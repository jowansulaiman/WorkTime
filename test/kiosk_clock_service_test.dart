import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/screens/kiosk/kiosk_clock_service.dart';
import 'package:worktime_app/services/database_service.dart';

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
}
