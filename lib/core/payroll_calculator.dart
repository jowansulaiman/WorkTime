import '../models/payroll_record.dart';
import '../models/payroll_settings.dart';
import 'german_tax.dart';

/// Ergebnis einer Brutto→Netto-Berechnung. Alle Beträge in ganzen Cent.
///
/// **Richtwert** – keine offizielle Lohnabrechnung (siehe [disclaimer]).
class PayrollResult {
  const PayrollResult({
    required this.grossCents,
    required this.kind,
    required this.incomeTaxCents,
    required this.soliCents,
    required this.churchTaxCents,
    required this.healthEmployeeCents,
    required this.careEmployeeCents,
    required this.pensionEmployeeCents,
    required this.unemploymentEmployeeCents,
    required this.healthEmployerCents,
    required this.careEmployerCents,
    required this.pensionEmployerCents,
    required this.unemploymentEmployerCents,
    required this.minijobEmployerFlatCents,
    required this.netCents,
    required this.employerTotalCents,
    required this.contributionBaseCents,
  });

  final int grossCents;
  final PayrollEmploymentKind kind;
  final int incomeTaxCents;
  final int soliCents;
  final int churchTaxCents;
  final int healthEmployeeCents;
  final int careEmployeeCents;
  final int pensionEmployeeCents;
  final int unemploymentEmployeeCents;
  final int healthEmployerCents;
  final int careEmployerCents;
  final int pensionEmployerCents;
  final int unemploymentEmployerCents;

  /// Arbeitgeber-Pauschalabgaben bei Minijob (sonst 0).
  final int minijobEmployerFlatCents;
  final int netCents;
  final int employerTotalCents;

  /// Beitragspflichtige Bemessungsgrundlage der Arbeitnehmer-SV (bei Midijob
  /// reduziert, sonst = gedeckeltes Brutto). Nur zur Transparenz.
  final int contributionBaseCents;

  /// Konstanter Hinweis, der in UI **und** PDF prominent angezeigt werden muss.
  static const String disclaimer =
      'Unverbindlicher Richtwert – keine offizielle Lohnabrechnung. '
      'Steuer- und Sozialversicherungsbeträge sind vereinfacht geschätzt.';

  bool get isRichtwert => true;

  int get employeeSocialTotalCents =>
      healthEmployeeCents +
      careEmployeeCents +
      pensionEmployeeCents +
      unemploymentEmployeeCents;

  int get employerSocialTotalCents =>
      healthEmployerCents +
      careEmployerCents +
      pensionEmployerCents +
      unemploymentEmployerCents +
      minijobEmployerFlatCents;

  int get totalDeductionsCents =>
      incomeTaxCents +
      soliCents +
      churchTaxCents +
      employeeSocialTotalCents;

  /// Baut einen persistierbaren [PayrollRecord] aus diesem Ergebnis + Metadaten.
  PayrollRecord buildRecord({
    String? id,
    required String orgId,
    required String userId,
    required int periodYear,
    required int periodMonth,
    required TaxClass taxClass,
    required bool churchTax,
    String? federalState,
    String? note,
    String? createdByUid,
  }) {
    return PayrollRecord(
      id: id,
      orgId: orgId,
      userId: userId,
      periodYear: periodYear,
      periodMonth: periodMonth,
      grossCents: grossCents,
      taxClass: taxClass,
      churchTax: churchTax,
      federalState: federalState,
      kind: kind,
      incomeTaxCents: incomeTaxCents,
      soliCents: soliCents,
      churchTaxCents: churchTaxCents,
      healthEmployeeCents: healthEmployeeCents,
      careEmployeeCents: careEmployeeCents,
      pensionEmployeeCents: pensionEmployeeCents,
      unemploymentEmployeeCents: unemploymentEmployeeCents,
      healthEmployerCents: healthEmployerCents,
      careEmployerCents: careEmployerCents,
      pensionEmployerCents: pensionEmployerCents,
      unemploymentEmployerCents: unemploymentEmployerCents,
      netCents: netCents,
      employerTotalCents: employerTotalCents,
      note: note,
      createdByUid: createdByUid,
    );
  }
}

/// Reiner, dependency-freier Brutto→Netto-Rechner (vollständig testbar).
///
/// Die Lohnsteuer folgt dem progressiven Tarif nach **§ 32a EStG**
/// ([GermanIncomeTax]/[TaxTariff] aus [PayrollSettings]) – mit Grundfreibetrag
/// und Vorsorgepauschale statt eines pauschalen Prozentsatzes. Sozialversicherung
/// wird hälftig (AN/AG) auf das gedeckelte Brutto gerechnet, Minijob/Midijob als
/// Sonderzweige. Ergebnis bleibt ein **Richtwert** – keine amtliche Abrechnung.
class PayrollCalculator {
  const PayrollCalculator._();

