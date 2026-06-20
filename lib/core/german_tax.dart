import '../models/payroll_record.dart';

/// Parameter des deutschen Einkommensteuertarifs nach **§ 32a EStG** für ein
/// Steuerjahr. Euro-Beträge sind Jahreswerte.
///
/// Adaptiert aus AllTecs `GermanTaxService`/`TaxYearConstants`. Die Zonen-
/// Koeffizienten approximieren den amtlichen Tarif (Stand 2026) und sind pro
/// Jahr austauschbar. Bleibt ein **Richtwert** – keine zertifizierte
/// Lohnbuchhaltung (siehe [PayrollResult.disclaimer]).
class TaxTariff {
  const TaxTariff({
    required this.year,
    required this.grundfreibetragEuro,
    required this.werbungskostenPauschaleEuro,
    required this.sonderausgabenPauschaleEuro,
    required this.vorsorgePauschaleRvPercent,
    required this.soliFreigrenzeJahrEuro,
    required this.zone2UpperEuro,
    required this.zone2A,
    required this.zone2B,
    required this.zone3UpperEuro,
    required this.zone3A,
    required this.zone3B,
    required this.zone3C,
    required this.zone4UpperEuro,
    required this.zone4Rate,
    required this.zone4Subtrahend,
    required this.zone5Rate,
    required this.zone5Subtrahend,
  });

  /// Bezugsjahr (informativ).
  final int year;

  /// Grundfreibetrag (Jahres-Euro) – bis hier 0 % Steuer.
  final double grundfreibetragEuro;

  /// Arbeitnehmer-Pauschbetrag (Werbungskosten).
  final double werbungskostenPauschaleEuro;

  /// Sonderausgaben-Pauschale.
  final double sonderausgabenPauschaleEuro;

  /// Vorsorge-Pauschale: Prozent-Anteil RV (AN), bezogen auf das Bruttojahr.
  final double vorsorgePauschaleRvPercent;

  /// Solidaritätszuschlag-Freigrenze (Jahres-Lohnsteuer).
  final double soliFreigrenzeJahrEuro;

  /// Zone 2 (progressiv ab ~14 %): Obergrenze + quadratische Koeffizienten.
  final double zone2UpperEuro;
  final double zone2A;
  final double zone2B;

  /// Zone 3 (progressiv bis 42 %): Obergrenze + Koeffizienten.
  final double zone3UpperEuro;
  final double zone3A;
  final double zone3B;
  final double zone3C;

  /// Zone 4 (linear 42 %): Obergrenze + Subtrahend.
  final double zone4UpperEuro;
  final double zone4Rate;
  final double zone4Subtrahend;

  /// Zone 5 (Reichensteuer 45 %): Satz + Subtrahend.
  final double zone5Rate;
  final double zone5Subtrahend;

  /// § 32a EStG – 5-Zonen-Tarif 2026 (approximativ).
  static const TaxTariff year2026 = TaxTariff(
    year: 2026,
    grundfreibetragEuro: 12096,
    werbungskostenPauschaleEuro: 1230,
    sonderausgabenPauschaleEuro: 36,
    vorsorgePauschaleRvPercent: 9.3,
    soliFreigrenzeJahrEuro: 18130,
    zone2UpperEuro: 17443,
    zone2A: 932.3,
    zone2B: 1400,
    zone3UpperEuro: 68480,
    zone3A: 176.64,
    zone3B: 2397,
    zone3C: 1015.13,
    zone4UpperEuro: 277825,
    zone4Rate: 0.42,
    zone4Subtrahend: 10911.92,
    zone5Rate: 0.45,
    zone5Subtrahend: 19246.67,
  );
}

/// Reine, dependency-freie Lohnsteuer-/Soli-Berechnung (Richtwert) nach
/// **§ 32a / § 39b EStG**.
///
/// Adaptiert aus AllTecs `GermanTaxService`, auf die von WorkTime benötigten
/// Größen (Lohnsteuer + Solidaritätszuschlag) reduziert. Ein-/Ausgaben sind in
/// **ganzen Cent**, intern wird in Euro (`double`) gerechnet. Die
/// Sozialversicherung selbst rechnet weiterhin der [PayrollCalculator]; hier
/// fließen die AN-SV-Anteile nur in die **Vorsorgepauschale** ein.
class GermanIncomeTax {
  const GermanIncomeTax._();

