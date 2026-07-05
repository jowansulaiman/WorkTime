import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/clock_service.dart';
import '../core/dienst_abgleich.dart';
import '../core/monats_festschreibung.dart';
import '../core/monatsabschluss_service.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/clock_entry.dart';
import '../models/payroll_record.dart';
import '../models/shift.dart';
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

  StreamSubscription<({ClockEntry? entry, bool pending, bool fromCache})>?
      _openSubscription;
  StreamSubscription<List<ClockEntry>>? _ongoingSubscription;
  StreamSubscription<List<ClockEntry>>? _klaerungSubscription;
  ClockEntry? _openEntry;
  bool _openEntryPending = false;
  List<ClockEntry> _ongoingEntries = <ClockEntry>[];
  List<ClockEntry> _klaerungEntries = <ClockEntry>[];
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

  /// Offene Klärungsfälle der Org (ZV-3.1) — nur für Manager/Admin befüllt,
  /// nach `kommen` absteigend sortiert.
  List<ClockEntry> get klaerungEntries => _klaerungEntries;

  /// Hat die eigene offene Buchung noch nicht bestätigte lokale Schreibvorgänge
  /// (offline gepuffert, ZV-1.2)? Treibt das „ausstehend"-Badge.
  bool get openEntryPending => _openEntryPending;

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

  /// Seam für die Abrechnungssperre (PA-5.2): liefert den [PayrollStatus] der
  /// Lohnabrechnung eines Mitarbeiter-Monats (oder `null`, wenn keine
  /// existiert). In `main.dart` mit `PersonalProvider.payrollForUserPeriod`
  /// verdrahtet — gleiches Entkopplungs-Muster wie [_payrollDraftPoster].
  PayrollStatus? Function(String userId, int jahr, int monat)?
      _payrollStatusLookup;
  void setPayrollStatusLookup(
      PayrollStatus? Function(String userId, int jahr, int monat) lookup) {
    _payrollStatusLookup = lookup;
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
    _klaerungSubscription?.cancel();
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
    await _klaerungSubscription?.cancel();
    _klaerungSubscription = null;
    _ongoingEntries = <ClockEntry>[];
    _klaerungEntries = <ClockEntry>[];
    _openEntryPending = false;

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
          .watchOpenClockEntryMeta(orgId: user.orgId, userId: user.uid)
          .listen(
        (snapshot) {
          _openEntry = snapshot.entry;
          _openEntryPending = snapshot.pending;
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
        _klaerungSubscription = _firestoreService
            .watchKlaerungClockEntries(orgId: user.orgId)
            .listen(
          (entries) {
            final sorted = List<ClockEntry>.from(entries)
              ..sort((a, b) => b.kommen.compareTo(a.kommen));
            _klaerungEntries = sorted;
            _safeNotify();
          },
          onError: (Object error) {
            AppLogger.warning('Zeitwirtschaft: klaerung-clock-stream Fehler',
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

  /// Lädt die Einmal-Read-Sichten (Monatsbuchungen + Jahres-Snapshots) neu
  /// (ZV-1.4). Von App-Resume / Reconnect-Flanke aufgerufen, damit die nicht-
  /// gestreamten Sichten selbstheilend werden. Streams (offene Buchung, org-weit,
  /// Klärung) aktualisieren sich ohnehin selbst.
  Future<void> refetch() async {
    if (_currentUser == null) return;
    if (usesLocalStorage) {
      await _loadLocal();
      _recomputeOpenFromLocal();
    }
    await _loadMonthEntries();
    await loadSnapshots(_snapshotYear);
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
    int offeneKlaerungen = 0,
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
    // PA-5: Laufende (ongoing) Stempelungen des Ziel-Mitarbeiters, deren Kommen
    // im/vor dem Zielmonat liegt, blockieren den Abschluss — sonst würde das
    // spätere Ausstempeln einen WorkEntry in den festgeschriebenen Monat
    // erzwingen. Aus dem Live-Zustand des Providers abgeleitet (eigene offene
    // Buchung + org-weiter Manager-Stream), per ID dedupliziert.
    final monatsEnde = DateTime(
        liveSnapshot.jahr, liveSnapshot.monat + 1, 1)
        .subtract(const Duration(seconds: 1));
    final offeneStempelungen = <String?>{
      for (final e in [
        if (_openEntry != null) _openEntry!,
        ..._ongoingEntries,
      ])
        if (e.userId == liveSnapshot.userId &&
            e.status == ClockStatus.ongoing &&
            !e.kommen.isAfter(monatsEnde))
          e.id,
    }.length;
    final validation = _monatsabschluss.validate(
      snapshot: liveSnapshot,
      entries: monthEntries,
      vormonat: vormonat,
      now: clock,
      offeneKlaerungen: offeneKlaerungen,
      offeneStempelungen: offeneStempelungen,
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
  ///
  /// **Admin-only** (PA-5.2, in den Rules gespiegelt: `zeitkontoSnapshots`-
  /// update auf gesperrten Snapshots nur `isAdmin`). Zusätzlich gesperrt, wenn
  /// die Lohnabrechnung des Monats bereits **freigegeben/bezahlt** ist — dann
  /// wäre das Zeitkonto rückwirkend änderbar, obwohl der Lohn schon auf dem
  /// festgeschriebenen Stand basiert. Weg: Lohnabrechnung zuerst stornieren
  /// (`setPayrollStatus(storniert)`), dann Reopen.
  Future<void> reopenMonth(
    ZeitkontoSnapshot snapshot, {
    String? actorUid,
  }) async {
    final user = _currentUser;
    if (user == null) return;
    if (!user.isAdmin) {
      throw StateError(
          'Nur Admins dürfen einen Monatsabschluss zurücknehmen.');
    }
    final payrollStatus = _payrollStatusLookup?.call(
        snapshot.userId, snapshot.jahr, snapshot.monat);
    if (payrollStatus == PayrollStatus.freigegeben ||
        payrollStatus == PayrollStatus.bezahlt) {
      throw StateError(
          'Die Lohnabrechnung ${snapshot.monat.toString().padLeft(2, '0')}/'
          '${snapshot.jahr} ist bereits ${payrollStatus!.label.toLowerCase()} '
          '— bitte zuerst im Lohnlauf stornieren, dann den Monatsabschluss '
          'zurücknehmen.');
    }
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
      // Z3: CLAUDE.md-Fehlermuster — im Hybrid lokal zurückfallen, im cloud-only
      // weiterwerfen (Fehler nicht still als „keine Daten" verschlucken).
      if (!usesHybridStorage) rethrow;
      AppLogger.warning(
          'Zeitwirtschaft: Org-Monatszeiten offline – lokaler Fallback',
          error: error);
      final all = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(user),
      );
      return all
          .where(
              (e) => e.date.year == first.year && e.date.month == first.month)
          .toList();
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
  ///
  /// [shiftId] verknüpft den Stempel mit der geplanten Schicht (ZV-2.1); das
  /// beim Ausstempeln erzeugte `WorkEntry` erbt sie als `sourceShiftId`
  /// (Schicht-Completion-Hook).
  Future<void> clockIn({
    String? siteId,
    String? siteName,
    String? shiftId,
    DateTime? at,
  }) async {
    final user = _currentUser;
    // Stempeln braucht Bearbeitungsrecht (wie WorkProvider-Clock + firestore.rules);
    // sonst entstünde nur lokal eine Geister-Buchung ohne WorkEntry.
    if (user == null || !user.canEditTimeEntries || isClockedIn) {
      return;
    }
    // PA-4.1: Im Cloud-/Hybrid-Modus läuft die offene Buchung unter der
    // deterministischen Doc-ID `{userId}-open` (Transaktion mit Existenz-Check
    // = harter Doppel-Stempel-Guard über Geräte hinweg). Local-Modus und der
    // hybrid-Offline-Fallback nutzen weiter zufällige IDs (ein Gerät, keine
    // Concurrency; und ein lokales `-open`-Doc würde beim Schließen in place
    // die ID des nächsten clockIn blockieren).
    final randomId = 'clock-${DateTime.now().microsecondsSinceEpoch}';
    final entry = ClockEntry(
      id: usesLocalStorage
          ? randomId
          : FirestoreService.openClockDocId(user.uid),
      orgId: user.orgId,
      userId: user.uid,
      userName: user.settings.name,
      siteId: siteId,
      siteName: siteName,
      shiftId: shiftId,
      source: 'app',
      kommen: at ?? DateTime.now(),
      status: ClockStatus.ongoing,
      createdByUid: user.uid,
    );
    if (usesLocalStorage) {
      await _persist(entry, ongoing: true);
    } else {
      try {
        await _firestoreService.clockInOpen(entry);
        _openEntry = entry;
        _safeNotify();
      } on StateError {
        // Doppel-Stempel-Guard hat gegriffen (anderes Gerät) — deutsche
        // Meldung an die UI durchreichen, NICHT lokal fallbacken.
        rethrow;
      } catch (error) {
        if (!usesHybridStorage) rethrow;
        // Hybrid offline: lokale Buchung mit zufälliger ID (Rück-Sync über
        // syncLocalStateToCloud; clockOut nimmt dann den Legacy-Pfad).
        final localEntry = entry.copyWith(id: randomId);
        _upsertLocal(localEntry);
        await _persistLocal();
        _recomputeOpenFromLocal();
        _safeNotify();
      }
    }
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Stempelzeit',
      entityId: _openEntry?.id ?? entry.id,
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
    // PA-4.1: Lief die Buchung unter der deterministischen `{userId}-open`-ID
    // (Cloud-/Hybrid-clockIn), wird sie beim Schließen transaktional unter ihre
    // endgültige ID kopiert und das open-Doc gelöscht — die open-ID ist damit
    // für den nächsten clockIn frei. Local-Modus und Alt-Buchungen (zufällige
    // ID, Übergangsphase) schließen wie bisher in place.
    final istOpenDoc = !usesLocalStorage &&
        open.id == FirestoreService.openClockDocId(user.uid);
    var persisted = updated;
    if (istOpenDoc) {
      final closed = updated.copyWith(
          id: 'clock-${DateTime.now().microsecondsSinceEpoch}');
      try {
        await _firestoreService.closeOpenClockEntry(
          orgId: user.orgId,
          userId: user.uid,
          closed: closed,
        );
        persisted = closed;
        _openEntry = null;
        _safeNotify();
      } catch (error) {
        if (!usesHybridStorage) rethrow;
        // Hybrid offline: geschlossene Buchung lokal ablegen (Rück-Sync via
        // syncLocalStateToCloud); das Cloud-open-Doc räumt der Rück-Sync bzw.
        // der nächste Online-clockOut ab.
        persisted = closed;
        _upsertLocal(closed);
        await _persistLocal();
        _recomputeOpenFromLocal();
        _safeNotify();
      }
    } else {
      await _persist(updated, ongoing: false);
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Stempelzeit',
      entityId: persisted.id,
      summary:
          'Ausgestempelt (${(netto / 60).toStringAsFixed(1)} h)${needsKlaerung ? ' · Klärung' : ''}',
    );
    // Sauber abgeschlossene Buchung → WorkEntry(submitted) erzeugen (best-effort;
    // Klärungsfälle erst nach Klärung). Ein Fehler (z. B. Compliance) bricht das
    // bereits gespeicherte Ausstempeln NICHT ab.
    if (!needsKlaerung && _workEntryPoster != null) {
      final workEntry = WorkEntry(
        orgId: persisted.orgId,
        userId: persisted.userId,
        date: open.kommen,
        startTime: open.kommen,
        endTime: now,
        breakMinutes: pause.toDouble(),
        siteId: persisted.siteId,
        siteName: persisted.siteName,
        sourceShiftId: persisted.shiftId,
        note: anmerkung,
        category: 'stempel',
        status: WorkEntryStatus.submitted,
        // Rückverweis auf die ENDGÜLTIGE Doc-ID (nach dem PA-4.1-copy+delete),
        // nicht auf die wiederverwendbare `{userId}-open`-ID.
        sourceClockEntryId: persisted.id,
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

  // ── Dienst-heute Soll-Ist (ZV-2.2b) ─────────────────────────────────────────
  /// Berechnet den Soll-Ist-Abgleich des Tages (verspätet / nicht erschienen /
  /// früher gegangen / ungeplant) für die Manager-Tagessicht. Lädt die org-weiten
  /// Schichten + Stempelungen + genehmigten Abwesenheiten des Tages selbst; nur
  /// Manager/Admin. Cloud/Hybrid via Firestore, Local aus dem (i. d. R. eigenen)
  /// Cache (dokumentierte Degradation — ohne Cloud keine org-weite Sicht).
  Future<List<DienstAbgleich>> loadDienstHeute({DateTime? now}) async {
    final user = _currentUser;
    if (user == null || !user.canManageShifts) return const [];
    final clock = now ?? DateTime.now();
    final dayStart = DateTime(clock.year, clock.month, clock.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    List<ClockEntry> stempel;
    List<Shift> schichten;
    List<AbsenceRequest> abwesenheiten;

    if (usesLocalStorage) {
      stempel = _localEntries
          .where((e) => !e.kommen.isBefore(dayStart) && e.kommen.isBefore(dayEnd))
          .toList();
      // Ohne Cloud kein org-weiter Schicht-/Abwesenheits-Zugriff.
      schichten = const [];
      abwesenheiten = const [];
    } else {
      try {
        final results = await Future.wait([
          _firestoreService.getOrgClockEntriesForDay(
              orgId: user.orgId, day: clock),
          _firestoreService.getShiftsInRange(
              orgId: user.orgId, start: dayStart, end: dayEnd),
          _firestoreService.getApprovedAbsencesInRange(
              orgId: user.orgId, start: dayStart, end: dayEnd),
        ]);
        stempel = results[0] as List<ClockEntry>;
        schichten = results[1] as List<Shift>;
        abwesenheiten = results[2] as List<AbsenceRequest>;
      } catch (error) {
        AppLogger.warning('Zeitwirtschaft: Dienst-heute laden fehlgeschlagen',
            error: error);
        // Live-Fallback: wenigstens die laufenden Buchungen zeigen.
        stempel = _ongoingEntries
            .where(
                (e) => !e.kommen.isBefore(dayStart) && e.kommen.isBefore(dayEnd))
            .toList();
        schichten = const [];
        abwesenheiten = const [];
      }
    }

    return DienstAbgleichService.berechne(
      schichten: schichten,
      stempel: stempel,
      abwesenheiten: abwesenheiten,
      now: clock,
    );
  }

  // ── Klärung & Korrektur (ZV-3) ──────────────────────────────────────────────
  /// Anzahl offener Klärungsfälle eines Nutzers im [month] (ZV-5.2, aus dem
  /// org-weiten Klärungs-Stream gefiltert — kein zusätzlicher Read). Für den
  /// Monatsabschluss-Blocker.
  int openKlaerungenCountForMonth(String userId, DateTime month) {
    return _klaerungEntries
        .where((e) =>
            e.userId == userId &&
            e.kommen.year == month.year &&
            e.kommen.month == month.month)
        .length;
  }

  /// Lädt den Monats-Snapshot für den Festschreibungs-Guard (PA-5) — Storage-
  /// modus-bewusst (SharedPreferences im Local-Modus, sonst Firestore).
  Future<ZeitkontoSnapshot?> _ladeZeitkontoSnapshot(
    String userId,
    int jahr,
    int monat,
  ) async {
    final user = _currentUser;
    if (user == null) return null;
    if (usesLocalStorage) {
      final all = await DatabaseService.loadLocalZeitkontoSnapshots(
        scope: LocalStorageScope.fromUser(user),
      );
      for (final s in all) {
        if (s.userId == userId && s.jahr == jahr && s.monat == monat) return s;
      }
      return null;
    }
    return _firestoreService.getZeitkontoSnapshot(
      orgId: user.orgId,
      userId: userId,
      jahr: jahr,
      monat: monat,
    );
  }

  /// Festschreibungs-Guard (PA-5.1, Client-Schicht) für Stempel-Korrekturen:
  /// wirft [StateError], wenn der Monat von [datum] für [userId] bereits per
  /// Monatsabschluss festgeschrieben ist. Fail-open bei Ladefehlern (offline).
  Future<void> _assertMonatNichtFestgeschrieben(
    String userId,
    DateTime datum,
  ) =>
      MonatsFestschreibung.assertNichtFestgeschrieben(
        ladeSnapshot: _ladeZeitkontoSnapshot,
        userId: userId,
        datum: datum,
      );

  /// Löst einen Klärungsfall auf (ZV-3.1): setzt die korrekten Zeiten, schließt
  /// die Buchung (`completed`) und erzeugt — wie ein sauberes Ausstempeln — einen
  /// `WorkEntry(submitted)` (läuft durch die Compliance-Freigabe). Nur
  /// Manager/Admin. [grund] ist Pflicht (Korrektur-Historie + Audit).
  Future<void> resolveKlaerung(
    ClockEntry entry, {
    required DateTime kommen,
    required DateTime gehen,
    int? pauseMinuten,
    required String grund,
  }) async {
    final user = _currentUser;
    if (user == null || !user.canManageShifts) return;
    // PA-5: Klärung in einem festgeschriebenen Monat erst nach Reopen lösbar
    // (alter UND neuer Kommen-Monat, falls die Korrektur den Monat wechselt).
    await _assertMonatNichtFestgeschrieben(entry.userId, entry.kommen);
    if (kommen.year != entry.kommen.year ||
        kommen.month != entry.kommen.month) {
      await _assertMonatNichtFestgeschrieben(entry.userId, kommen);
    }
    final pause = ClockService.effectivePauseMinutes(
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pauseMinuten,
    );
    final netto = ClockService.netMinutes(
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pause,
    );
    final corrected = entry.copyWith(
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pause,
      nettoMinutes: netto,
      status: ClockStatus.completed,
      klaerung: false,
      manuellErfasst: true,
      korrigiertVonUid: user.uid,
      korrekturGrund: grund,
    );
    await _persist(corrected, ongoing: false);
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Stempelzeit',
      entityId: corrected.id,
      summary:
          'Klärung gelöst (${(netto / 60).toStringAsFixed(1)} h) · $grund',
    );
    await _postWorkEntryFor(corrected, user: user, note: grund);
    await _loadMonthEntries();
    _safeNotify();
  }

  /// Verwirft einen Klärungsfall (ZV-3.1) — z. B. Doppel-Buchung: Status
  /// `deaktiviert`, kein `WorkEntry`. Nur Manager/Admin. [grund] Pflicht.
  Future<void> dismissKlaerung(
    ClockEntry entry, {
    required String grund,
  }) async {
    final user = _currentUser;
    if (user == null || !user.canManageShifts) return;
    // PA-5: auch das Verwerfen ändert einen festgeschriebenen Monat.
    await _assertMonatNichtFestgeschrieben(entry.userId, entry.kommen);
    final dismissed = entry.copyWith(
      status: ClockStatus.deaktiviert,
      klaerung: false,
      manuellErfasst: true,
      korrigiertVonUid: user.uid,
      korrekturGrund: grund,
    );
    await _persist(dismissed, ongoing: false);
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Stempelzeit',
      entityId: dismissed.id,
      summary: 'Klärung verworfen · $grund',
    );
    _safeNotify();
  }

  /// Trägt eine Buchung manuell nach (ZV-3.3) — „Handy vergessen"-Fälle. Erzeugt
  /// direkt eine abgeschlossene Buchung + `WorkEntry(submitted)`. Nur Manager/Admin.
  Future<void> addManualClockEntry({
    required String userId,
    String? userName,
    required DateTime kommen,
    required DateTime gehen,
    int? pauseMinuten,
    String? siteId,
    String? siteName,
    String? shiftId,
    required String grund,
  }) async {
    final user = _currentUser;
    if (user == null || !user.canManageShifts) return;
    // PA-5: Nachtragen in einen festgeschriebenen Monat erst nach Reopen.
    await _assertMonatNichtFestgeschrieben(userId, kommen);
    final pause = ClockService.effectivePauseMinutes(
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pauseMinuten,
    );
    final netto = ClockService.netMinutes(
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pause,
    );
    final entry = ClockEntry(
      id: 'clock-manual-${DateTime.now().microsecondsSinceEpoch}',
      orgId: user.orgId,
      userId: userId,
      userName: userName,
      siteId: siteId,
      siteName: siteName,
      shiftId: shiftId,
      source: 'app',
      kommen: kommen,
      gehen: gehen,
      pauseMinuten: pause,
      nettoMinutes: netto,
      status: ClockStatus.completed,
      manuellErfasst: true,
      korrigiertVonUid: user.uid,
      korrekturGrund: grund,
      createdByUid: user.uid,
    );
    await _persist(entry, ongoing: false);
    _audit?.call(
      action: AuditAction.created,
      entityType: 'Stempelzeit',
      entityId: entry.id,
      summary:
          'Buchung nachgetragen (${(netto / 60).toStringAsFixed(1)} h) · $grund',
    );
    await _postWorkEntryFor(entry, user: user, note: grund);
    await _loadMonthEntries();
    _safeNotify();
  }

  /// Erzeugt für [entry] einen `WorkEntry(submitted)` über den [_workEntryPoster]
  /// und schreibt die `workEntryId` zurück (Duplikat-Schutz). Best-effort — ein
  /// Fehler (z. B. Compliance) bricht die bereits gespeicherte Korrektur NICHT ab.
  Future<void> _postWorkEntryFor(
    ClockEntry entry, {
    required AppUserProfile user,
    String? note,
  }) async {
    final poster = _workEntryPoster;
    final gehen = entry.gehen;
    if (poster == null || gehen == null || entry.workEntryId != null) return;
    final workEntry = WorkEntry(
      orgId: entry.orgId,
      userId: entry.userId,
      date: entry.kommen,
      startTime: entry.kommen,
      endTime: gehen,
      breakMinutes: entry.pauseMinuten.toDouble(),
      siteId: entry.siteId,
      siteName: entry.siteName,
      sourceShiftId: entry.shiftId,
      note: note,
      category: 'stempel',
      status: WorkEntryStatus.submitted,
      sourceClockEntryId: entry.id,
    );
    try {
      await poster(workEntry);
    } catch (error) {
      AppLogger.warning(
          'Zeitwirtschaft: WorkEntry aus Korrektur fehlgeschlagen',
          error: error);
      sessionError =
          'Die korrigierte Zeit konnte nicht als Zeiteintrag übernommen werden. '
          'Bitte in der Zeiterfassung prüfen.';
    }
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
    // Eigene Klärungsfälle aus dem lokalen Cache (Manager sehen im Local-Modus
    // ohnehin nur den eigenen Bestand).
    _klaerungEntries = _localEntries
        .where((e) => e.status == ClockStatus.klaerung)
        .toList()
      ..sort((a, b) => b.kommen.compareTo(a.kommen));
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