  static PayrollResult calculate({
    required int grossCents,
    required TaxClass taxClass,
    required bool churchTax,
    String? federalState,
    required PayrollEmploymentKind kind,
    required PayrollSettings settings,
  }) {
    final gross = grossCents < 0 ? 0 : grossCents;

    // --- Minijob: keine AN-Abzüge, AG zahlt Pauschalabgaben ----------------
    if (kind == PayrollEmploymentKind.minijob) {
      // AG-Pauschalen aufgeschlüsselt (KV+RV+Umlagen+Pauschsteuer) statt 30 %-Block.
      final flat = _round(gross * settings.minijobEmployerTotalRate);
      return PayrollResult(
        grossCents: gross,
        kind: kind,
        incomeTaxCents: 0,
        soliCents: 0,
        churchTaxCents: 0,
        healthEmployeeCents: 0,
        careEmployeeCents: 0,
        pensionEmployeeCents: 0,
        unemploymentEmployeeCents: 0,
        healthEmployerCents: 0,
        careEmployerCents: 0,
        pensionEmployerCents: 0,
        unemploymentEmployerCents: 0,
        minijobEmployerFlatCents: flat,
        netCents: gross,
        employerTotalCents: gross + flat,
        contributionBaseCents: 0,
      );
    }

    // --- Lohnsteuer / Soli / Kirchensteuer (Richtwert) ---------------------
    // Lohnsteuer nach § 32a EStG (Grundfreibetrag + Progression statt Pauschal-%):
    // Monatsbrutto wird annualisiert, der Tarif angewandt und durch 12 geteilt.
    final tax = GermanIncomeTax.monthly(
      monthlyGrossCents: gross,
      taxClass: taxClass,
      tariff: settings.taxTariff,
      healthEmployeeShare: settings.healthRate / 2,
      healthAdditionalEmployeeShare: settings.healthAdditionalRate / 2,
      careEmployeeShare: settings.careRate / 2,
      bbgKvPvMonthlyCents: settings.bbgKvPvMonthlyCents,
      bbgRvAlvMonthlyCents: settings.bbgRvAlvMonthlyCents,
    );
    final incomeTax = tax.incomeTaxCents;
    final soli = tax.soliCents;
    final churchTaxCents = churchTax
        ? _round(incomeTax * settings.churchTaxRateFor(federalState))
        : 0;

    // --- Bemessungsgrundlagen ----------------------------------------------
    // Arbeitnehmer: bei Midijob reduzierte Bemessung (Übergangsbereich).
    final employeeBaseKvPv = kind == PayrollEmploymentKind.midijob
        ? _midijobBase(gross, settings)
        : _capped(gross, settings.bbgKvPvMonthlyCents);
    final employeeBaseRvAlv = kind == PayrollEmploymentKind.midijob
        ? _midijobBase(gross, settings)
        : _capped(gross, settings.bbgRvAlvMonthlyCents);
    // Arbeitgeber: immer auf das (gedeckelte) volle Brutto.
    final employerBaseKvPv = _capped(gross, settings.bbgKvPvMonthlyCents);
    final employerBaseRvAlv = _capped(gross, settings.bbgRvAlvMonthlyCents);

    final kvHalf = (settings.healthRate + settings.healthAdditionalRate) / 2;
    final pvHalf = settings.careRate / 2;
    final rvHalf = settings.pensionRate / 2;
    final alvHalf = settings.unemploymentRate / 2;

    final healthEmp = _round(employeeBaseKvPv * kvHalf);
    final careEmp = _round(employeeBaseKvPv * pvHalf);
    final pensionEmp = _round(employeeBaseRvAlv * rvHalf);
    final unemploymentEmp = _round(employeeBaseRvAlv * alvHalf);

    final healthEr = _round(employerBaseKvPv * kvHalf);
    final careEr = _round(employerBaseKvPv * pvHalf);
    final pensionEr = _round(employerBaseRvAlv * rvHalf);
    final unemploymentEr = _round(employerBaseRvAlv * alvHalf);

    final employeeSocial = healthEmp + careEmp + pensionEmp + unemploymentEmp;
    final employerSocial = healthEr + careEr + pensionEr + unemploymentEr;

    final net = gross - incomeTax - soli - churchTaxCents - employeeSocial;

    return PayrollResult(
      grossCents: gross,
      kind: kind,
      incomeTaxCents: incomeTax,
      soliCents: soli,
      churchTaxCents: churchTaxCents,
      healthEmployeeCents: healthEmp,
      careEmployeeCents: careEmp,
      pensionEmployeeCents: pensionEmp,
      unemploymentEmployeeCents: unemploymentEmp,
      healthEmployerCents: healthEr,
      careEmployerCents: careEr,
      pensionEmployerCents: pensionEr,
      unemploymentEmployerCents: unemploymentEr,
      minijobEmployerFlatCents: 0,
      netCents: net,
      employerTotalCents: gross + employerSocial,
      contributionBaseCents: employeeBaseRvAlv,
    );
  }

  /// Reduzierte beitragspflichtige Einnahme im Midijob-Übergangsbereich.
  static int _midijobBase(int gross, PayrollSettings settings) {
    final g = settings.minijobCeilingCents.toDouble(); // untere Grenze
    final o = settings.midijobUpperCents.toDouble(); // obere Grenze
    if (gross <= g || o <= g) {
      return gross;
    }
    if (gross >= o) {
      return gross; // oberhalb des Übergangsbereichs: volle Bemessung
    }
    final f = settings.midijobFactorF;
    final factor1 = o / (o - g);
    final factor2 = g / (o - g);
    final base = f * g + (factor1 - factor2 * f) * (gross - g);
    final rounded = base.round();
    if (rounded < 0) return 0;
    return rounded > gross ? gross : rounded;
  }

  static int _capped(int value, int cap) => value > cap ? cap : value;

  static int _round(double value) => value.round();
}