  /// Monatliche Lohnsteuer + Soli (Cent) für ein Monatsbrutto.
  ///
  /// [healthEmployeeShare]/[healthAdditionalEmployeeShare]/[careEmployeeShare]
  /// sind die AN-Bruchteile der SV-Sätze (z.B. `0.073` für KV) und speisen die
  /// Vorsorgepauschale; [bbgKvPvMonthlyCents]/[bbgRvAlvMonthlyCents] deckeln sie.
  static ({int incomeTaxCents, int soliCents}) monthly({
    required int monthlyGrossCents,
    required TaxClass taxClass,
    required TaxTariff tariff,
    required double healthEmployeeShare,
    required double healthAdditionalEmployeeShare,
    required double careEmployeeShare,
    required int bbgKvPvMonthlyCents,
    required int bbgRvAlvMonthlyCents,
  }) {
    if (monthlyGrossCents <= 0) {
      return (incomeTaxCents: 0, soliCents: 0);
    }
    final annualGross = monthlyGrossCents / 100.0 * 12;
    final stk = _classNumber(taxClass);

    // Vorsorgepauschale (RV-Anteil + KV/PV-Anteil), je auf BBG gedeckelt.
    final rvBbgAnnual = bbgRvAlvMonthlyCents / 100.0 * 12;
    final kvBbgAnnual = bbgKvPvMonthlyCents / 100.0 * 12;
    final vorsorgeRv =
        _min(annualGross, rvBbgAnnual) * tariff.vorsorgePauschaleRvPercent / 100.0;
    final vorsorgeKvPv = _min(annualGross, kvBbgAnnual) *
        (healthEmployeeShare + healthAdditionalEmployeeShare + careEmployeeShare);
    final vorsorge = vorsorgeRv + vorsorgeKvPv;

    final zvE = (annualGross -
            tariff.werbungskostenPauschaleEuro -
            tariff.sonderausgabenPauschaleEuro -
            vorsorge)
        .clamp(0.0, double.infinity);

    final annualTax = _incomeTaxForClass(zvE, stk, tariff);
    final monthlyTax = annualTax / 12;
    final monthlySoli = _soli(annualTax, tariff) / 12;

    return (
      incomeTaxCents: (monthlyTax * 100).round(),
      soliCents: (monthlySoli * 100).round(),
    );
  }

  /// Jahres-Lohnsteuer in Abhängigkeit der Steuerklasse.
  static double _incomeTaxForClass(double zvE, int steuerklasse, TaxTariff t) {
    // Klasse III → Splittingtarif (zvE/2 berechnen, × 2).
    if (steuerklasse == 3) {
      return _tarif32a(zvE / 2, t) * 2;
    }
    // Klasse V/VI → kein Grundfreibetrag, Mindeststeuer approximiert.
    if (steuerklasse == 5 || steuerklasse == 6) {
      final base = _tarif32a(zvE + t.grundfreibetragEuro, t);
      final min = zvE * 0.14;
      return base > min ? base : min;
    }
    return _tarif32a(zvE, t);
  }

  /// § 32a EStG – 5-Zonen-Tarif.
  static double _tarif32a(double zvE, TaxTariff t) {
    final g = t.grundfreibetragEuro;
    if (zvE <= g) return 0;
    if (zvE <= t.zone2UpperEuro) {
      final y = (zvE - g) / 10000;
      return ((t.zone2A * y + t.zone2B) * y).roundToDouble();
    }
    if (zvE <= t.zone3UpperEuro) {
      final z = (zvE - t.zone2UpperEuro) / 10000;
      return ((t.zone3A * z + t.zone3B) * z + t.zone3C).roundToDouble();
    }
    if (zvE <= t.zone4UpperEuro) {
      return (t.zone4Rate * zvE - t.zone4Subtrahend).roundToDouble();
    }
    return (t.zone5Rate * zvE - t.zone5Subtrahend).roundToDouble();
  }

  /// Solidaritätszuschlag (Jahr) mit Freigrenze + Milderungszone.
  static double _soli(double annualTax, TaxTariff t) {
    if (annualTax <= t.soliFreigrenzeJahrEuro) return 0;
    final upper = t.soliFreigrenzeJahrEuro * 1.85;
    if (annualTax < upper) {
      final milderung = 0.119 * (annualTax - t.soliFreigrenzeJahrEuro);
      final regular = annualTax * 0.055;
      return milderung < regular ? milderung : regular;
    }
    return annualTax * 0.055;
  }

  static int _classNumber(TaxClass taxClass) => switch (taxClass) {
        TaxClass.i => 1,
        TaxClass.ii => 2,
        TaxClass.iii => 3,
        TaxClass.iv => 4,
        TaxClass.v => 5,
        TaxClass.vi => 6,
      };

  static double _min(double a, double b) => a < b ? a : b;
}
