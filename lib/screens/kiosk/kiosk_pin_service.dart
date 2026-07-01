import 'package:cloud_functions/cloud_functions.dart';

import '../../core/app_config.dart';
import '../../models/app_user.dart';
import '../../services/firestore_service.dart';
import 'kiosk_controller.dart';

/// Ergebnis einer Kiosk-Anmeldung: bei Erfolg die Session-ID (`sid`), sonst eine
/// deutsche Fehlermeldung.
class KioskSessionResult {
  const KioskSessionResult.success(this.sid)
      : ok = true,
        error = null;
  const KioskSessionResult.failure(this.error)
      : ok = false,
        sid = null;

  final bool ok;
  final String? sid;
  final String? error;
}

/// Seam für die PIN-Prüfung/-Verwaltung am Kiosk. Im Offline-/Demo-Modus lokal
/// ([DevKioskPinService], [KioskPinStore]); im echten Betrieb server-geprüft
/// ([ServerKioskPinService] über die `setKioskPin`/`kioskBeginSession`-Callables).
/// Der Aufrufer bleibt identisch — der Wechsel ist ein Impl-Tausch.
abstract class KioskPinService {
  /// Setzt/ändert die PIN des Mitarbeiters (auf dem eigenen Handy).
  Future<bool> setPin(String uid, String pin);

  /// Meldet [employee] per [pin] am Kiosk an.
  Future<KioskSessionResult> beginSession({
    required AppUserProfile employee,
    required String pin,
    String? deviceId,
  });

  factory KioskPinService.resolve({FirestoreService? firestore}) {
    if (AppConfig.disableAuthentication) {
      return DevKioskPinService();
    }
    return ServerKioskPinService(firestore ?? FirestoreService());
  }
}

/// Offline-/Demo-Pfad: lokaler PIN-Speicher ([KioskPinStore]).
class DevKioskPinService implements KioskPinService {
  @override
  Future<bool> setPin(String uid, String pin) async {
    await KioskPinStore.setPin(uid, pin);
    return true;
  }

  @override
  Future<KioskSessionResult> beginSession({
    required AppUserProfile employee,
    required String pin,
    String? deviceId,
  }) async {
    final ok = await KioskPinStore.verify(employee.uid, pin);
    return ok
        ? const KioskSessionResult.success('dev-local')
        : const KioskSessionResult.failure('Falsche PIN.');
  }
}

/// Echter Betrieb: server-geprüfte PIN über Cloud Functions.
class ServerKioskPinService implements KioskPinService {
  ServerKioskPinService(this._firestore);

  final FirestoreService _firestore;

  @override
  Future<bool> setPin(String uid, String pin) async {
    // Der Server nutzt request.auth.uid; [uid] dient nur dem einheitlichen
    // Interface (Dev-Pfad braucht ihn).
    await _firestore.setKioskPin(pin);
    return true;
  }

  @override
  Future<KioskSessionResult> beginSession({
    required AppUserProfile employee,
    required String pin,
    String? deviceId,
  }) async {
    try {
      final sid = await _firestore.kioskBeginSession(
        employeeId: employee.uid,
        pin: pin,
        deviceId: deviceId,
      );
      return KioskSessionResult.success(sid);
    } on FirebaseFunctionsException catch (error) {
      return KioskSessionResult.failure(_message(error));
    } catch (_) {
      return const KioskSessionResult.failure('Anmeldung fehlgeschlagen.');
    }
  }

  String _message(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Falsche PIN.';
      case 'resource-exhausted':
        return 'Zu viele Fehlversuche. Bitte später erneut versuchen.';
      case 'failed-precondition':
        return 'Für dich ist noch keine PIN hinterlegt.';
      default:
        return 'Anmeldung fehlgeschlagen.';
    }
  }
}
