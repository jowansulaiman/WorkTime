import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/fridge_refill_shortfall.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/site_schedule.dart';

Product fridgeProduct({
  required String id,
  String siteId = 'site-1',
  bool inFridge = true,
  bool isActive = true,
  int currentStock = 30,
  int fridgeTargetStock = 24,
  int fridgeStock = 8,
}) =>
    Product(
      id: id,
      orgId: 'org-1',
      siteId: siteId,
      name: id,
      isActive: isActive,
      currentStock: currentStock,
      inFridge: inFridge,
      fridgeTargetStock: fridgeTargetStock,
      fridgeStock: fridgeStock,
    );

void main() {
  group('computeFridgeShortfalls', () {
    test('meldet nur inFridge-Artikel mit Defizit UND Lager-Bestand', () {
      final products = [
        fridgeProduct(id: 'cola'), // Defizit 16, Lager 22 -> Lücke
        fridgeProduct(id: 'wasser', fridgeStock: 24), // Soll erreicht -> nein
        fridgeProduct(id: 'fanta', inFridge: false), // nicht im Kühlschrank -> nein
        fridgeProduct(id: 'sprite', currentStock: 8, fridgeStock: 8), // Lager 0 -> nein
        fridgeProduct(id: 'alt', isActive: false), // inaktiv -> nein
      ];

      final shortfalls = computeFridgeShortfalls(products);

      expect(shortfalls.map((s) => s.product.id), ['cola']);
      expect(shortfalls.single.deficit, 16);
      expect(shortfalls.single.warehouseAvailable, 22);
    });

    test('sortiert absteigend nach Defizit und filtert je Standort', () {
      final products = [
        fridgeProduct(id: 'klein', fridgeTargetStock: 10, fridgeStock: 8), // Defizit 2
        fridgeProduct(id: 'gross', fridgeTargetStock: 30, fridgeStock: 2), // Defizit 28
        fridgeProduct(id: 'fremd', siteId: 'site-2'),
      ];

      final s1 = computeFridgeShortfalls(products, siteId: 'site-1');
      expect(s1.map((s) => s.product.id), ['gross', 'klein']);

      final s2 = computeFridgeShortfalls(products, siteId: 'site-2');
      expect(s2.map((s) => s.product.id), ['fremd']);
    });

    test('Severity: leer vs. nachfüllen vs. Lager knapp', () {
      // Ist 0 -> empty
      final empty = fridgeProduct(id: 'a', currentStock: 30, fridgeStock: 0);
      // Ist 8, Lager 22 deckt Defizit 16 -> refill
      final refill = fridgeProduct(id: 'b');
      // Ist 8, Defizit 16, aber Lager nur 3 -> warehouseLow
      final low = fridgeProduct(id: 'c', currentStock: 11, fridgeStock: 8);

      expect(
        computeFridgeShortfalls([empty]).single.severity,
        FridgeShortfallSeverity.empty,
      );
      expect(
        computeFridgeShortfalls([refill]).single.severity,
        FridgeShortfallSeverity.refill,
      );
      final lowShort = computeFridgeShortfalls([low]).single;
      expect(lowShort.severity, FridgeShortfallSeverity.warehouseLow);
      expect(lowShort.coveredByWarehouse, isFalse);
    });

    test('roh-negativer fridgeStock wird als 0 (leer) behandelt', () {
      final drift = fridgeProduct(id: 'd', currentStock: 5, fridgeStock: -3);
      final s = computeFridgeShortfalls([drift]).single;
      expect(s.deficit, 24); // 24 - max(0,-3)
      expect(s.warehouseAvailable, 5); // 5 - 0
      // Ist geklemmt auf 0 -> "leer" hat Vorrang vor "Lager knapp".
      expect(s.severity, FridgeShortfallSeverity.empty);
    });
  });

  group('suggestFridgeTarget', () {
    test('Tagesabsatz × Eindeckung, aufgerundet, min 1 bei Absatz', () {
      expect(suggestFridgeTarget(0), 0); // Ladenhüter
      expect(suggestFridgeTarget(5), 10); // 5 * 2
      expect(suggestFridgeTarget(0.2), 1); // 0.4 -> ceil 1
      expect(suggestFridgeTarget(3, coverageDays: 1), 3);
      expect(suggestFridgeTarget(2.5, coverageDays: 3), 8); // 7.5 -> 8
    });
  });

  group('isNearClosing', () {
    // Laden Mo-So 08:00-20:00 (endMinute 1200).
    final site = SiteDefinition(
      orgId: 'org-1',
      name: 'Laden',
      weekdayHours: [
        for (var d = 1; d <= 7; d++)
          WeekdayHours(
            weekday: d,
            windows: const [TimeWindow(startMinute: 480, endMinute: 1200)],
          ),
      ],
    );

    test('feuert nur im 90-Min-Vorlauf vor Ladenschluss', () {
      // 2024-01-03 ist Mittwoch.
      expect(isNearClosing(site, DateTime(2024, 1, 3, 18, 35)), isTrue);
      expect(isNearClosing(site, DateTime(2024, 1, 3, 18)), isFalse); // zu früh
      expect(isNearClosing(site, DateTime(2024, 1, 3, 20, 5)), isFalse); // zu
    });

    test('ohne Öffnungszeiten für heute kein Trigger', () {
      const emptySite = SiteDefinition(orgId: 'o', name: 'X');
      expect(isNearClosing(emptySite, DateTime(2024, 1, 3, 19)), isFalse);
    });
  });
}
