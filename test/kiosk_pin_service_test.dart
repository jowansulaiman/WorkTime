import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/screens/kiosk/kiosk_controller.dart';
import 'package:worktime_app/screens/kiosk/kiosk_pin_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _peter = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('KioskPinStore (Dev-PIN)', () {
    test('akzeptiert Demo-PIN, wenn keine gesetzt ist', () async {
      expect(await KioskPinStore.verify('emp-1', KioskPinStore.demoPin), isTrue);
      expect(await KioskPinStore.verify('emp-1', '9999'), isFalse);
    });

    test('gesetzte PIN gilt, Demo-PIN dann nicht mehr', () async {
      await KioskPinStore.setPin('emp-1', '2468');
      expect(await KioskPinStore.verify('emp-1', '2468'), isTrue);
      expect(await KioskPinStore.verify('emp-1', KioskPinStore.demoPin), isFalse);
    });
  });

  group('KioskDeviceStore (geräte-lokaler Laden)', () {
    test('ohne Wahl null, nach setSiteId gemerkt', () async {
      expect(await KioskDeviceStore.getSiteId(), isNull);
      await KioskDeviceStore.setSiteId('site-1');
      expect(await KioskDeviceStore.getSiteId(), 'site-1');
      await KioskDeviceStore.setSiteId('site-2');
      expect(await KioskDeviceStore.getSiteId(), 'site-2');
    });
  });

  group('DevKioskPinService', () {
    test('beginSession: richtige PIN → Erfolg mit sid', () async {
      final svc = DevKioskPinService();
      await svc.setPin('emp-1', '1357');
      final ok = await svc.beginSession(employee: _peter, pin: '1357');
      expect(ok.ok, isTrue);
      expect(ok.sid, isNotNull);

      final bad = await svc.beginSession(employee: _peter, pin: '0000');
      expect(bad.ok, isFalse);
      expect(bad.error, isNotNull);
    });
  });

  group('ServerKioskPinService (über cloudFunctionInvoker-Seam)', () {
    test('setPin ruft Callable setKioskPin mit PIN auf', () async {
      String? calledName;
      Map<String, dynamic>? calledPayload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, payload) async {
          calledName = name;
          calledPayload = payload;
          return <String, dynamic>{'ok': true};
        },
      );
      await ServerKioskPinService(service).setPin('emp-1', '4444');
      expect(calledName, 'setKioskPin');
      expect(calledPayload?['pin'], '4444');
    });

    test('beginSession: Callable liefert sid → Erfolg', () async {
      final service = FirestoreService(
        cloudFunctionInvoker: (name, payload) async =>
            <String, dynamic>{'sid': 'srv-123'},
      );
      final result =
          await ServerKioskPinService(service).beginSession(employee: _peter, pin: '1234');
      expect(result.ok, isTrue);
      expect(result.sid, 'srv-123');
    });

    test('beginSession: permission-denied → deutsche Falsch-PIN-Meldung', () async {
      final service = FirestoreService(
        cloudFunctionInvoker: (name, payload) async {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'nope',
          );
        },
      );
      final result =
          await ServerKioskPinService(service).beginSession(employee: _peter, pin: '0000');
      expect(result.ok, isFalse);
      expect(result.error, 'Falsche PIN.');
    });

    test('beginSession: resource-exhausted → Sperr-Meldung', () async {
      final service = FirestoreService(
        cloudFunctionInvoker: (name, payload) async {
          throw FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'locked',
          );
        },
      );
      final result =
          await ServerKioskPinService(service).beginSession(employee: _peter, pin: '0000');
      expect(result.ok, isFalse);
      expect(result.error, contains('Fehlversuche'));
    });
  });
}
