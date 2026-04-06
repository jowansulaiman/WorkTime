import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseService local storage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('defaults to hybrid data storage location', () async {
      expect(await DatabaseService.loadDataStorageLocation(), 'hybrid');
    });

    test('shares org data but keeps user settings separate', () async {
      const firstScope = LocalStorageScope(orgId: 'org-1', userId: 'user-1');
      const secondScope = LocalStorageScope(orgId: 'org-1', userId: 'user-2');

      await DatabaseService.saveLocalEntries(
        [
          WorkEntry(
            id: 'entry-1',
            orgId: 'org-1',
            userId: 'user-1',
            date: DateTime(2026, 4, 1),
            startTime: DateTime(2026, 4, 1, 8),
            endTime: DateTime(2026, 4, 1, 16),
            breakMinutes: 30,
            siteId: 'site-1',
            siteName: 'Berlin',
          ),
          WorkEntry(
            id: 'entry-2',
            orgId: 'org-1',
            userId: 'user-2',
            date: DateTime(2026, 4, 2),
            startTime: DateTime(2026, 4, 2, 9),
            endTime: DateTime(2026, 4, 2, 17),
            breakMinutes: 45,
            siteId: 'site-2',
            siteName: 'Hamburg',
          ),
        ],
        scope: firstScope,
      );
      await DatabaseService.saveLocalUserSettings(
        const UserSettings(name: 'Anna', hourlyRate: 15),
        scope: firstScope,
      );
      await DatabaseService.saveLocalUserSettings(
        const UserSettings(name: 'Ben', hourlyRate: 21),
        scope: secondScope,
      );

      final firstEntries =
          await DatabaseService.loadLocalEntries(scope: firstScope);
      final secondEntries =
          await DatabaseService.loadLocalEntries(scope: secondScope);
      final firstSettings =
          await DatabaseService.loadLocalUserSettings(scope: firstScope);
      final secondSettings =
          await DatabaseService.loadLocalUserSettings(scope: secondScope);

      expect(
        firstEntries.map((entry) => entry.id),
        containsAll(<String?>['entry-1', 'entry-2']),
      );
      expect(
        secondEntries.map((entry) => entry.id),
        containsAll(<String?>['entry-1', 'entry-2']),
      );
      expect(firstSettings.name, 'Anna');
      expect(secondSettings.name, 'Ben');
      expect(secondSettings.hourlyRate, 21);
    });

    test('migrates legacy local data into matching scopes', () async {
      const firstScope = LocalStorageScope(orgId: 'org-1', userId: 'user-1');
      const secondScope = LocalStorageScope(orgId: 'org-2', userId: 'user-2');

      await DatabaseService.saveLocalEntries([
        WorkEntry(
          id: 'legacy-entry-1',
          orgId: 'org-1',
          userId: 'user-1',
          date: DateTime(2026, 4, 3),
          startTime: DateTime(2026, 4, 3, 8),
          endTime: DateTime(2026, 4, 3, 16),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
        ),
        WorkEntry(
          id: 'legacy-entry-2',
          orgId: 'org-2',
          userId: 'user-2',
          date: DateTime(2026, 4, 4),
          startTime: DateTime(2026, 4, 4, 9),
          endTime: DateTime(2026, 4, 4, 17),
          breakMinutes: 45,
          siteId: 'site-2',
          siteName: 'Hamburg',
        ),
      ]);
      await DatabaseService.saveLocalShifts([
        Shift(
          id: 'legacy-shift-1',
          orgId: 'org-1',
          userId: 'user-1',
          employeeName: 'Anna',
          title: 'Frueh',
          startTime: DateTime(2026, 4, 3, 8),
          endTime: DateTime(2026, 4, 3, 16),
          breakMinutes: 30,
          siteId: 'site-1',
          siteName: 'Berlin',
          location: 'Berlin',
          status: ShiftStatus.confirmed,
        ),
        Shift(
          id: 'legacy-shift-2',
          orgId: 'org-2',
          userId: 'user-2',
          employeeName: 'Ben',
          title: 'Spaet',
          startTime: DateTime(2026, 4, 4, 10),
          endTime: DateTime(2026, 4, 4, 18),
          breakMinutes: 30,
          siteId: 'site-2',
          siteName: 'Hamburg',
          location: 'Hamburg',
          status: ShiftStatus.confirmed,
        ),
      ]);

      final firstEntries =
          await DatabaseService.loadLocalEntries(scope: firstScope);
      final firstShifts =
          await DatabaseService.loadLocalShifts(scope: firstScope);
      final secondEntries =
          await DatabaseService.loadLocalEntries(scope: secondScope);
      final secondShifts =
          await DatabaseService.loadLocalShifts(scope: secondScope);

      expect(firstEntries.single.id, 'legacy-entry-1');
      expect(firstShifts.single.id, 'legacy-shift-1');
      expect(secondEntries.single.id, 'legacy-entry-2');
      expect(secondShifts.single.id, 'legacy-shift-2');
    });

    test('clears only legacy work settings and keeps app settings', () async {
      await DatabaseService.saveDataStorageLocation('local');
      await DatabaseService.saveLocalSetting('theme_mode', 'dark');
      await DatabaseService.saveLocalSetting('name', 'Anna');
      await DatabaseService.saveLocalSetting(
        'clock_in_time',
        DateTime(2026, 4, 5, 8).toIso8601String(),
      );

      await DatabaseService.clearLegacyWorkData();

      expect(await DatabaseService.loadDataStorageLocation(), 'local');
      expect(await DatabaseService.getLocalSetting('theme_mode'), 'dark');
      expect(await DatabaseService.getLocalSetting('name'), isNull);
      expect(await DatabaseService.getLocalSetting('clock_in_time'), isNull);
    });
  });
}
