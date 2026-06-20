import '../core/firestore_num_parser.dart' as parse;
import '../core/german_tax.dart';
import 'payroll_record.dart';

/// Konfigurierbare Lohn-Sätze für die Brutto→Netto-Berechnung.
///
/// **Wichtig:** Alle Werte sind bewusst vereinfachte Richtwerte. Die Lohnsteuer
/// wird als pauschaler Prozentsatz je Steuerklasse modelliert (NICHT die
/// amtliche Lohnsteuertabelle / der Programmablaufplan). Sätze sind zentral hier
/// gepflegt und können pro Jahr ausgetauscht (`defaults2025`/`defaults2026`) oder
/// pro Org überschrieben werden.
class PayrollSettings {
  const PayrollSettings({
    required this.year,
    required this.incomeTaxRateByClass,
    this.soliRate = 0.055,
    this.soliThresholdCents = 134000,
    this.churchTaxRateDefault = 0.09,
    this.churchTaxRateReduced = 0.08,
    this.reducedChurchTaxStates = const {'BY', 'BW'},
    this.healthRate = 0.146,
    this.healthAdditionalRate = 0.025,
    this.careRate = 0.036,
    this.pensionRate = 0.186,
    this.unemploymentRate = 0.026,
    this.bbgKvPvMonthlyCents = 551250,
    this.bbgRvAlvMonthlyCents = 805000,
    this.minijobCeilingCents = 55600,
    this.minijobEmployerFlatRate = 0.30,
    this.midijobUpperCents = 200000,
    this.midijobFactorF = 0.6683,
    this.taxTariff = TaxTariff.year2026,
  });

  /// Bezugsjahr der Sätze (nur informativ / für Anzeige).
  final int year;

  /// Einkommensteuertarif nach § 32a EStG (Grundfreibetrag + Progression).
  /// Wird vom [PayrollCalculator] für die Lohnsteuer genutzt.
  final TaxTariff taxTariff;

  /// **Veraltet** – früher pauschaler Lohnsteuer-Prozentsatz je Steuerklasse.
  /// Bleibt für Serialisierungs-Rückwärtskompatibilität erhalten, wird aber vom
  /// Rechner nicht mehr verwendet (jetzt: [taxTariff], § 32a-Tarif).
  final Map<TaxClass, double> incomeTaxRateByClass;

  /// Solidaritätszuschlag auf die Lohnsteuer (5,5 %), erst ab Schwelle.
  final double soliRate;
  final int soliThresholdCents;

  /// Kirchensteuersatz (Standard 9 %, ermäßigt 8 % in [reducedChurchTaxStates]).
  final double churchTaxRateDefault;
  final double churchTaxRateReduced;
  final Set<String> reducedChurchTaxStates;

  /// Krankenversicherung (allgemeiner Beitragssatz) + durchschn. Zusatzbeitrag.
  final double healthRate;
  final double healthAdditionalRate;

  /// Pflegeversicherung (Gesamtsatz, hälftige Teilung).
  final double careRate;

  /// Rentenversicherung (Gesamtsatz).
  final double pensionRate;

  /// Arbeitslosenversicherung (Gesamtsatz).
  final double unemploymentRate;

  /// Beitragsbemessungsgrenzen (Monat) für KV/PV bzw. RV/ALV.
  final int bbgKvPvMonthlyCents;
  final int bbgRvAlvMonthlyCents;

  /// Minijob-Grenze und Arbeitgeber-Pauschalabgaben (ca. 30 %).
  final int minijobCeilingCents;
  final double minijobEmployerFlatRate;

  /// Midijob-Obergrenze (Übergangsbereich) und Faktor F.
  final int midijobUpperCents;
  final double midijobFactorF;

  double incomeTaxRateFor(TaxClass taxClass) =>
      incomeTaxRateByClass[taxClass] ?? 0.18;

  double churchTaxRateFor(String? federalState) {
    final code = _stateCode(federalState);
    if (code != null && reducedChurchTaxStates.contains(code)) {
      return churchTaxRateReduced;
    }
    return churchTaxRateDefault;
  }

  /// Standard-Lohnsteuer-Richtwerte je Steuerklasse.
  static const Map<TaxClass, double> _defaultTaxRates = {
    TaxClass.i: 0.18,
    TaxClass.ii: 0.16,
    TaxClass.iii: 0.10,
    TaxClass.iv: 0.18,
    TaxClass.v: 0.30,
    TaxClass.vi: 0.33,
  };

