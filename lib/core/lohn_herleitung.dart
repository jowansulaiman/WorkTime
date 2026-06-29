import '../models/employment_contract.dart' show SalaryKind;
import '../models/payroll_record.dart' show PayrollLine, TaxClass;
import '../models/payroll_settings.dart';
import 'german_tax.dart';
import 'sfn_zuschlag.dart';

/// Brücke **Zeit → Lohn** (Plan §5.6 / M-B0) und §3b-/§39b-Helfer für die
/// Lohnarten (M-L-a). Reine, dependency-freie Funktionen (Muster
/// `payroll_calculator`/`german_tax`), vom Provider/UI aufgerufen.
///
/// **Architektur-Respekt:** Die itemisierten [PayrollLine]s sind in WorkTime
/// **additiv/informativ** — die Einzelfelder der [PayrollRecord] bleiben für
/// Brutto/Netto maßgeblich. Diese Klasse ändert deshalb kein Brutto/Netto,
/// sondern **leitet** Werte ab (Grundlohn-Vorschlag, §3b-Zeile, §39b-Steuer auf
/// eine Einmalzahlung) — die volle Auszahlungs-/Konto-Verrechnung gehört zu
/// M-L-b. Bleibt durchgängig ein **Richtwert**.
class LohnHerleitung {
  const LohnHerleitung._();

  /// **§5.6 Grundlohn** des Monats in Cent.
  ///
  /// - [SalaryKind.monthly] → das Festgehalt [festgehaltCents] (kanonisch der
  ///   `EmploymentContract.monthlyGrossCents`, sonst der PayrollProfile-Cache).
  /// - [SalaryKind.hourly] → `round(istMinutes / 60 × hourlyRateCents)`, wobei
  ///   [istMinutes] die abgerechneten/erfassten Minuten des Monats inkl.
  ///   bezahlter Abwesenheit (Anrechnungsmatrix §5.4a) sind.
  ///
  /// Liefert den **reinen Cent-Wert** zur Brutto-Vorbefüllung/Anzeige. Im
  /// additiven Lines-Modell IST der Grundlohn das `PayrollRecord.grossCents`-
  /// Hauptfeld — es wird **keine** separate `PayLineKind.grundlohn`-Line
  /// erzeugt (das wäre eine Doppelzählung). Negative Eingaben → 0.
  static int grundlohnCents({
    required SalaryKind salaryKind,
    int? festgehaltCents,
    int istMinutes = 0,
    int hourlyRateCents = 0,
  }) {
    if (salaryKind == SalaryKind.monthly) {
      final fest = festgehaltCents ?? 0;
      return fest < 0 ? 0 : fest;
    }
    if (istMinutes <= 0 || hourlyRateCents <= 0) {
      return 0;
    }
    return (istMinutes * hourlyRateCents / 60).round();
  }

  /// Stundengrundlohn in Cent/h aus Monatsbrutto und Monats-Sollminuten — die
  /// **Bemessung** der §3b-Aufteilung (Plan §5.8b). 0 bei fehlender Sollzeit.
  static int grundlohnProStundeCents({
    required int monatsbruttoCents,
    required int monatsSollMinutes,
  }) {
    if (monatsbruttoCents <= 0 || monatsSollMinutes <= 0) return 0;
    return (monatsbruttoCents * 60 / monatsSollMinutes).round();
  }

  /// Baut eine **§3b-Zuschlagszeile** ([PayrollLine.zuschlag3b]) aus einer Lage
  /// (Zuschlagsart + Dauer) bei [grundlohnCentsProStunde]. Delegiert die
  /// gesetzliche Aufteilung an den Rechenkern [computeSfn3bAnteil] (E9). Die
  /// Lage selbst (welche Stunden Nacht/Sonn-/Feiertag sind) ist Eingabe.
  static PayrollLine sfn3bLine({
    required SfnZuschlagsart art,
    required int grundlohnCentsProStunde,
    required Duration dauer,
    String? name,
    String? datevLohnartNr,
    String? lineTypeId,
  }) {
    final anteil = computeSfn3bAnteil(
      art: art,
      grundlohnCentsProStunde: grundlohnCentsProStunde,
      dauer: dauer,
    );
    return PayrollLine.zuschlag3b(
      anteil: anteil,
      name: name ?? art.label,
      datevLohnartNr: datevLohnartNr,
      lineTypeId: lineTypeId,
    );
  }

  /// **§39b Abs. 3 EStG** — Lohnsteuer/Soli/Kirchensteuer (Richtwert) auf eine
  /// **Einmalzahlung** ([einmalzahlungCents]) neben dem laufenden Monatsbrutto
  /// ([regularMonthlyGrossCents]). Wrappt [GermanIncomeTax.sonstigerBezug] und
  /// rechnet die Kirchensteuer aus der Zuschlag-Bemessung × Kirchensteuersatz.
  ///
  /// **Hinweis (Richtwert/M-L-a):** Die **SV** auf den sonstigen Bezug wird hier
  /// NICHT separat aufgeteilt (Märzklausel/anteilige Jahres-BBG) — fließt erst
  /// ein, wenn der Bezug Teil des SV-Brutto wird (M-D/Lohnlauf). Reine
  /// Lohnsteuer-Vorschau.
  static ({int incomeTaxCents, int soliCents, int churchTaxCents})
      einmalzahlungSteuer({
    required int regularMonthlyGrossCents,
    required int einmalzahlungCents,
    required PayrollSettings settings,
    required TaxClass taxClass,
    bool churchTax = false,
    String? federalState,
    int childCount = 0,
    double? healthAdditionalRateOverride,
  }) {
    if (einmalzahlungCents <= 0) {
      return (incomeTaxCents: 0, soliCents: 0, churchTaxCents: 0);
    }
    final healthAdditionalRate =
        healthAdditionalRateOverride ?? settings.healthAdditionalRate;
    final tax = GermanIncomeTax.sonstigerBezug(
      regularMonthlyGrossCents: regularMonthlyGrossCents,
      sonstigerBezugCents: einmalzahlungCents,
      taxClass: taxClass,
      tariff: settings.taxTariff,
      healthEmployeeShare: settings.healthRate / 2,
      healthAdditionalEmployeeShare: healthAdditionalRate / 2,
      careEmployeeShare: settings.careRate / 2,
      bbgKvPvMonthlyCents: settings.bbgKvPvMonthlyCents,
      bbgRvAlvMonthlyCents: settings.bbgRvAlvMonthlyCents,
      childCount: childCount,
    );
    final churchTaxCents = churchTax
        ? (tax.churchBaseTaxCents * settings.churchTaxRateFor(federalState))
            .round()
        : 0;
    return (
      incomeTaxCents: tax.incomeTaxCents,
      soliCents: tax.soliCents,
      churchTaxCents: churchTaxCents,
    );
  }
}
