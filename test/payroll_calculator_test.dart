import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/payroll_calculator.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/payroll_settings.dart';

void main() {
  final settings = PayrollSettings.defaults2026();

  PayrollResult calc({
    required int gross,
    TaxClass taxClass = TaxClass.i,
    bool church = false,
    String? state,
    PayrollEmploymentKind kind = PayrollEmploymentKind.standard,
  }) {
    return PayrollCalculator.calculate(
      grossCents: gross,
      taxClass: taxClass,
      churchTax: church,
      federalState: state,
      kind: kind,
      settings: settings,
    );
  }

  group('PayrollCalculator (Richtwert)', () {
    test('standard Klasse I, 3000 € brutto — exakte Positionen', () {
      final r = calc(gross: 300000);
      // § 32a-Tarif: ~304 €/Monat (realistischer Single-Wert, Kl. I) statt der
      // alten Pauschale von 18 % (= 540 €), die niedrige Loehne massiv ueberbesteuerte.
      expect(r.incomeTaxCents, 30408);
      expect(r.soliCents, 0); // Jahres-Lohnsteuer unter Soli-Freigrenze
      expect(r.churchTaxCents, 0);
      expect(r.healthEmployeeCents, 25650); // 8,55 % von 3000 €
      expect(r.careEmployeeCents, 5400); // 1,8 %
      expect(r.pensionEmployeeCents, 27900); // 9,3 %
      expect(r.unemploymentEmployeeCents, 3900); // 1,3 %
      expect(r.employeeSocialTotalCents, 62850);
      expect(r.netCents, 206742); // 300000 - 30408 - 62850
      expect(r.employerTotalCents, 362850);
    });

    test('niedriger Lohn nahe Grundfreibetrag — ~0 Lohnsteuer (Kernkorrektur)',
        () {
      // 1000 €/Monat = 12.000 €/Jahr: nach Pauschalen unter dem Grundfreibetrag
      // -> 0 Lohnsteuer. Die alte Pauschale haette faelschlich 180 € berechnet.
      final r = calc(gross: 100000);
      expect(r.incomeTaxCents, 0);
      expect(r.soliCents, 0);
      // Netto = Brutto - AN-SV (keine Steuer).
      expect(r.netCents, 100000 - r.employeeSocialTotalCents);
    });

    test('Netto- und AG-Invariante halten immer', () {
      for (final gross in [120000, 300000, 600000, 900000]) {
        final r = calc(gross: gross);
        expect(
          r.netCents,
          r.grossCents -
              r.incomeTaxCents -
              r.soliCents -
              r.churchTaxCents -
              r.employeeSocialTotalCents,
        );
        expect(r.employerTotalCents, r.grossCents + r.employerSocialTotalCents);
      }
    });

    test('Klasse V hat höhere Lohnsteuer als Klasse I', () {
      expect(
        calc(gross: 300000, taxClass: TaxClass.v).incomeTaxCents,
        greaterThan(calc(gross: 300000).incomeTaxCents),
      );
    });

    test('Soli ab Schwelle, BBG-Deckelung der KV', () {
      final r = calc(gross: 800000); // 8000 €
      // § 32a, Zone 4 (42 %): ~1854 €/Monat (der hohe Verdiener wurde von der
      // alten 18-%-Pauschale unterbesteuert).
      expect(r.incomeTaxCents, 185425);
      // Soli greift (Jahres-LSt > Freigrenze), in der Milderungszone (11,9 %).
      expect(r.soliCents, 4087);
      // KV/PV auf BBG (5512,50 €) gedeckelt -> kleiner als ungedeckelt.
      expect(r.healthEmployeeCents, 47132); // 8,55 % von 551250
      expect(r.healthEmployeeCents, lessThan((800000 * 0.0855).round()));
      // RV/ALV-Bemessung = volles Brutto (unter RV-BBG).
      expect(r.contributionBaseCents, 800000);
    });

    test('Minijob: keine AN-Abzüge, AG-Pauschale', () {
      final r = calc(gross: 55600, kind: PayrollEmploymentKind.minijob);
      expect(r.incomeTaxCents, 0);
      expect(r.employeeSocialTotalCents, 0);
      expect(r.netCents, 55600);
      expect(r.minijobEmployerFlatCents, 16680); // 30 %
      expect(r.employerTotalCents, 72280);
    });

    test('Midijob: reduzierte AN-Bemessung gegenüber Standard', () {
      final midi = calc(gross: 150000, kind: PayrollEmploymentKind.midijob);
      final std = calc(gross: 150000);
      expect(midi.contributionBaseCents, lessThan(150000));
      expect(midi.contributionBaseCents, greaterThan(0));
      expect(midi.employeeSocialTotalCents,
          lessThan(std.employeeSocialTotalCents));
    });

    test('Kirchensteuer: 9 % Standard, 8 % in Bayern, 0 wenn aus', () {
      // Klasse III (Splittingtarif) -> niedrige Lohnsteuer (~45 €/Monat).
      final base = calc(gross: 300000, taxClass: TaxClass.iii);
      expect(base.churchTaxCents, 0);
      final berlin = calc(gross: 300000, taxClass: TaxClass.iii, church: true);
      expect(berlin.churchTaxCents, 407); // 9 % der Lohnsteuer
      final bayern = calc(
          gross: 300000,
          taxClass: TaxClass.iii,
          church: true,
          state: 'Bayern');
      expect(bayern.churchTaxCents, 361); // 8 %
    });

    test('Richtwert-Flag und Disclaimer vorhanden', () {
      final r = calc(gross: 300000);
      expect(r.isRichtwert, isTrue);
      expect(PayrollResult.disclaimer, contains('Richtwert'));
    });
  });
}
