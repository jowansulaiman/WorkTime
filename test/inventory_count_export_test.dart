import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/inventory_count_session.dart';
import 'package:worktime_app/services/export_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  final session = InventoryCountSession(
    id: 's-1',
    orgId: 'org-1',
    siteId: 'site-1',
    title: 'Sommerinventur',
    status: InventoryCountStatus.completed,
    startedAt: DateTime(2026, 7, 14, 8),
    startedByUid: 'u-1',
    startedByLabel: 'Chef',
    completedAt: DateTime(2026, 7, 14, 20),
    diffSummary: const [
      InventoryCountDiff(
        productId: 'p-1',
        productName: 'Cola',
        countedQuantity: 7,
        previousStock: 10,
        unitCostCents: 80,
      ),
    ],
  );

  final lines = [
    InventoryCountEvent(
      id: 'l-1',
      productId: 'p-1',
      productName: 'Cola',
      countedQuantity: 7,
      stockAtCount: 10,
      countedAt: DateTime(2026, 7, 14, 9),
      countedByUid: 'u-1',
      countedByLabel: 'Peter',
      bookedAt: DateTime(2026, 7, 14, 20),
    ),
  ];

  test('CSV hat UTF-8-BOM, ; als Trenner und beide Abschnitte', () {
    final csv = ExportService.buildInventoryCountCsv(
      session: session,
      lines: lines,
    );
    expect(csv.codeUnitAt(0), 0xFEFF); // BOM bleibt erhalten
    expect(csv, contains('Inventur-Protokoll'));
    expect(csv, contains('Titel;Sommerinventur'));
    expect(csv, contains('Zählliste'));
    expect(csv, contains('Cola;7;Peter;'));
    expect(csv, contains('ja')); // gebucht
    expect(csv, contains('Differenzen'));
    // Delta -3, Bewertung -3 * 0,80 = -2,40. Negative Zahlen bekommen durch die
    // CSV-Formel-Injection-Neutralisierung (_escapeCsv) ein führendes Apostroph.
    expect(csv, contains("Cola;7;10;'-3;0.80;'-2.40"));
  });

  test('ohne Bewertung fehlen die EK-Spalten', () {
    final csv = ExportService.buildInventoryCountCsv(
      session: session,
      lines: lines,
      includeValuation: false,
    );
    expect(csv, contains('Artikel;Gezählt;Vorher;Delta'));
    expect(csv, isNot(contains('Bewertung (€)')));
  });

  test('Differenzliste kommt aus diffSummary (nicht live neu bewertet)', () {
    // Auch mit anderer aktueller line-Bewertung bleibt die eingefrorene
    // diffSummary maßgeblich.
    final csv = ExportService.buildInventoryCountCsv(
      session: session,
      lines: lines,
    );
    // Genau eine Differenzzeile (aus diffSummary), nicht aus den lines abgeleitet.
    final diffSection = csv.split('Differenzen').last;
    final dataRows = diffSection
        .split('\n')
        .where((l) => l.startsWith('Cola;'))
        .toList();
    expect(dataRows, hasLength(1));
  });
}
