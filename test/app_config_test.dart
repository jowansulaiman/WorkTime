import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/app_config.dart';

void main() {
  group('AppConfig.parseStoreNames (#51/#73)', () {
    test('trimmt Namen und verwirft leere Eintraege', () {
      expect(
        AppConfig.parseStoreNames('A, B ,,C'),
        ['A', 'B', 'C'],
      );
    });

    test('leerer String ergibt leere Liste', () {
      expect(AppConfig.parseStoreNames(''), isEmpty);
      expect(AppConfig.parseStoreNames(','), isEmpty);
      expect(AppConfig.parseStoreNames(' , '), isEmpty);
    });

    test('kappt Namen auf die Rules-Grenze von 120 Zeichen', () {
      final long = 'L' * 200;
      final parsed = AppConfig.parseStoreNames(long);
      expect(parsed.single.length, 120,
          reason: 'firestore.rules erlauben storeName.size() <= 120 — ein '
              'laengerer Name wuerde jede oeffentliche Abgabe blockieren');
    });

    test('Default liefert die zwei konfigurierten Laeden', () {
      // Tripwire: der Default-Build muss beide Kieler Laeden anbieten.
      expect(AppConfig.publicStoreNameList, hasLength(2));
      expect(
        AppConfig.publicStoreNameList.every(
          (name) => name.isNotEmpty && name.length <= 120,
        ),
        isTrue,
      );
    });
  });
}
