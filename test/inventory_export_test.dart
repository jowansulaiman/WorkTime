import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/product.dart';
import 'package:worktime_app/services/export_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  const stock = Product(
    orgId: 'o',
    siteId: 's1',
    siteName: 'Strichmännchen',
    name: 'Feuerzeug',
    category: 'Raucherbedarf',
    unit: 'Stück',
    currentStock: 10,
    minStock: 5,
    targetStock: 20,
    purchasePriceCents: 45,
    sellingPriceCents: 99,
  );

  group('Bestands-CSV', () {
    test('hat BOM, Kopfzeile und Warenwert', () {
      final csv = ExportService.buildStockListCsv(
        products: const [stock],
        siteLabel: 'Strichmännchen',
      );
      expect(csv.codeUnitAt(0), 0xFEFF); // UTF-8-BOM
      expect(csv, contains('Artikel;Warengruppe;Standort;Bestand;'));
      expect(csv, contains('Feuerzeug;Raucherbedarf;Strichmännchen;10;'));
      // Warenwert = 10 * 0,45 € = 4,50 € (Leerzeichen vor € ist geschütztes
      // Leerzeichen -> nur auf den Zahlteil pruefen).
      expect(csv, contains('4,50'));
    });
  });

  group('Nachbestell-CSV', () {
    test('enthält Vorschlagsmenge (Ziel − Bestand)', () {
      final csv = ExportService.buildReorderListCsv(products: const [stock]);
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Artikel;Lieferant;Standort;Bestand;'));
      // Zielbestand 20 - Bestand 10 = 10 Vorschlag, letzte Spalte.
      expect(csv.trimRight().endsWith(';10'), isTrue);
    });

    test('übernimmt einen bereits um unterwegs-Ware reduzierten Vorschlag', () {
      final csv = ExportService.buildReorderListCsv(
        products: [stock.copyWith(reorderQuantity: 4)],
      );

      expect(csv.trimRight().endsWith(';4'), isTrue);
    });
  });
}
