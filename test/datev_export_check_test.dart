import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/datev_export.dart';
import 'package:worktime_app/core/datev_export_check.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/pos_receipt.dart';

void main() {
  const center = CostCenter(id: 'c1', orgId: 'o', number: '1001', name: 'Laden');
  const type = CostType(id: 't1', orgId: 'o', number: '4100', name: 'Miete');

  JournalEntry entry({
    String costCenterId = 'c1',
    String costTypeId = 't1',
    int year = 2026,
  }) =>
      JournalEntry(
        orgId: 'o',
        date: DateTime(year, 3, 15),
        costCenterId: costCenterId,
        costTypeId: costTypeId,
        description: 'Buchung',
        amountCents: 1000,
      );

  const config = DatevExportConfig(
    consultantNumber: '1234567',
    clientNumber: '54321',
    defaultContraAccount: '9000',
    revenueAccountByRate: {19: '8400'},
  );

  List<DatevExportFinding> run({
    List<JournalEntry>? entries,
    Map<String, CostCenter>? centers,
    Map<String, CostType>? types,
    DatevExportConfig cfg = config,
    List<CashClosing>? closings = const [],
  }) =>
      DatevExportCheck.run(
        entries: entries ?? [entry()],
        centersById: centers ?? const {'c1': center},
        typesById: types ?? const {'t1': type},
        config: cfg,
        year: 2026,
        closings: closings,
      );

  Set<String> codes(List<DatevExportFinding> f) =>
      f.map((e) => e.code).toSet();

  group('DatevExportCheck.run', () {
    test('sauberer Fall ohne Abschlüsse → keine Befunde', () {
      expect(run(), isEmpty);
    });

    test('entries_empty (Fehler), wenn keine Buchungen im Jahr', () {
      final f = run(entries: [entry(year: 2025)]);
      expect(codes(f), contains('entries_empty'));
      expect(f.firstWhere((e) => e.code == 'entries_empty').isError, isTrue);
    });

    test('contra_account_missing (Fehler) bei leerem Gegenkonto', () {
      final f = run(
        cfg: const DatevExportConfig(defaultContraAccount: '  '),
      );
      expect(codes(f), contains('contra_account_missing'));
    });

    test('unknown_cost_center + unknown_cost_type bei fehlenden Stammdaten', () {
      final f = run(centers: const {}, types: const {});
      expect(codes(f), containsAll(['unknown_cost_center', 'unknown_cost_type']));
    });

    test('cost_type_missing_number bei Kostenart ohne Kontonummer', () {
      final f = run(types: const {
        't1': CostType(id: 't1', orgId: 'o', number: '  ', name: 'Ohne Nr'),
      });
      expect(codes(f), contains('cost_type_missing_number'));
    });

    test('cost_type_missing_number auch bei nicht-numerischem Platzhalter '
        '(spiegelt _digits)', () {
      final f = run(types: const {
        't1': CostType(id: 't1', orgId: 'o', number: 'TBD', name: 'Platzhalter'),
      });
      // „TBD" ist nicht leer, ergäbe im Export aber eine leere Konto-Spalte.
      expect(codes(f), contains('cost_type_missing_number'));
    });

    test('closings_unavailable (Info) bei null (local-Modus)', () {
      final f = run(closings: null);
      final finding = f.firstWhere((e) => e.code == 'closings_unavailable');
      expect(finding.severity, DatevFindingSeverity.info);
      // leere Liste ≠ null: keine closing-Befunde
      expect(codes(run(closings: const [])),
          isNot(contains('closings_unavailable')));
    });

    test('closing_unbooked (Warnung) bei ungebuchtem Abschluss', () {
      final f = run(closings: [
        const CashClosing(
          orgId: 'o',
          siteId: 'site-1',
          businessDay: '2026-05-10',
          closedByUid: 'u',
          bookedToFinance: false,
        ),
      ]);
      final finding = f.firstWhere((e) => e.code == 'closing_unbooked');
      expect(finding.isWarning, isTrue);
      expect(finding.affectedIds, contains('2026-05-10'));
    });

    test('gebuchter Abschluss löst KEIN closing_unbooked aus', () {
      final f = run(closings: [
        const CashClosing(
          orgId: 'o',
          siteId: 'site-1',
          businessDay: '2026-05-10',
          closedByUid: 'u',
          bookedToFinance: true,
        ),
      ]);
      expect(codes(f), isNot(contains('closing_unbooked')));
    });

    test('revenue_rate_unmapped (Warnung) bei Umsatz-Satz ohne Erlöskonto', () {
      final f = run(closings: [
        const CashClosing(
          orgId: 'o',
          siteId: 'site-1',
          businessDay: '2026-05-10',
          closedByUid: 'u',
          bookedToFinance: true,
          taxes: [
            // 19 % ist gemappt (config), 7 % nicht → unmapped
            ReceiptTax(ratePercent: 19, netCents: 1000),
            ReceiptTax(ratePercent: 7, netCents: 200),
            // netto 0 zählt nicht
            ReceiptTax(ratePercent: 0, netCents: 0),
          ],
        ),
      ]);
      final finding = f.firstWhere((e) => e.code == 'revenue_rate_unmapped');
      expect(finding.isWarning, isTrue);
      expect(finding.affectedIds, ['7']);
    });

    test('Abschluss außerhalb des Jahres wird ignoriert', () {
      final f = run(closings: [
        const CashClosing(
          orgId: 'o',
          siteId: 'site-1',
          businessDay: '2025-12-31',
          closedByUid: 'u',
          bookedToFinance: false,
        ),
      ]);
      expect(codes(f), isNot(contains('closing_unbooked')));
    });
  });
}
