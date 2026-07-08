import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/third_party_cash.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/screens/kiosk/kiosk_clock_service.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _peter = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

const _maria = AppUserProfile(
  uid: 'emp-2',
  orgId: 'org-1',
  email: 'maria@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Maria'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  test('Dev-Stempel: Kommen/Gehen wird dem MITARBEITER zugeordnet', () async {
    final svc = DevKioskClockService();
    expect(await svc.isClockedIn(_peter), isFalse);

    final inState = await svc.clockIn(_peter, siteId: 'site-1', siteName: 'Laden 1');
    expect(inState, isTrue);
    expect(await svc.isClockedIn(_peter), isTrue);

    // ClockEntry trägt Peters userId (nicht das Geräte-Konto).
    final entries = await DatabaseService.loadLocalClockEntries(
        scope: LocalStorageScope.fromUser(_peter));
    final open = entries.where(
        (e) => e.userId == 'emp-1' && e.status == ClockStatus.ongoing);
    expect(open, hasLength(1));
    expect(open.first.siteName, 'Laden 1');

    final outState = await svc.clockOut(_peter);
    expect(outState, isFalse);
    expect(await svc.isClockedIn(_peter), isFalse);

    // WorkEntry(submitted, „stempel") für Peter erzeugt → landet in der App.
    final work = await DatabaseService.loadLocalEntries(
        scope: LocalStorageScope.fromUser(_peter));
    final we = work.where((w) => w.userId == 'emp-1' && w.category == 'stempel');
    expect(we, hasLength(1));
    expect(we.first.status, WorkEntryStatus.submitted);
  });

  test('Dev-Stempel: Mitarbeiter sind unabhängig', () async {
    final svc = DevKioskClockService();
    await svc.clockIn(_peter);
    expect(await svc.isClockedIn(_peter), isTrue);
    expect(await svc.isClockedIn(_maria), isFalse);
  });

  test('Dev-Stempel: doppeltes Kommen legt keine zweite offene Buchung an',
      () async {
    final svc = DevKioskClockService();
    await svc.clockIn(_peter);
    await svc.clockIn(_peter);
    final entries = await DatabaseService.loadLocalClockEntries(
        scope: LocalStorageScope.fromUser(_peter));
    expect(
      entries.where((e) => e.status == ClockStatus.ongoing),
      hasLength(1),
    );
  });

  group('ServerKioskClockService (cloudFunctionInvoker-Seam)', () {
    test('clockIn übergibt direction=in, Standort und expliziten shiftId',
        () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = {'name': name, ...p};
          return <String, dynamic>{'clockedIn': true};
        },
      );
      final ok = await ServerKioskClockService(service).clockIn(
        _peter,
        sid: 'srv-1',
        siteId: 'site-1',
        siteName: 'Laden 1',
        shiftId: 'shift-9',
      );
      expect(ok, isTrue);
      expect(payload?['name'], 'kioskClockPunch');
      expect(payload?['direction'], 'in');
      expect(payload?['sid'], 'srv-1');
      expect(payload?['siteId'], 'site-1');
      // Expliziter shiftId behält Vorrang und wird durchgereicht.
      expect(payload?['shiftId'], 'shift-9');
    });

    test('clockIn ohne shiftId sendet keinen — der Server löst die Schicht auf',
        () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = p;
          return <String, dynamic>{'clockedIn': true};
        },
      );
      // Kein Client-seitiger shifts-Read mehr (Gerätekonto darf das nicht) —
      // der Client sendet keinen shiftId, kioskClockPunch resolved server-seitig.
      await ServerKioskClockService(service).clockIn(_peter, sid: 'srv-1');
      expect(payload!.containsKey('shiftId'), isFalse);
    });

    test('clockOut sendet direction=out + pauseMinuten', () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = p;
          return <String, dynamic>{'clockedIn': false};
        },
      );
      final state = await ServerKioskClockService(service)
          .clockOut(_peter, sid: 'srv-1', pauseMinuten: 30);
      expect(state, isFalse);
      expect(payload?['direction'], 'out');
      expect(payload?['pauseMinuten'], 30);
    });
  });

  group('kioskSaveCashCount (Dritte-Hand-Payload)', () {
    test('sendet thirdParty als camelCase-Liste + liefert cashCountId',
        () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = {'name': name, ...p};
          return <String, dynamic>{'cashCountId': 'cc-1'};
        },
      );
      final id = await service.kioskSaveCashCount(
        sid: 'srv-1',
        countedCents: 20000,
        businessDay: '2026-07-08',
        siteId: 'site-1',
        thirdParty: const [
          ThirdPartyAmount(
              typeId: 'lotto', typeName: 'Lotto', amountCents: 5000),
        ],
      );
      expect(id, 'cc-1');
      expect(payload?['name'], 'kioskSaveCashCount');
      final tp = payload?['thirdParty'] as List;
      expect(tp, hasLength(1));
      final first = tp.first as Map;
      // camelCase (nicht type_id/amount_cents) — passt zu parseThirdPartyAmounts.
      expect(first['typeId'], 'lotto');
      expect(first['typeName'], 'Lotto');
      expect(first['amountCents'], 5000);
    });

    test('leere thirdParty-Liste wird nicht mitgesendet', () async {
      Map<String, dynamic>? payload;
      final service = FirestoreService(
        cloudFunctionInvoker: (name, p) async {
          payload = p;
          return <String, dynamic>{'cashCountId': 'cc-2'};
        },
      );
      await service.kioskSaveCashCount(
        sid: 'srv-1',
        countedCents: 20000,
        businessDay: '2026-07-08',
      );
      expect(payload!.containsKey('thirdParty'), isFalse);
    });
  });
}
