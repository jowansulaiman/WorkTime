import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/german_tax.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/payroll_settings.dart';

/// Reine Tests des § 32a-Tarifs ([GermanIncomeTax]) — unabhaengig vom
/// vollstaendigen Brutto→Netto-Rechner.
void main() {
  // AN-SV-Anteile + BBG wie in den Standard-Saetzen (fuer die Vorsorgepauschale).
  final s = PayrollSettings.defaults2026();

  ({int incomeTaxCents, int soliCents}) tax(
    int monthlyGrossCents, {
    TaxClass taxClass = TaxClass.i,
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
  });
}
