import '../../core/app_config.dart';
import '../../models/app_user.dart';
import '../../models/shift_swap_request.dart';
import '../../services/database_service.dart';
import '../../services/firestore_service.dart';

/// Schichttausch am Kiosk **für den angemeldeten Session-Mitarbeiter** (nicht das
/// Geräte-Konto). Zeigt die an ihn gerichteten, noch offenen Tauschanfragen und
/// lässt ihn sie annehmen/ablehnen — der Kollegen-Schritt des Tausch-Workflows
/// ([SwapStatus.pending] → `acceptedByColleague`/`declinedByColleague`).
///
/// Seam wie [KioskClockService]/[KioskPinService]:
/// - Offline/Demo ([DevKioskSwapService]): liest/schreibt die lokal gespiegelten
///   Tauschanfragen (`shiftSwapRequests` ist org-skopiert) direkt — dieselben
///   Daten, die die App im Local-/Hybrid-Modus nutzt.
/// - Echt ([ServerKioskSwapService]): `getKioskIncomingSwaps`/`kioskRespondSwap`-
///   Callables lesen/schreiben via Admin-SDK ALS der Mitarbeiter (autorisiert
///   über die Session-`sid`). Das niedrig-privilegierte Geräte-Konto darf die
///   Tauschanfragen fremder Mitarbeiter selbst NICHT lesen/ändern — die Rules
///   binden Lesen/Schreiben an `requesterUid`/`targetUid == auth.uid`.
abstract class KioskSwapService {
  /// An [employee] gerichtete, noch offene ([SwapStatus.pending]) Tauschanfragen
  /// — die, die er annehmen/ablehnen kann. Neueste zuerst.
  Future<List<ShiftSwapRequest>> incomingPending(
    AppUserProfile employee, {
    String? sid,
  });

  /// [employee] nimmt die Anfrage [requestId] an ([accept] == true) oder lehnt
  /// sie ab. Es wird KEINE Schicht umgebucht — das macht erst der Chef beim
  /// Bestätigen in der App.
  Future<void> respond(
    AppUserProfile employee, {
    required String requestId,
    required bool accept,
    String? sid,
  });

  factory KioskSwapService.resolve({FirestoreService? firestore}) {
    if (AppConfig.disableAuthentication) {
      return DevKioskSwapService();
    }
    return ServerKioskSwapService(firestore ?? FirestoreService());
  }
}

/// Offline-/Demo-Pfad: lokale Persistenz (org-skopiert, siehe
/// [DatabaseService.loadLocalSwapRequests]).
class DevKioskSwapService implements KioskSwapService {
  LocalStorageScope _scope(AppUserProfile e) => LocalStorageScope.fromUser(e);

  @override
  Future<List<ShiftSwapRequest>> incomingPending(
    AppUserProfile employee, {
    String? sid,
  }) async {
    final all = await DatabaseService.loadLocalSwapRequests(
      scope: _scope(employee),
    );
    final incoming = all
        .where((r) =>
            r.orgId == employee.orgId &&
            r.targetUid == employee.uid &&
            r.status == SwapStatus.pending)
        .toList()
      ..sort((a, b) {
        final aw = a.createdAt ?? a.requesterShiftStart;
        final bw = b.createdAt ?? b.requesterShiftStart;
        return bw.compareTo(aw);
      });
    return incoming;
  }

  @override
  Future<void> respond(
    AppUserProfile employee, {
    required String requestId,
    required bool accept,
    String? sid,
  }) async {
    final scope = _scope(employee);
    final all = await DatabaseService.loadLocalSwapRequests(scope: scope);
    final index = all.indexWhere((r) => r.id == requestId);
    if (index < 0) {
      throw StateError('Die Tauschanfrage wurde nicht gefunden.');
    }
    final request = all[index];
    if (request.targetUid != employee.uid) {
      throw StateError(
        'Nur der angefragte Kollege kann annehmen oder ablehnen.',
      );
    }
    if (request.status != SwapStatus.pending) {
      throw StateError('Diese Anfrage ist nicht mehr offen.');
    }
    final updated = request.copyWith(
      status: accept
          ? SwapStatus.acceptedByColleague
          : SwapStatus.declinedByColleague,
      updatedAt: DateTime.now(),
    );
    final next = [...all]..[index] = updated;
    await DatabaseService.saveLocalSwapRequests(next, scope: scope);
  }
}

/// Echter Betrieb: server-validierte Session über Cloud Functions.
class ServerKioskSwapService implements KioskSwapService {
  ServerKioskSwapService(this._firestore);

  final FirestoreService _firestore;

  @override
  Future<List<ShiftSwapRequest>> incomingPending(
    AppUserProfile employee, {
    String? sid,
  }) async {
    if (sid == null) return const [];
    return _firestore.getKioskIncomingSwaps(sid);
  }

  @override
  Future<void> respond(
    AppUserProfile employee, {
    required String requestId,
    required bool accept,
    String? sid,
  }) async {
    await _firestore.kioskRespondSwap(
      sid: sid!,
      requestId: requestId,
      accept: accept,
    );
  }
}
