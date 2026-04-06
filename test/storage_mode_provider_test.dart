import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/providers/storage_mode_provider.dart';
import 'package:worktime_app/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageModeProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('defaults to hybrid storage', () async {
      final provider = StorageModeProvider();

      await provider.init();

      expect(provider.location, DataStorageLocation.hybrid);
      expect(provider.isLocalOnly, isFalse);
      expect(provider.isHybrid, isTrue);
    });

    test('persists selected storage location', () async {
      final provider = StorageModeProvider();
      await provider.init();

      await provider.setLocation(DataStorageLocation.local);

      final reloaded = StorageModeProvider();
      await reloaded.init();

      expect(reloaded.location, DataStorageLocation.local);
      expect(reloaded.isLocalOnly, isTrue);
    });

    test('persists cloud storage explicitly', () async {
      final provider = StorageModeProvider();
      await provider.init();

      await provider.setLocation(DataStorageLocation.cloud);

      final reloaded = StorageModeProvider();
      await reloaded.init();

      expect(reloaded.location, DataStorageLocation.cloud);
      expect(reloaded.isHybrid, isFalse);
      expect(reloaded.isLocalOnly, isFalse);
    });
  });
}
