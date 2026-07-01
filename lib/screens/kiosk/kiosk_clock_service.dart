import '../../core/app_config.dart';
import '../../core/clock_service.dart';
import '../../models/app_user.dart';
import '../../models/clock_entry.dart';
import '../../models/work_entry.dart';
import '../../services/database_service.dart';
import '../../services/firestore_service.dart';

/// Stempeln am Kiosk **für den angemeldeten Session-Mitarbeiter** (nicht das
/// Geräte-Konto). Seam wie [KioskPinService]:
/// - Offline/Demo ([DevKioskClockService]): schreibt ClockEntry (+ WorkEntry auf
///   sauberem Ausstempeln) lokal, dem Mitarbeiter zugeordnet — dieselben
///   Collections, die die App liest (org-skopiert, gefiltert nach `userId`).
/// - Echt ([ServerKioskClockService]): `kioskClockPunch`-Callable schreibt via
///   Admin-SDK als der Mitarbeiter (autorisiert über die Session-`sid`).
abstract class KioskClockService {
  /// Ist der Mitarbeiter aktuell eingestempelt?
  Future<bool> isClockedIn(AppUserProfile employee, {String? sid});

  /// Kommen. Liefert den neuen Zustand (`true` = eingestempelt).
  Future<bool> clockIn(
    AppUserProfile employee, {
    String? sid,
    String? siteId,
    String? siteName,
  });

  /// Gehen. Liefert den neuen Zustand (`false` = ausgestempelt).
  Future<bool> clockOut(
    AppUserProfile employee, {
    String? sid,
    int? pauseMinuten,
  });

  factory KioskClockService.resolve({FirestoreService? firestore}) {
    if (AppConfig.disableAuthentication) {
      return DevKioskClockService();
    }
    return ServerKioskClockService(firestore ?? FirestoreService());
  }
}

/// Offline-/Demo-Pfad: lokale Persistenz, dem Mitarbeiter zugeordnet.
class DevKioskClockService implements KioskClockService {
  LocalStorageScope _scope(AppUserProfile e) => LocalStorageScope.fromUser(e);

  ClockEntry? _openFor(List<ClockEntry> list, String uid) {
    for (final entry in list) {
      if (entry.userId == uid && entry.status == ClockStatus.ongoing) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<bool> isClockedIn(AppUserProfile employee, {String? sid}) async {
    final list =
        await DatabaseService.loadLocalClockEntries(scope: _scope(employee));
    return _openFor(list, employee.uid) != null;
  }

  @override
  Future<bool> clockIn(
    AppUserProfile employee, {
    String? sid,
    String? siteId,
    String? siteName,
  }) async {
    final scope = _scope(employee);
    final list = await DatabaseService.loadLocalClockEntries(scope: scope);
    if (_openFor(list, employee.uid) != null) return true;
    final entry = ClockEntry(
      id: 'clock-kiosk-${DateTime.now().microsecondsSinceEpoch}',
      orgId: employee.orgId,
      userId: employee.uid,
      userName: employee.settings.name,
      siteId: siteId,
      siteName: siteName,
      kommen: DateTime.now(),
      status: ClockStatus.ongoing,
      createdByUid: employee.uid,
    );
    await DatabaseService.saveLocalClockEntries([...list, entry], scope: scope);
    return true;
  }

  @override
  Future<bool> clockOut(
    AppUserProfile employee, {
    String? sid,
    int? pauseMinuten,
  }) async {
    final scope = _scope(employee);
    final list = await DatabaseService.loadLocalClockEntries(scope: scope);
    final open = _openFor(list, employee.uid);
    if (open == null) return false;
    final now = DateTime.now();
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
    final needsKlaerung =
        ClockService.needsClarification(kommen: open.kommen, now: now);
    final closed = open.copyWith(
      gehen: now,
      pauseMinuten: pause,
      nettoMinutes: netto,
      status: needsKlaerung ? ClockStatus.klaerung : ClockStatus.completed,
      klaerung: needsKlaerung,
    );
    final updated =
        list.map((e) => e.id == closed.id ? closed : e).toList(growable: false);
    await DatabaseService.saveLocalClockEntries(updated, scope: scope);

    // Sauber abgeschlossen → WorkEntry(submitted) erzeugen (wie der App-Stempel),
    // dem Mitarbeiter zugeordnet. Klärungsfälle erst nach Klärung.
    if (!needsKlaerung) {
      final entries = await DatabaseService.loadLocalEntries(scope: scope);
      final workEntry = WorkEntry(
        id: 'we-kiosk-${DateTime.now().microsecondsSinceEpoch}',
        orgId: employee.orgId,
        userId: employee.uid,
        date: open.kommen,
        startTime: open.kommen,
        endTime: now,
        breakMinutes: pause.toDouble(),
        siteId: closed.siteId,
        siteName: closed.siteName,
        category: 'stempel',
        status: WorkEntryStatus.submitted,
        sourceClockEntryId: closed.id,
      );
      await DatabaseService.saveLocalEntries([...entries, workEntry],
          scope: scope);
    }
    return false;
  }
}

/// Echter Betrieb: `kioskClockPunch`-Callable (server-validierte Session).
class ServerKioskClockService implements KioskClockService {
  ServerKioskClockService(this._firestore);

  final FirestoreService _firestore;

  @override
  Future<bool> isClockedIn(AppUserProfile employee, {String? sid}) async {
    if (sid == null) return false;
    return _firestore.kioskClockPunch(sid: sid, direction: 'status');
  }

  @override
  Future<bool> clockIn(
    AppUserProfile employee, {
    String? sid,
    String? siteId,
    String? siteName,
  }) {
    return _firestore.kioskClockPunch(
      sid: sid!,
      direction: 'in',
      siteId: siteId,
      siteName: siteName,
    );
  }

  @override
  Future<bool> clockOut(
    AppUserProfile employee, {
    String? sid,
    int? pauseMinuten,
  }) {
    return _firestore.kioskClockPunch(
      sid: sid!,
      direction: 'out',
      pauseMinuten: pauseMinuten,
    );
  }
}
