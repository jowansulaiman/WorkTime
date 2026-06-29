import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/clock_service.dart';
import '../core/monatsabschluss_service.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/clock_entry.dart';
import '../models/payroll_record.dart';
import '../models/work_entry.dart';
import '../models/zeitkonto_snapshot.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Zeitwirtschaft-Provider (M3): besitzt die persistenten **Stempel-Sessions**
/// ([ClockEntry], Kommen/Gehen). Bewusst **additiv** zum bestehenden ephemeren
/// `WorkProvider`-Clock — die UI-Migration (Stempel-Screen/FAB) + die Erzeugung
/// eines `WorkEntry(status: submitted)` beim Ausstempeln folgen in M3b-2.
///
/// Stundenkonto-Snapshots + Monatsabschluss ziehen später (M4/M5) hier ein.
class ZeitwirtschaftProvider extends ChangeNotifier {
  ZeitwirtschaftProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final bool _forceLocalStorage;
  final MonatsabschlussService _monatsabschluss = const MonatsabschlussService();

  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;
  bool _disposed = false;

  AppUserProfile? _currentUser;
  String? _lastSessionKey;
  String? sessionError;

  AuditSink? _audit;

  StreamSubscription<ClockEntry?>? _openSubscription;
  StreamSubscription<List<ClockEntry>>? _ongoingSubscription;
  ClockEntry? _openEntry;
  List<ClockEntry> _ongoingEntries = <ClockEntry>[];
  List<ClockEntry> _localEntries = <ClockEntry>[];
  List<ClockEntry> _monthEntries = <ClockEntry>[];
  DateTime _selectedMonth = _currentMonth();
  List<ZeitkontoSnapshot> _yearSnapshots = <ZeitkontoSnapshot>[];
  int _snapshotYear = _currentMonth().year;

  static DateTime _currentMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  // ── Storage-Modus ──────────────────────────────────────────────────────────
  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : usesHybridStorage
          ? 'hybrid'
          : 'cloud';

  // ── Öffentlicher Zustand ────────────────────────────────────────────────────
  ClockEntry? get openEntry => _openEntry;
  bool get isClockedIn => _openEntry != null;
  DateTime? get clockInTime => _openEntry?.kommen;

  /// Aktuell laufende Buchungen der Org („wer ist eingestempelt") — nur für
  /// Manager/Admin befüllt (Mitarbeiter sehen nur die eigene offene Buchung).
  List<ClockEntry> get ongoingEntries => _ongoingEntries;

  /// Eigene Buchungen des [selectedMonth].
  List<ClockEntry> get monthEntries => _monthEntries;
  DateTime get selectedMonth => _selectedMonth;

  /// Persistierte Stundenkonto-Snapshots des [snapshotYear] (eigene).
  List<ZeitkontoSnapshot> get yearSnapshots => _yearSnapshots;
  int get snapshotYear => _snapshotYear;
  ZeitkontoSnapshot? snapshotFor(int jahr, int monat) {
    for (final s in _yearSnapshots) {
      if (s.jahr == jahr && s.monat == monat) return s;
    }
    return null;
  }

  /// Vormonats-Snapshot (Übertragsquelle) des zuletzt via [loadCarryover]
  /// angeforderten Monats — deckt auch die **Jahresgrenze** (Januar → Dezember
  /// Vorjahr) ab, die der Jahres-Cache [yearSnapshots] nicht enthält.
  ZeitkontoSnapshot? _carryover;
  ZeitkontoSnapshot? get carryover => _carryover;

  /// Zuletzt angefragter Monat — schützt vor out-of-order abgeschlossenen
  /// Lade-Vorgängen bei schneller Monatsnavigation.
  DateTime? _carryoverRequest;

