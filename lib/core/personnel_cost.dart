/// Eine Zeile der Personalkosten-Übersicht (Finanz-Bereich im Personal-Modul).
///
/// Reines Wertobjekt: die UI stellt es aus Zeiteinträgen (Stunden), Verträgen
/// (Stundenlohn) und – falls vorhanden – Lohnabrechnungen (AG-Gesamtkosten)
/// zusammen. Gilt sowohl für die Gruppierung pro Mitarbeiter als auch pro
/// Standort (`label` trägt den jeweiligen Namen).
class PersonnelCostRow {
  const PersonnelCostRow({
    required this.label,
    required this.workedHours,
    required this.laborCostCents,
    this.employerTotalCents = 0,
  });

  /// Mitarbeitername oder Standortname.
  final String label;

  /// Geleistete Stunden im Zeitraum.
  final double workedHours;

  /// Direkte Personalkosten = Stunden × Stundenlohn (in Cent).
  final int laborCostCents;

  /// Arbeitgeber-Gesamtkosten aus der Lohnabrechnung (Cent), falls vorhanden.
  final int employerTotalCents;
}
