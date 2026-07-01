import '../models/app_user.dart';
import 'shell_tab.dart';

/// **Single Source of Truth** für das URL-/Tab-Berechtigungs-Gating.
///
/// Vor der Konsolidierung existierte dieselbe Matrix doppelt: einmal als
/// `_isLocationAllowed` im Router-Redirect und einmal als `_isTabVisible` im
/// Home-Screen — mit einer realen Divergenz beim Laden/Shop-Tab
/// (`canViewInventory || isAdmin` vs. nur `canViewInventory`). Beide Stellen
/// lesen jetzt diese eine Funktion; die Tab-Sichtbarkeit wird aus dem
/// kanonischen Tab-Pfad ([shellTabPaths]) abgeleitet.
///
/// Die serverseitige Spiegelung in `firestore.rules` (`sameOrg` /
/// `canManage*`) bleibt aus Plattformgründen getrennt, muss aber dieselben
/// Regeln tragen (CLAUDE.md, kritische Kopplung #4/#8).
abstract final class RoutePermissions {
  /// Darf der Nutzer [p] die URL [loc] aufrufen? Unbekannte/öffentliche Pfade
  /// sind erlaubt (der Fallback `/` kann so keine Redirect-Schleife auslösen).
  static bool isLocationAllowed(String loc, AppUserProfile? p) {
    switch (loc) {
      case '/': // Heute
      case '/anfragen': // Anfragen
      case '/profil':
      case AppRoutes.settings:
        return true;
      case '/plan':
        return p?.canViewSchedule ?? false;
      case '/zeit':
      // Mitarbeiterseitige Zeitwirtschafts-Bereiche (Self-Service).
      case AppRoutes.zeitErfassung:
      case AppRoutes.zeitStempeln:
      case AppRoutes.zeitStundenkonto:
      case AppRoutes.zeitAbwesenheiten:
      case AppRoutes.zeitAbwesenheitenKalender:
      case AppRoutes.zeitMonatsabschluss:
        return p?.canViewTimeTracking ?? false;
      // Admin-Bereiche der Zeitwirtschaft.
      case AppRoutes.zeitMitarbeiterabschluss:
      case AppRoutes.zeitLohnlauf:
        return p?.isAdmin ?? false;
      case '/kontakte':
        return p?.canViewContacts ?? false;
      case '/laden':
      case AppRoutes.inventory:
      case AppRoutes.customerOrders:
      case AppRoutes.customerWishes:
      case AppRoutes.orderAnalytics:
        return p?.canViewInventory ?? false;
      case AppRoutes.personal:
      case AppRoutes.finance:
      case AppRoutes.team:
      case AppRoutes.auditLog:
      // Besetzungs-Profil (P3.1): Kassendaten-Auswertung -> admin-only.
      case AppRoutes.staffingProfile:
      // Tagesabschluss (P2.0): Kasse → Buchung -> admin-only.
      case AppRoutes.dailyClosing:
      // Laden-Benchmark (P2.3): Umsatz-/Beleg-Auswertung -> admin-only.
      case AppRoutes.storeHealth:
      // Kassierer-Prüfung (P3.2): Leistungskontrolle-sensibel -> admin-only.
      case AppRoutes.cashierAnomaly:
      // Bestand-Insights/Sortimentsanalyse zeigen EK-Preise / Marge / gebundenes
      // Kapital -> admin-only, enger als die übrige Warenwirtschaft
      // (canViewInventory == isActive).
      case AppRoutes.bestandInsights:
      case AppRoutes.sortiment:
        return p?.isAdmin ?? false;
      case AppRoutes.feedbackInbox:
        return p?.canManageFeedback ?? false;
      case AppRoutes.monthReport:
      case AppRoutes.statistics:
        return p?.canViewReports ?? false;
      case AppRoutes.scanner:
        // Scanner ist fester Bottomnav-Tab (Mitte) auf ALLEN Plattformen — kein
        // isNativeMobile-Gate mehr. Off-Mobile fällt der ScannerScreen sauber auf
        // manuelle Barcode-Eingabe zurück (MobileScannerAdapter handhabt Web/
        // Desktop). Bleibt aber an die Inventar-Berechtigung gebunden.
        return p?.canUseScanner ?? false;
      default:
        return true;
    }
  }

  /// Berechtigung für einen Shell-Tab — **abgeleitet** aus dem kanonischen
  /// Tab-Pfad, damit Tab und zugehörige Route nie auseinanderlaufen. Reine
  /// Darstellungs-Sonderfälle (z. B. „Profil-Tab im V2-Design ausblenden")
  /// gehören NICHT hierher, sondern in den Screen.
  static bool isShellTabAllowed(ShellTab tab, AppUserProfile? p) {
    final path = shellTabPaths[tab];
    if (path == null) {
      return true;
    }
    return isLocationAllowed(path, p);
  }
}
