import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/german_tax.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/payroll_settings.dart';

/// Reine Tests des § 32a-Tarifs ([GermanIncomeTax]) — unabhaengig vom
/// vollstaendigen Brutto→Netto-Rechner.
void main() {
  // AN-SV-Anteile + BBG wie in den Standard-Saetzen (fuer die Vorsorgepauschale).
  final s = PayrollSettings.defaults2026();

  ({int incomeTaxCents, int soliCents, int churchBaseTaxCents}) tax(
    int monthlyGrossCents, {
    TaxClass taxClass = TaxClass.i,
    int childCount = 0,
  }) {
    return GermanIncomeTax.monthly(
      monthlyGrossCents: monthlyGrossCents,
      taxClass: taxClass,
      tariff: s.taxTariff,
      healthEmployeeShare: s.healthRate / 2,
      healthAdditionalEmployeeShare: s.healthAdditionalRate / 2,
      careEmployeeShare: s.careRate / 2,
      bbgKvPvMonthlyCents: s.bbgKvPvMonthlyCents,
      bbgRvAlvMonthlyCents: s.bbgRvAlvMonthlyCents,
      childCount: childCount,
    );
  }

  group('GermanIncomeTax (§ 32a Richtwert)', () {
    test('kein/negatives Brutto -> 0', () {
      expect(tax(0).incomeTaxCents, 0);
      expect(tax(-100).incomeTaxCents, 0);
    });

    test('Lohn nahe/unter Grundfreibetrag -> 0 Lohnsteuer', () {
      // 1.000 €/Monat: nach Pauschalen klar unter dem Grundfreibetrag.
      expect(tax(100000).incomeTaxCents, 0);
    });

    test('Lohnsteuer steigt monoton mit dem Brutto', () {
      final a = tax(150000).incomeTaxCents;
      final b = tax(300000).incomeTaxCents;
      final c = tax(600000).incomeTaxCents;
      expect(a, lessThan(b));
      expect(b, lessThan(c));
    });

    test('Steuerklassen-Ordnung: III < I < V', () {
      final i = tax(300000).incomeTaxCents;
      final iii = tax(300000, taxClass: TaxClass.iii).incomeTaxCents;
      final v = tax(300000, taxClass: TaxClass.v).incomeTaxCents;
      expect(iii, lessThan(i));
      expect(i, lessThan(v));
    });

    test('Soli: 0 unter Freigrenze, > 0 bei hoher Lohnsteuer', () {
      expect(tax(300000).soliCents, 0);
      expect(tax(800000).soliCents, greaterThan(0));
    });

    test('ohne Kinder ist churchBaseTax == Lohnsteuer', () {
      final r = tax(400000);
      expect(r.churchBaseTaxCents, r.incomeTaxCents);
    });

    test('Steuerklasse II: Entlastungsbetrag senkt die Lohnsteuer ggü. I', () {
      expect(
        tax(300000, taxClass: TaxClass.ii).incomeTaxCents,
        lessThan(tax(300000).incomeTaxCents),
      );
    });

    test(
        'Kinderfreibeträge senken NUR die Zuschlagsteuer-Bemessung, nicht die '
        'Lohnsteuer (§ 51a EStG)', () {
      final ohne = tax(400000, taxClass: TaxClass.iv);
      final mit = tax(400000, taxClass: TaxClass.iv, childCount: 2);
      // Lohnsteuer unverändert ...
      expect(mit.incomeTaxCents, ohne.incomeTaxCents);
      // ... aber die Bemessung für Soli/Kirchensteuer sinkt.
      expect(mit.churchBaseTaxCents, lessThan(ohne.incomeTaxCents));
    });

    test('Steuerklasse I: Kinder ändern nichts (keine Freibeträge auf Karte)',
        () {
      final ohne = tax(400000);
      final mit = tax(400000, childCount: 3);
      expect(mit.incomeTaxCents, ohne.incomeTaxCents);
      expect(mit.churchBaseTaxCents, ohne.churchBaseTaxCents);
    });

    test('Kinderfreibetrags-Zähler je Steuerklasse (III voll, II/IV halb)', () {
      double units(int stk, int kinder) =>
          GermanIncomeTax.childAllowanceUnitsForTesting(stk, kinder);
      expect(units(3, 2), 2.0); // Kl. III: voller Zähler
      expect(units(2, 2), 1.0); // Kl. II: halber Zähler (0,5/Kind)
      expect(units(4, 2), 1.0); // Kl. IV: halber Zähler
      expect(units(1, 2), 0.0); // Kl. I: keiner
      expect(units(5, 2), 0.0); // Kl. V: keiner
      expect(units(2, 0), 0.0); // keine Kinder
    });

    test('Steuerklasse II: Kinder senken Bemessung, nicht Lohnsteuer', () {
      final ohne = tax(450000, taxClass: TaxClass.ii);
      final mit = tax(450000, taxClass: TaxClass.ii, childCount: 2);
      expect(mit.incomeTaxCents, ohne.incomeTaxCents);
      expect(mit.churchBaseTaxCents, lessThan(ohne.incomeTaxCents));
    });
  });
}
