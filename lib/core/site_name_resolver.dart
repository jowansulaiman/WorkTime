import '../models/site_definition.dart';

/// Löst den **aktuellen** Standortnamen aus der `siteId` gegen die Live-Liste
/// der [SiteDefinition]s auf (Single Source of Truth = `SiteDefinition.name`).
///
/// Hintergrund (H-C2): `siteName` wird in ≥9 Modellen denormalisiert
/// mitgespeichert (Product, Contact, Shift, WorkEntry, …). Bei einer
/// Standort-Umbenennung driften diese Snapshots. Statt eines riskanten
/// Back-Propagation-Massenschreibens über callable-/rules-gated Collections
/// wird der Name zur **Anzeigezeit** aufgelöst; der persistierte `siteName`
/// dient nur noch als Fallback (z. B. für gelöschte Standorte oder im
/// Offline-/Local-Modus ohne Stammdaten).
///
/// Reine Funktion ohne Provider-Abhängigkeit → leicht testbar und überall
/// einsetzbar, wo eine `sites`-Liste vorliegt (Screens lesen sie ohnehin).
String? resolveSiteName(
  Iterable<SiteDefinition> sites,
  String? siteId, {
  String? fallback,
}) {
  if (siteId == null || siteId.trim().isEmpty) {
    return _trimToNull(fallback);
  }
  for (final site in sites) {
    if (site.id == siteId) {
      final name = site.name.trim();
      if (name.isNotEmpty) {
        return name;
      }
      break;
    }
  }
  // Standort nicht (mehr) gefunden → Snapshot als Fallback.
  return _trimToNull(fallback);
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
