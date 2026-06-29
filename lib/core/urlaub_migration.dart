import '../models/sollzeit_profile.dart';

/// Baut – falls nötig – das Migrations-`SollzeitProfile`, das den
/// Jahresurlaubsanspruch eines Mitarbeiters aus den **Altfeldern** in die
/// kanonische Quelle `SollzeitProfile.urlaubstageJahr` überträgt
/// (M0, Vorrangregel §5.1).
///
/// Gibt **null** (No-op) zurück, wenn
/// - der Mitarbeiter bereits ein [SollzeitProfile] hat ([hasSollzeitProfile]) –
///   dort ist `urlaubstageJahr` schon kanonisch (Idempotenz: ein zweiter
///   Migrationslauf überschreibt nichts), oder
/// - keine **deliberate** Altdaten vorliegen: [annualVacationDays] null **und**
///   [vertragVacationDays] entweder null oder = [standardVertragUrlaub]
///   (Default-30 des Vertrags, der auch ungewollt von synthetischen Verträgen
///   gesetzt wird → kein org-weiter Stub für jeden Mitarbeiter). Der Resolver
///   §5.1 liefert für solche Mitarbeiter weiterhin den Vertrags-Default.
///
/// Kopiert die Altwerte **verbatim**, ohne Teilzeit-Skalierung
/// (Audit-Korrektur B1): 5-Tage-Basis (`arbeitstageProWoche`/
/// `urlaubsbasisWerktage` = 5), Tagessoll bleibt 0 (Arbeitszeit-Modell wird
/// erst in M-Z1 gepflegt). Vorrang der Altquellen: [annualVacationDays]
/// (EmployeeProfile) vor [vertragVacationDays] (EmploymentContract).
///
/// **Deterministische Doc-ID** (`urlaub-migration-<userId>`): ein erneuter Lauf
/// upsertet denselben Datensatz statt einen Duplikat-Stub mit Zufalls-ID
/// anzulegen (Idempotenz auch im Cloud-Modus, bevor der Stream das neue Profil
/// zugestellt hat).
SollzeitProfile? buildUrlaubMigrationProfile({
  required String orgId,
  required String userId,
  required bool hasSollzeitProfile,
  int? annualVacationDays,
  int? vertragVacationDays,
  DateTime? gueltigAb,
  int standardVertragUrlaub = 30,
}) {
  if (hasSollzeitProfile) return null;
  // Default-30 des Vertrags zählt nicht als deliberate Altwert.
  final vertragDeliberat =
      (vertragVacationDays != null && vertragVacationDays != standardVertragUrlaub)
          ? vertragVacationDays
          : null;
  final legacy = annualVacationDays ?? vertragDeliberat; // Vorrang §5.1
  if (legacy == null) return null;
  return SollzeitProfile(
    id: 'urlaub-migration-$userId',
    orgId: orgId,
    userId: userId,
    // Weit zurückdatiert (bzw. Eintrittsdatum), damit das Profil für „heute"
    // und vergangene Zeiträume als aktiv aufgelöst wird.
    gueltigAb: gueltigAb ?? DateTime(2020, 1, 1),
    urlaubstageJahr: legacy.toDouble(),
    arbeitstageProWoche: 5,
    urlaubsbasisWerktage: 5,
  );
}