  /// Lädt den Vormonats-Snapshot des Nutzers für [month] als Übertragsquelle.
  /// Liegt der Vormonat bereits im Jahres-Cache, von dort (kein Read); sonst —
  /// **inkl. Jahresgrenze (Januar → Dezember Vorjahr)** — gezielt self-scoped
  /// laden (also auch für reguläre Mitarbeiter via zeitkontoSnapshots-Self-Read).
  /// Die Entscheidung Cache-vs-Read hängt an der **tatsächlichen Cache-
  /// Mitgliedschaft** ([snapshotFor]), NICHT am ggf. voreilig gesetzten
  /// [snapshotYear] (sonst Race gegen den noch ladenden Jahres-Cache).
  Future<void> loadCarryover(DateTime month) async {
    final request = DateTime(month.year, month.month);
    _carryoverRequest = request;
    final user = _currentUser;
    if (user == null) {
      _carryover = null;
      _safeNotify();
      return;
    }
    final prevMonth = month.month == 1 ? 12 : month.month - 1;
    final prevYear = month.month == 1 ? month.year - 1 : month.year;

    final cached = snapshotFor(prevYear, prevMonth);
    if (cached != null) {
      _carryover = cached;
      _safeNotify();
      return;
    }

    List<ZeitkontoSnapshot> list;
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: LocalStorageScope.fromUser(user),
      );
      list = all
          .where((s) => s.userId == user.uid && s.jahr == prevYear)
          .toList();
    } else {
      try {
        list = await _firestoreService.getZeitkontoSnapshotsForYear(
          orgId: user.orgId,
          userId: user.uid,
          jahr: prevYear,
        );
      } catch (error) {
        AppLogger.warning('Zeitwirtschaft: Übertrag laden fehlgeschlagen',
            error: error);
        list = const [];
      }
    }
    // Verworfen, falls inzwischen ein anderer Monat angefragt wurde.
    if (_carryoverRequest != request) return;
    ZeitkontoSnapshot? found;
    for (final s in list) {
      if (s.monat == prevMonth) {
        found = s;
        break;
      }
    }
    _carryover = found;
    _safeNotify();
  }

  /// Laufzeit der offenen Buchung relativ zu [now] (Default jetzt), in Minuten.
  int runningMinutes({DateTime? now}) {
    final entry = _openEntry;
    if (entry == null) return 0;
    return ClockService.runningMinutes(
      kommen: entry.kommen,
      now: now ?? DateTime.now(),
    );
  }

  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  /// Seam, über den ein abgeschlossenes Ausstempeln einen `WorkEntry` erzeugt
  /// (in `main.dart` mit `WorkProvider.addEntry` verdrahtet — Muster
  /// Finance→Personal). So fließt gestempelte Zeit ins Stundenkonto/Lohn.
  Future<void> Function(WorkEntry entry)? _workEntryPoster;
  void setWorkEntryPoster(Future<void> Function(WorkEntry entry) poster) {
    _workEntryPoster = poster;
  }

  /// Seam, über den der Monatsabschluss einen **Entwurfs-Lohndatensatz** ablegt
  /// (in `main.dart` mit `PersonalProvider.savePayrollRecord` verdrahtet — Muster
  /// `_workEntryPoster`). Hält den `ZeitwirtschaftProvider` von der
  /// PersonalProvider-Abhängigkeit frei.
  Future<void> Function(PayrollRecord record)? _payrollDraftPoster;
  void setPayrollDraftPoster(Future<void> Function(PayrollRecord record) poster) {
    _payrollDraftPoster = poster;
  }

  void surfaceSessionError(Object error) {
    sessionError = error.toString();
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _openSubscription?.cancel();
    _ongoingSubscription?.cancel();
    super.dispose();
  }

  // ── Session ─────────────────────────────────────────────────────────────────
  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey) {
      _currentUser = user;
      return;
    }
    _lastSessionKey = sessionKey;
    _currentUser = user;

    await _openSubscription?.cancel();
    _openSubscription = null;
    await _ongoingSubscription?.cancel();
    _ongoingSubscription = null;
    _ongoingEntries = <ClockEntry>[];

    if (user == null) {
      _openEntry = null;
      _localEntries = <ClockEntry>[];
      _monthEntries = <ClockEntry>[];
      _yearSnapshots = <ZeitkontoSnapshot>[];
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _openSubscription = _firestoreService
          .watchOpenClockEntry(orgId: user.orgId, userId: user.uid)
          .listen(
        (entry) {
          _openEntry = entry;
          _safeNotify();
        },
        onError: (Object error) {
          AppLogger.warning('Zeitwirtschaft: open-clock-stream Fehler',
              error: error);
        },
      );
      // Org-weite „wer ist eingestempelt"-Sicht nur für Manager/Admin (Rules
      // erlauben Mitarbeitern nur eigene Reads).
      if (user.canManageShifts) {
        _ongoingSubscription = _firestoreService
            .watchOngoingClockEntries(orgId: user.orgId)
            .listen(
          (entries) {
            _ongoingEntries = entries;
            _safeNotify();
          },
          onError: (Object error) {
            AppLogger.warning('Zeitwirtschaft: ongoing-clock-stream Fehler',
                error: error);
          },
        );
      }
    } else {
      await _loadLocal();
      _recomputeOpenFromLocal();
    }
    await _loadMonthEntries();
    _safeNotify();
  }

  /// Wechselt den angezeigten Monat (Stempel-Screen) und lädt dessen Buchungen.
  Future<void> selectMonth(DateTime month) async {
    _selectedMonth = DateTime(month.year, month.month);
    await _loadMonthEntries();
    _safeNotify();
  }

  Future<void> _loadMonthEntries() async {
    final user = _currentUser;
    if (user == null) {
      _monthEntries = <ClockEntry>[];
      return;
    }
    final start = DateTime(_selectedMonth.year, _selectedMonth.month);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (usesLocalStorage) {
      _monthEntries = _localEntries
          .where((e) =>
              e.userId == user.uid &&
              !e.kommen.isBefore(start) &&
              e.kommen.isBefore(end))
          .toList()
        ..sort((a, b) => b.kommen.compareTo(a.kommen));
      return;
    }
    try {
      _monthEntries = await _firestoreService.getClockEntriesInRange(
        orgId: user.orgId,
        userId: user.uid,
        start: start,
        end: end,
      );
    } catch (error) {
      AppLogger.warning('Zeitwirtschaft: Monatsbuchungen laden fehlgeschlagen',
          error: error);
      _monthEntries = <ClockEntry>[];
    }
  }

  /// Lädt die persistierten Stundenkonto-Snapshots des Nutzers für ein Jahr.
  Future<void> loadSnapshots(int jahr) async {
    _snapshotYear = jahr;
    final user = _currentUser;
    if (user == null) {
      _yearSnapshots = <ZeitkontoSnapshot>[];
      _safeNotify();
      return;
    }
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: LocalStorageScope.fromUser(user),
      );
      _yearSnapshots = all
          .where((s) => s.userId == user.uid && s.jahr == jahr)
          .toList()
        ..sort((a, b) => a.monat.compareTo(b.monat));
    } else {
      try {
        _yearSnapshots = await _firestoreService.getZeitkontoSnapshotsForYear(
          orgId: user.orgId,
          userId: user.uid,
          jahr: jahr,
        );
      } catch (error) {
        AppLogger.warning('Zeitwirtschaft: Snapshots laden fehlgeschlagen',
            error: error);
        _yearSnapshots = <ZeitkontoSnapshot>[];
      }
    }
    _safeNotify();
  }

  /// Persistiert einen Stundenkonto-Snapshot (Auszahlung/Anzeige, M5).
  Future<void> saveSnapshot(ZeitkontoSnapshot snapshot) async {
    final user = _currentUser;
    if (user == null) return;
    final id = ZeitkontoSnapshot.buildId(
        snapshot.userId, snapshot.jahr, snapshot.monat);
    // createdAt des bestehenden Snapshots bewahren (sonst stempelt der
    // toFirestoreMap-Guard bei jedem Abschluss-Upsert ein neues createdAt).
    final existing = snapshotFor(snapshot.jahr, snapshot.monat);
    final withId = snapshot.copyWith(
      id: id,
      createdAt: snapshot.createdAt ?? existing?.createdAt,
    );
    await _writeSnapshot(withId);
    if (withId.jahr == _snapshotYear && withId.userId == user.uid) {
      _upsertYearSnapshot(withId);
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Stundenkonto',
      entityId: id,
      summary: 'Stundenkonto ${snapshot.monat}/${snapshot.jahr} aktualisiert',
    );
    _safeNotify();
  }

  /// Schreibt einen Snapshot in den aktiven Speicher (lokal / Cloud mit
  /// Hybrid-Fallback) — **ohne** Audit/Cache/Notify. [snapshot] muss bereits die
  /// deterministische Doc-ID tragen.
  Future<void> _writeSnapshot(ZeitkontoSnapshot snapshot) async {
    if (usesLocalStorage) {
      await _persistLocalSnapshotUpsert(snapshot);
      return;
    }
    try {
      await _firestoreService.saveZeitkontoSnapshot(snapshot);
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      await _persistLocalSnapshotUpsert(snapshot);
    }
  }

  /// **Monatsabschluss** (M5): validiert ([MonatsabschlussService]), sperrt den
  /// Snapshot und legt — falls vorhanden — einen Entwurfs-Lohndatensatz ab. Gibt
  /// die Validierung zurück; bei `canClose == false` wird **nichts** geschrieben.
  /// [actorUid] = schließender Nutzer (Default: Sitzungsnutzer; im Admin-Hub die
  /// Admin-uid). [liveSnapshot] sollte `createdAt`/`ausgezahltMinutes` des
  /// bestehenden Snapshots bereits tragen (für Fremd-Snapshots übergibt der
  /// Admin-Hub sie aus dem geladenen Org-Snapshot).
  Future<MonatsabschlussValidation> closeMonth({
    required ZeitkontoSnapshot liveSnapshot,
    required List<WorkEntry> monthEntries,
    required ZeitkontoSnapshot? vormonat,
    PayrollRecord? draftPayroll,
    String? actorUid,
    DateTime? now,
  }) async {
    final user = _currentUser;
    if (user == null) {
      return const MonatsabschlussValidation(
        canClose: false,
        errors: ['Keine aktive Sitzung.'],
      );
    }
    final clock = now ?? DateTime.now();
    final validation = _monatsabschluss.validate(
      snapshot: liveSnapshot,
      entries: monthEntries,
      vormonat: vormonat,
      now: clock,
    );
    if (!validation.canClose) return validation;

    final id = ZeitkontoSnapshot.buildId(
        liveSnapshot.userId, liveSnapshot.jahr, liveSnapshot.monat);
    // createdAt nur aus dem Year-Cache übernehmen, wenn es derselbe Nutzer ist —
    // der Cache hält nur die eigenen Snapshots des Sitzungsnutzers; für fremde
    // Snapshots (Admin-Hub) liefert der Aufrufer createdAt im liveSnapshot.
    final cached = snapshotFor(liveSnapshot.jahr, liveSnapshot.monat);
    final cachedCreatedAt =
        cached?.userId == liveSnapshot.userId ? cached?.createdAt : null;
    final base = liveSnapshot.copyWith(
      id: id,
      createdAt: liveSnapshot.createdAt ?? cachedCreatedAt,
    );
    final locked = _monatsabschluss.applyLock(
      base,
      von: actorUid ?? user.uid,
      am: clock,
    );
    await _writeSnapshot(locked);
    if (locked.jahr == _snapshotYear && locked.userId == user.uid) {
      _upsertYearSnapshot(locked);
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Monatsabschluss',
      entityId: id,
      summary: 'Monat ${liveSnapshot.monat}/${liveSnapshot.jahr} abgeschlossen',
    );
    // Entwurfs-Lohndatensatz best-effort — nur Admins dürfen `payrollRecords`
    // schreiben (`_assertAdmin` im PersonalProvider). Ein Schichtleiter darf zwar
    // den Snapshot sperren (`canManageShifts`), erzeugt aber keinen Lohn-Entwurf;
    // der Poster würde sonst nur erfolglos werfen. Ein Fehler bricht den bereits
    // gespeicherten Abschluss NICHT ab.
    if (draftPayroll != null &&
        _payrollDraftPoster != null &&
        (user.isAdmin)) {
      try {
        await _payrollDraftPoster!(draftPayroll);
      } catch (error) {
        AppLogger.warning(
            'Zeitwirtschaft: Entwurfs-Lohndatensatz fehlgeschlagen',
            error: error);
      }
    }
    _safeNotify();
    return validation;
  }

  /// Nimmt einen Monatsabschluss zurück (Unlock) — Zeiteinträge werden dadurch
  /// wieder bearbeitbar. [snapshot] ist der bereits persistierte (gesperrte).
  Future<void> reopenMonth(
    ZeitkontoSnapshot snapshot, {
    String? actorUid,
  }) async {
    final user = _currentUser;
    if (user == null) return;
    final id = ZeitkontoSnapshot.buildId(
        snapshot.userId, snapshot.jahr, snapshot.monat);
    final unlocked = _monatsabschluss.applyUnlock(snapshot).copyWith(id: id);
    await _writeSnapshot(unlocked);
    if (unlocked.jahr == _snapshotYear && unlocked.userId == user.uid) {
      _upsertYearSnapshot(unlocked);
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Monatsabschluss',
      entityId: id,
      summary:
          'Monatsabschluss ${snapshot.monat}/${snapshot.jahr} zurückgenommen',
    );
    _safeNotify();
  }

  // ── Org-weite Lese-Helfer (Mitarbeiterabschluss-Hub, M5) ────────────────────
  /// Zeiteinträge **aller** Mitarbeiter eines Monats (org-weit). Cloud/Hybrid via
  /// Firestore (`canManageShifts`-Rules), Local aus dem org-skopierten Cache.
  Future<List<WorkEntry>> loadOrgWorkEntriesForMonth(DateTime month) async {
    final user = _currentUser;
    if (user == null) return const [];
    final first = DateTime(month.year, month.month);
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(user),
      );
      return all
          .where(
              (e) => e.date.year == first.year && e.date.month == first.month)
          .toList();
    }
    try {
      return await _firestoreService.getOrgWorkEntriesForMonth(
        orgId: user.orgId,
        month: first,
      );
    } catch (error) {
      AppLogger.warning('Zeitwirtschaft: Org-Monatszeiten laden fehlgeschlagen',
          error: error);
      return const [];
    }
  }

  /// Genehmigte Abwesenheiten **aller** Mitarbeiter, die [month] berühren.
  Future<List<AbsenceRequest>> loadOrgApprovedAbsencesForMonth(
      DateTime month) async {
    final user = _currentUser;
    if (user == null) return const [];
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalAbsenceRequests(
        scope: LocalStorageScope.fromUser(user),
      );
      return all
          .where((a) =>
              a.status == AbsenceStatus.approved &&
              a.startDate.isBefore(end) &&
              !a.endDate.isBefore(start))
          .toList();
    }
    try {
      return await _firestoreService.getApprovedAbsencesInRange(
        orgId: user.orgId,
        start: start,
        end: end,
      );
    } catch (error) {
      AppLogger.warning('Zeitwirtschaft: Org-Abwesenheiten laden fehlgeschlagen',
          error: error);
      return const [];
    }
  }

  /// Persistierte Monats-Snapshots **aller** Mitarbeiter für [jahr]/[monat].
  Future<List<ZeitkontoSnapshot>> loadOrgSnapshotsForMonth(
      int jahr, int monat) async {
    final user = _currentUser;
    if (user == null) return const [];
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: LocalStorageScope.fromUser(user),
      );
      return all.where((s) => s.jahr == jahr && s.monat == monat).toList();
    }
    try {
      return await _firestoreService.getOrgZeitkontoSnapshotsForMonth(
        orgId: user.orgId,
        jahr: jahr,
        monat: monat,
      );
    } catch (error) {
      AppLogger.warning('Zeitwirtschaft: Org-Snapshots laden fehlgeschlagen',
          error: error);
      return const [];
    }
  }

  void _upsertYearSnapshot(ZeitkontoSnapshot snapshot) {
    final next = List<ZeitkontoSnapshot>.from(_yearSnapshots);
    final index = next.indexWhere((s) => s.id == snapshot.id);
    if (index >= 0) {
      next[index] = snapshot;
    } else {
      next.add(snapshot);
    }
    next.sort((a, b) => a.monat.compareTo(b.monat));
    _yearSnapshots = next;
  }

  Future<void> _persistLocalSnapshotUpsert(ZeitkontoSnapshot snapshot) async {
    final user = _currentUser;
    if (user == null) return;
    final scope = LocalStorageScope.fromUser(user);
    final all = await DatabaseService.loadLocalZeitkontoSnapshots(scope: scope);
    final next = List<ZeitkontoSnapshot>.from(all);
    final index = next.indexWhere((s) => s.id == snapshot.id);
    if (index >= 0) {
      next[index] = snapshot;
    } else {
      next.add(snapshot);
    }
    await DatabaseService.saveLocalZeitkontoSnapshots(next, scope: scope);
  }

  // ── Stempeln ──────────────────────────────────────────────────────────────
  /// Einstempeln. No-Op, wenn bereits eine offene Buchung läuft.
  Future<void> clockIn({String? siteId, String? siteName, DateTime? at}) async {
    final user = _currentUser;
    // Stempeln braucht Bearbeitungsrecht (wie WorkProvider-Clock + firestore.rules);
    // sonst entstünde nur lokal eine Geister-Buchung ohne WorkEntry.
    if (user == null || !user.canEditTimeEntries || isClockedIn) {
      return;
    }
    final entry = ClockEntry(
      id: 'clock-${DateTime.now().microsecondsSinceEpoch}',
      orgId: user.orgId,
      userId: user.uid,
      userName: user.settings.name,
      siteId: siteId,
      siteName: siteName,
      kommen: at ?? DateTime.now(),
      status: ClockStatus.ongoing,
      createdByUid: user.uid,
    );
    await _persist(entry, ongoing: true);
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Stempelzeit',
      entityId: entry.id,
      summary: 'Eingestempelt${siteName != null ? ' · $siteName' : ''}',
    );
    await _loadMonthEntries();
    _safeNotify();
  }

  /// Ausstempeln der laufenden Buchung: Auto-Pflichtpause + Netto via
  /// [ClockService]; ein Kommen vom Vortag wird als Klärung markiert.
  Future<void> clockOut({
    int? pauseMinuten,
    String? anmerkung,
    DateTime? at,
  }) async {
    final open = _openEntry;
    final user = _currentUser;
    if (open == null || user == null || !user.canEditTimeEntries) {
      return;
    }
    final now = at ?? DateTime.now();
    final pause = ClockService.effectivePauseMinutes(
      kommen: open.kommen,
      gehen: now,
      pauseMinuten: pauseMinuten,
    );
    final netto = ClockService.netMinutes(
      kommen: open.kommen,
      gehen: now,
      pauseMinuten: pause,
    );
    final needsKlaerung = ClockService.needsClarification(
      kommen: open.kommen,
      now: now,
    );
    final updated = open.copyWith(
      gehen: now,
      pauseMinuten: pause,
      nettoMinutes: netto,
      status: needsKlaerung ? ClockStatus.klaerung : ClockStatus.completed,
      klaerung: needsKlaerung,
      anmerkung: anmerkung,
    );
    await _persist(updated, ongoing: false);
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Stempelzeit',
      entityId: updated.id,
      summary:
          'Ausgestempelt (${(netto / 60).toStringAsFixed(1)} h)${needsKlaerung ? ' · Klärung' : ''}',
    );
    // Sauber abgeschlossene Buchung → WorkEntry(submitted) erzeugen (best-effort;
    // Klärungsfälle erst nach Klärung). Ein Fehler (z. B. Compliance) bricht das
    // bereits gespeicherte Ausstempeln NICHT ab.
    if (!needsKlaerung && _workEntryPoster != null) {
      final workEntry = WorkEntry(
        orgId: updated.orgId,
        userId: updated.userId,
        date: open.kommen,
        startTime: open.kommen,
        endTime: now,
        breakMinutes: pause.toDouble(),
        siteId: updated.siteId,
        siteName: updated.siteName,
        note: anmerkung,
        category: 'stempel',
        status: WorkEntryStatus.submitted,
        sourceClockEntryId: updated.id,
      );
      try {
        await _workEntryPoster!(workEntry);
      } catch (error) {
        AppLogger.warning(
            'Zeitwirtschaft: WorkEntry aus Stempelzeit fehlgeschlagen',
            error: error);
        // Nicht still verlieren: sichtbar machen, damit der Eintrag in der
        // Zeiterfassung nachgepflegt werden kann (z. B. Pausen-/Compliance-Regel).
        sessionError =
            'Die gestempelte Zeit konnte nicht als Zeiteintrag übernommen werden. '
            'Bitte in der Zeiterfassung prüfen.';
      }
    }
    await _loadMonthEntries();
    _safeNotify();
  }

  // ── Persistenz (lokal / Cloud / Hybrid-Fallback) ────────────────────────────
  Future<void> _persist(ClockEntry entry, {required bool ongoing}) async {
    if (usesLocalStorage) {
      _upsertLocal(entry);
      await _persistLocal();
      _recomputeOpenFromLocal();
      _safeNotify();
      return;
    }
    try {
      await _firestoreService.saveClockEntry(entry);
      // Cloud: der watch-Stream aktualisiert _openEntry; optimistisch sofort
      // setzen, damit die UI nicht auf den Stream warten muss.
      _openEntry = ongoing ? entry : null;
      _safeNotify();
    } catch (error) {
      if (!usesHybridStorage) {
        rethrow;
      }
      _upsertLocal(entry);
      await _persistLocal();
      _recomputeOpenFromLocal();
      _safeNotify();
    }
  }

  void _upsertLocal(ClockEntry entry) {
    final next = List<ClockEntry>.from(_localEntries);
    final index = next.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      next[index] = entry;
    } else {
      next.add(entry);
    }
    _localEntries = next;
  }

  void _recomputeOpenFromLocal() {
    final uid = _currentUser?.uid;
    ClockEntry? open;
    for (final entry in _localEntries) {
      if (entry.userId == uid && entry.isOngoing) {
        open = entry;
        break;
      }
    }
    _openEntry = open;
    // Im Local-Modus gibt es keinen org-weiten Stream — die „wer ist
    // eingestempelt"-Karte zeigt dann zumindest die eigene offene Buchung.
    _ongoingEntries = open == null ? <ClockEntry>[] : <ClockEntry>[open];
  }

  Future<void> _loadLocal() async {
    final user = _currentUser;
    if (user == null) {
      _localEntries = <ClockEntry>[];
      return;
    }
    _localEntries = await DatabaseService.loadLocalClockEntries(
      scope: LocalStorageScope.fromUser(user),
    );
  }

  Future<void> _persistLocal() async {
    final user = _currentUser;
    if (user == null) return;
    await DatabaseService.saveLocalClockEntries(
      _localEntries,
      scope: LocalStorageScope.fromUser(user),
    );
  }

  // ── Speichermodus-Migration (CLAUDE.md-Footgun: beide Richtungen!) ──────────
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    // Im Cloud/Hybrid-Modus pflegt der Stream nur die offene Buchung; für den
    // lokalen Cache reicht sie (abgeschlossene Buchungen liegen im Firestore-
    // Offline-Cache). Offene Buchung lokal spiegeln, damit sie offline sichtbar
    // bleibt.
    final open = _openEntry;
    if (open != null) {
      _upsertLocal(open);
      await _persistLocal();
    }
    // Geladene Jahres-Snapshots ebenfalls lokal spiegeln.
    for (final snapshot in List<ZeitkontoSnapshot>.from(_yearSnapshots)) {
      await _persistLocalSnapshotUpsert(snapshot);
    }
  }

  Future<void> syncLocalStateToCloud() async {
    if (usesLocalStorage) return;
    final user = _currentUser;
    for (final entry in List<ClockEntry>.from(_localEntries)) {
      try {
        await _firestoreService.saveClockEntry(entry);
      } catch (error) {
        AppLogger.warning('Zeitwirtschaft: syncLocalStateToCloud Fehler',
            error: error);
      }
    }
    if (user != null) {
      final localSnapshots = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: LocalStorageScope.fromUser(user),
      );
      for (final snapshot in localSnapshots) {
        try {
          await _firestoreService.saveZeitkontoSnapshot(snapshot);
        } catch (error) {
          AppLogger.warning('Zeitwirtschaft: Snapshot-Sync Fehler',
              error: error);
        }
      }
    }
  }
}