  /// Richtwerte auf Basis der Sozialversicherungswerte 2025.
  factory PayrollSettings.defaults2025() => const PayrollSettings(
        year: 2025,
        incomeTaxRateByClass: _defaultTaxRates,
        bbgKvPvMonthlyCents: 551250, // 5.512,50 €
        bbgRvAlvMonthlyCents: 805000, // 8.050,00 €
        minijobCeilingCents: 55600, // 556 €
        midijobUpperCents: 200000, // 2.000 €
        careRate: 0.036,
      );

  /// Richtwerte (vorläufig) für 2026 – als Default verwendet, bis offizielle
  /// Werte gepflegt sind. Konservativ identisch zu 2025 gehalten.
  factory PayrollSettings.defaults2026() => const PayrollSettings(
        year: 2026,
        incomeTaxRateByClass: _defaultTaxRates,
        bbgKvPvMonthlyCents: 551250,
        bbgRvAlvMonthlyCents: 805000,
        minijobCeilingCents: 55600,
        midijobUpperCents: 200000,
        careRate: 0.036,
      );

  factory PayrollSettings.fromMap(Map<String, dynamic> map) {
    final rawRates = parse.toMap(map['income_tax_rate_by_class']);
    final rates = <TaxClass, double>{};
    for (final entry in rawRates.entries) {
      rates[TaxClassX.fromValue(entry.key)] =
          parse.toDouble(entry.value) ?? 0.18;
    }
    final base = PayrollSettings.defaults2026();
    return PayrollSettings(
      year: parse.toInt(map['year']) ?? base.year,
      incomeTaxRateByClass:
          rates.isEmpty ? base.incomeTaxRateByClass : rates,
      soliRate: parse.toDouble(map['soli_rate']) ?? base.soliRate,
      soliThresholdCents:
          parse.toInt(map['soli_threshold_cents']) ?? base.soliThresholdCents,
      churchTaxRateDefault:
          parse.toDouble(map['church_tax_rate_default']) ??
              base.churchTaxRateDefault,
      churchTaxRateReduced:
          parse.toDouble(map['church_tax_rate_reduced']) ??
              base.churchTaxRateReduced,
      healthRate: parse.toDouble(map['health_rate']) ?? base.healthRate,
      healthAdditionalRate: parse.toDouble(map['health_additional_rate']) ??
          base.healthAdditionalRate,
      careRate: parse.toDouble(map['care_rate']) ?? base.careRate,
      pensionRate: parse.toDouble(map['pension_rate']) ?? base.pensionRate,
      unemploymentRate:
          parse.toDouble(map['unemployment_rate']) ?? base.unemploymentRate,
      bbgKvPvMonthlyCents: parse.toInt(map['bbg_kv_pv_monthly_cents']) ??
          base.bbgKvPvMonthlyCents,
      bbgRvAlvMonthlyCents: parse.toInt(map['bbg_rv_alv_monthly_cents']) ??
          base.bbgRvAlvMonthlyCents,
      minijobCeilingCents: parse.toInt(map['minijob_ceiling_cents']) ??
          base.minijobCeilingCents,
      minijobEmployerFlatRate:
          parse.toDouble(map['minijob_employer_flat_rate']) ??
              base.minijobEmployerFlatRate,
      midijobUpperCents:
          parse.toInt(map['midijob_upper_cents']) ?? base.midijobUpperCents,
      midijobFactorF:
          parse.toDouble(map['midijob_factor_f']) ?? base.midijobFactorF,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'year': year,
      'income_tax_rate_by_class': {
        for (final entry in incomeTaxRateByClass.entries)
          entry.key.value: entry.value,
      },
      'soli_rate': soliRate,
      'soli_threshold_cents': soliThresholdCents,
      'church_tax_rate_default': churchTaxRateDefault,
      'church_tax_rate_reduced': churchTaxRateReduced,
      'health_rate': healthRate,
      'health_additional_rate': healthAdditionalRate,
      'care_rate': careRate,
      'pension_rate': pensionRate,
      'unemployment_rate': unemploymentRate,
      'bbg_kv_pv_monthly_cents': bbgKvPvMonthlyCents,
      'bbg_rv_alv_monthly_cents': bbgRvAlvMonthlyCents,
      'minijob_ceiling_cents': minijobCeilingCents,
      'minijob_employer_flat_rate': minijobEmployerFlatRate,
      'midijob_upper_cents': midijobUpperCents,
      'midijob_factor_f': midijobFactorF,
    };
  }

  static String? _stateCode(String? federalState) {
    if (federalState == null) return null;
    final raw = federalState.trim();
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.startsWith('bay') || lower == 'by') return 'BY';
    if (lower.startsWith('baden') || lower == 'bw') return 'BW';
    return raw.toUpperCase();
  }
}
