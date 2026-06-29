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
    this.careChildlessSurchargeRate = 0.006,
    this.pensionRate = 0.186,
    this.unemploymentRate = 0.026,
    this.bbgKvPvMonthlyCents = 551250,
    this.bbgRvAlvMonthlyCents = 805000,
    this.minijobCeilingCents = 55600,
    this.minijobEmployerFlatRate = 0.30,
    this.minijobEmployerHealthRate = 0.13,
    this.minijobEmployerPensionRate = 0.15,
    this.minijobEmployerLevyRate = 0.0138,
    this.minijobEmployerFlatTaxRate = 0.02,
    this.midijobUpperCents = 200000,
    this.midijobFactorF = 0.6683,
    this.minimumHourlyWageCents = 1282,
    this.umlageU1Rate = 0.011,
    this.umlageU2Rate = 0.0024,
    this.insolvenzgeldumlageRate = 0.0015,
    this.uvRate = 0.013,
    this.u1Applies = true,
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

  /// PV-Beitragszuschlag für Kinderlose (ab 23 J.) – nur Arbeitnehmer.
  final double careChildlessSurchargeRate;

  /// Rentenversicherung (Gesamtsatz).
  final double pensionRate;

  /// Arbeitslosenversicherung (Gesamtsatz).
  final double unemploymentRate;

  /// Beitragsbemessungsgrenzen (Monat) für KV/PV bzw. RV/ALV.
  final int bbgKvPvMonthlyCents;
  final int bbgRvAlvMonthlyCents;

  /// Minijob-Grenze und Arbeitgeber-Pauschalabgaben.
  final int minijobCeilingCents;

  /// **Veraltet** – früher pauschale 30 %. Bleibt für Serialisierungs-Kompatibilität;
  /// der Rechner nutzt jetzt die aufgeschlüsselten Komponenten ([minijobEmployerTotalRate]).
  final double minijobEmployerFlatRate;

  /// Arbeitgeber-Pauschalen beim gewerblichen Minijob (aufgeschlüsselt statt
  /// eines einzelnen 30-%-Blocks): KV-Pauschale, RV-Pauschale, Umlagen
  /// (U1/U2/InsO) und Pauschsteuer.
  final double minijobEmployerHealthRate;
  final double minijobEmployerPensionRate;
  final double minijobEmployerLevyRate;
  final double minijobEmployerFlatTaxRate;

  /// Gesetzlicher Mindestlohn je Stunde (Cent) – für die Mindestlohn-Warnung.
  final int minimumHourlyWageCents;

  /// Summe der Arbeitgeber-Pauschalsätze beim Minijob (≈ 31,4 %).
  double get minijobEmployerTotalRate =>
      minijobEmployerHealthRate +
      minijobEmployerPensionRate +
      minijobEmployerLevyRate +
      minijobEmployerFlatTaxRate;

  /// True, wenn [hourlyRateCents] unter dem gesetzlichen Mindestlohn liegt
  /// (nur prüfen, wenn ein positiver Stundenlohn vorliegt).
  bool isBelowMinimumWage(int hourlyRateCents) =>
      hourlyRateCents > 0 && hourlyRateCents < minimumHourlyWageCents;

  /// Midijob-Obergrenze (Übergangsbereich) und Faktor F.
  final int midijobUpperCents;
  final double midijobFactorF;

  /// **Arbeitgeber-Umlagen** (nur AG-Kosten, kein AN-Abzug) für reguläre
  /// Beschäftigte – beim Minijob sind sie bereits im Pauschalsatz
  /// ([minijobEmployerLevyRate]) enthalten. Alle als Bruchteil (z. B. `0.011`).
  ///
  /// U1 (Lohnfortzahlung im Krankheitsfall, nur Betriebe mit i. d. R. ≤ 30 MA)
  /// und U2 (Mutterschutz, immer) sind **kassenindividuell**, der UV-Beitrag
  /// (Unfallversicherung) ist **BG-/gefahrtarif-individuell** – alle drei sind
  /// Richtwerte und org-/jahr-überschreibbar. Die **Insolvenzgeldumlage** ist
  /// dagegen ein **bundeseinheitlicher, gesetzlich fixierter** Satz (§ 360
  /// SGB III): seit 2025 wieder 0,15 % (2023/2024 abgesenkt auf 0,06 %), auch
  /// 2026 unverändert.
  final double umlageU1Rate;
  final double umlageU2Rate;
  final double insolvenzgeldumlageRate;
  final double uvRate;

  /// Ob die U1-Umlage greift (i. d. R. nur Betriebe bis ~30 MA). Schaltet die
  /// U1-Belastung ab, ohne den hinterlegten [umlageU1Rate] zu verlieren.
  final bool u1Applies;

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
        minimumHourlyWageCents: 1282, // 12,82 €/h (explizit, nicht aus Default erben)
        careRate: 0.036,
      );

  /// Richtwerte für 2026. Die gesetzlich fixen Werte sind aktualisiert
  /// (Mindestlohn 13,90 €/h, Minijob-Grenze 603 €/Monat). Die Minijob-Grenze ist
  /// zugleich die **Midijob-Untergrenze `g`** in [PayrollCalculator] – daher
  /// rechnerisch relevant, nicht nur ein Anzeige-Label.
  ///
  /// **Platzhalter (noch 2025-Werte):** SV-Beitragssätze (KV-Zusatz, PV) und die
  /// Beitragsbemessungsgrenzen bleiben vorläufig, bis die amtlichen 2026-Werte
  /// gepflegt bzw. über `OrgPayrollSettings` (M-Settings) org-individuell
  /// überschrieben werden. `midijobFactorF` (0,6683) anpassen, sobald der
  /// SV-Gesamtsatz 2026 final ist.
  factory PayrollSettings.defaults2026() => const PayrollSettings(
        year: 2026,
        incomeTaxRateByClass: _defaultTaxRates,
        bbgKvPvMonthlyCents: 551250, // Platzhalter (2025), bis amtlich 2026
        bbgRvAlvMonthlyCents: 805000, // Platzhalter (2025), bis amtlich 2026
        minijobCeilingCents: 60300, // 603 € (= Midijob-Untergrenze g)
        midijobUpperCents: 200000, // 2.000 €
        minimumHourlyWageCents: 1390, // 13,90 €/h (gesetzlich 2026)
        careRate: 0.036, // Platzhalter (2025)
      );

  factory PayrollSettings.fromMap(Map<String, dynamic> map) {
    final rawRates = parse.toMap(map['income_tax_rate_by_class']);
    final rates = <TaxClass, double>{};
    for (final entry in rawRates.entries) {
      rates[TaxClassX.fromValue(entry.key)] =
          parse.toDouble(entry.value) ?? 0.18;
    }
    final base = PayrollSettings.defaults2026();
    final year = parse.toInt(map['year']) ?? base.year;
    return PayrollSettings(
      year: year,
      // taxTariff explizit aus dem Bezugsjahr ableiten, damit ein gespeichertes
      // year den tatsaechlich angewandten Tarif bestimmt (probleme #28).
      taxTariff: _tariffForYear(year),
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
      careChildlessSurchargeRate:
          parse.toDouble(map['care_childless_surcharge_rate']) ??
              base.careChildlessSurchargeRate,
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
      minijobEmployerHealthRate:
          parse.toDouble(map['minijob_employer_health_rate']) ??
              base.minijobEmployerHealthRate,
      minijobEmployerPensionRate:
          parse.toDouble(map['minijob_employer_pension_rate']) ??
              base.minijobEmployerPensionRate,
      minijobEmployerLevyRate:
          parse.toDouble(map['minijob_employer_levy_rate']) ??
              base.minijobEmployerLevyRate,
      minijobEmployerFlatTaxRate:
          parse.toDouble(map['minijob_employer_flat_tax_rate']) ??
              base.minijobEmployerFlatTaxRate,
      midijobUpperCents:
          parse.toInt(map['midijob_upper_cents']) ?? base.midijobUpperCents,
      midijobFactorF:
          parse.toDouble(map['midijob_factor_f']) ?? base.midijobFactorF,
      minimumHourlyWageCents: parse.toInt(map['minimum_hourly_wage_cents']) ??
          base.minimumHourlyWageCents,
      umlageU1Rate:
          parse.toDouble(map['umlage_u1_rate']) ?? base.umlageU1Rate,
      umlageU2Rate:
          parse.toDouble(map['umlage_u2_rate']) ?? base.umlageU2Rate,
      insolvenzgeldumlageRate: parse.toDouble(map['insolvenzgeldumlage_rate']) ??
          base.insolvenzgeldumlageRate,
      uvRate: parse.toDouble(map['uv_rate']) ?? base.uvRate,
      u1Applies: parse.toBool(map['u1_applies']) ?? base.u1Applies,
      reducedChurchTaxStates:
          (map['reduced_church_tax_states'] as List?)?.cast<String>().toSet() ??
              base.reducedChurchTaxStates,
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
      'care_childless_surcharge_rate': careChildlessSurchargeRate,
      'pension_rate': pensionRate,
      'unemployment_rate': unemploymentRate,
      'bbg_kv_pv_monthly_cents': bbgKvPvMonthlyCents,
      'bbg_rv_alv_monthly_cents': bbgRvAlvMonthlyCents,
      'minijob_ceiling_cents': minijobCeilingCents,
      'minijob_employer_flat_rate': minijobEmployerFlatRate,
      'minijob_employer_health_rate': minijobEmployerHealthRate,
      'minijob_employer_pension_rate': minijobEmployerPensionRate,
      'minijob_employer_levy_rate': minijobEmployerLevyRate,
      'minijob_employer_flat_tax_rate': minijobEmployerFlatTaxRate,
      'midijob_upper_cents': midijobUpperCents,
      'midijob_factor_f': midijobFactorF,
      'minimum_hourly_wage_cents': minimumHourlyWageCents,
      'umlage_u1_rate': umlageU1Rate,
      'umlage_u2_rate': umlageU2Rate,
      'insolvenzgeldumlage_rate': insolvenzgeldumlageRate,
      'uv_rate': uvRate,
      'u1_applies': u1Applies,
      'reduced_church_tax_states': reducedChurchTaxStates.toList(),
      // taxTariff wird über [year] abgeleitet (aktuell nur year2026).
    };
  }

  PayrollSettings copyWith({
    int? year,
    Map<TaxClass, double>? incomeTaxRateByClass,
    double? soliRate,
    int? soliThresholdCents,
    double? churchTaxRateDefault,
    double? churchTaxRateReduced,
    Set<String>? reducedChurchTaxStates,
    double? healthRate,
    double? healthAdditionalRate,
    double? careRate,
    double? careChildlessSurchargeRate,
    double? pensionRate,
    double? unemploymentRate,
    int? bbgKvPvMonthlyCents,
    int? bbgRvAlvMonthlyCents,
    int? minijobCeilingCents,
    double? minijobEmployerFlatRate,
    double? minijobEmployerHealthRate,
    double? minijobEmployerPensionRate,
    double? minijobEmployerLevyRate,
    double? minijobEmployerFlatTaxRate,
    int? midijobUpperCents,
    double? midijobFactorF,
    int? minimumHourlyWageCents,
    double? umlageU1Rate,
    double? umlageU2Rate,
    double? insolvenzgeldumlageRate,
    double? uvRate,
    bool? u1Applies,
    TaxTariff? taxTariff,
  }) {
    final resolvedYear = year ?? this.year;
    return PayrollSettings(
      year: resolvedYear,
      incomeTaxRateByClass: incomeTaxRateByClass ?? this.incomeTaxRateByClass,
      soliRate: soliRate ?? this.soliRate,
      soliThresholdCents: soliThresholdCents ?? this.soliThresholdCents,
      churchTaxRateDefault: churchTaxRateDefault ?? this.churchTaxRateDefault,
      churchTaxRateReduced: churchTaxRateReduced ?? this.churchTaxRateReduced,
      reducedChurchTaxStates:
          reducedChurchTaxStates ?? this.reducedChurchTaxStates,
      healthRate: healthRate ?? this.healthRate,
      healthAdditionalRate: healthAdditionalRate ?? this.healthAdditionalRate,
      careRate: careRate ?? this.careRate,
      careChildlessSurchargeRate:
          careChildlessSurchargeRate ?? this.careChildlessSurchargeRate,
      pensionRate: pensionRate ?? this.pensionRate,
      unemploymentRate: unemploymentRate ?? this.unemploymentRate,
      bbgKvPvMonthlyCents: bbgKvPvMonthlyCents ?? this.bbgKvPvMonthlyCents,
      bbgRvAlvMonthlyCents: bbgRvAlvMonthlyCents ?? this.bbgRvAlvMonthlyCents,
      minijobCeilingCents: minijobCeilingCents ?? this.minijobCeilingCents,
      minijobEmployerFlatRate:
          minijobEmployerFlatRate ?? this.minijobEmployerFlatRate,
      minijobEmployerHealthRate:
          minijobEmployerHealthRate ?? this.minijobEmployerHealthRate,
      minijobEmployerPensionRate:
          minijobEmployerPensionRate ?? this.minijobEmployerPensionRate,
      minijobEmployerLevyRate:
          minijobEmployerLevyRate ?? this.minijobEmployerLevyRate,
      minijobEmployerFlatTaxRate:
          minijobEmployerFlatTaxRate ?? this.minijobEmployerFlatTaxRate,
      midijobUpperCents: midijobUpperCents ?? this.midijobUpperCents,
      midijobFactorF: midijobFactorF ?? this.midijobFactorF,
      minimumHourlyWageCents:
          minimumHourlyWageCents ?? this.minimumHourlyWageCents,
      umlageU1Rate: umlageU1Rate ?? this.umlageU1Rate,
      umlageU2Rate: umlageU2Rate ?? this.umlageU2Rate,
      insolvenzgeldumlageRate:
          insolvenzgeldumlageRate ?? this.insolvenzgeldumlageRate,
      uvRate: uvRate ?? this.uvRate,
      u1Applies: u1Applies ?? this.u1Applies,
      // Tarif folgt dem (ggf. geänderten) Bezugsjahr, sofern nicht explizit gesetzt.
      taxTariff: taxTariff ?? _tariffForYear(resolvedYear),
    );
  }

  /// Loest das Bezugsjahr explizit auf den passenden § 32a-Steuertarif auf
  /// (probleme #28). Aktuell ist nur der 2026er-Tarif gepflegt; weitere Jahre
  /// fallen bewusst darauf zurueck. Sobald z.B. ein year2027-Tarif existiert,
  /// hier die zusaetzliche Zuordnung (`2027 => TaxTariff.year2027`) ergaenzen.
  static TaxTariff _tariffForYear(int year) => switch (year) {
        _ => TaxTariff.year2026,
      };

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
