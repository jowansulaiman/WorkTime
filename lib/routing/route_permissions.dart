import '../core/app_config.dart';
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
    // Mitarbeiter-Detail-Deep-Link `/personal/{uid}` matcht keinen exakten
    // `case` unten und fiele sonst auf `default:true` (KEIN Gate). Admin-only,
    // spiegelt den `AppRoutes.personal`-Case (kritische Kopplung #4/#7). Muss
    // in `firestore.rules` (Personal-Collections admin/self) gespiegelt bleiben.
    if (loc.startsWith('/personal/')) {
      return p?.isAdmin ?? false;
    }
    // Kontakt-Detail-Deep-Link `/kontakte/{id}` matcht keinen exakten `case`
    // unten und fiele sonst auf `default:true`. Spiegelt den `/kontakte`-Tab-
    // Case (canViewContacts = jedes aktive Mitglied — NICHT admin-only wie
    // Personal). In `firestore.rules` (contacts read=sameOrg) gespiegelt.
    if (loc.startsWith('/kontakte/')) {
      return p?.canViewContacts ?? false;
    }
    switch (loc) {
      case '/': // Heute
      case '/anfragen': // Anfragen
      case '/profil':
      case AppRoutes.settings:
        return true;
      // „Meine Personalakte" (PA-2.4): jeder angemeldete (aktive) Nutzer sieht
      // seine EIGENEN Daten (self-scoped Streams + Rules).
      case AppRoutes.meineAkte:
        return p != null;
      // Mitteilungs-Inbox (PERSONAL-9/Q4): jeder angemeldete Nutzer sieht seine
      // EIGENEN Mitteilungen (self-scoped `recipientUid`-Query + Rules).
      case AppRoutes.mitteilungen:
        return p != null;
      // Wissen/Hilfe: jeder angemeldete Nutzer sieht die Fach-Doku; die
      // Technik-Doku blendet der Screen fuer Nicht-Admins aus.
      case AppRoutes.knowledge:
        return p != null;
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
      // Zeit-Freigabe (Z7/E2): Admin UND Teamleiter dürfen fremde Zeiten
      // genehmigen (canManageShifts); der Server (Rules/Callable) verhindert
      // Selbst-Genehmigung + Admin-Ziele.
      case AppRoutes.zeitMitarbeiterabschluss:
        return p?.canManageShifts ?? false;
      // Lohnlauf bleibt admin-only (abrechnungssensibel).
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
      // Hermes-Paketshop (Plan §7.6): alle aktiven Mitarbeiter (Betreiber §0).
      // Gespiegelt in app_user.canViewParcels + firestore.rules canManageParcels.
      case AppRoutes.paketshop:
        return p?.canViewParcels ?? false;
      // Geführter Inventur-Modus: bucht Bestand (recordStocktake) -> nur wer
      // den Bestand verwalten darf (Admin + Schichtleitung), enger als das
      // Ansehen der Warenwirtschaft (canViewInventory == isActive). Spiegelt
      // das Screen-interne Gate (leerer Zustand mit Hinweis).
      case AppRoutes.inventur:
        return p?.canManageInventory ?? false;
      // Tagesabschluss/Kasse (P2.0 / Kassen-Modul M3): einsehen + zählen dürfen
      // Admin UND Teamleitung (deckungsgleich mit den posReceipts-Rules).
      // Abschließen/Buchen bleibt per Button-Gate im Screen admin-only.
      case AppRoutes.dailyClosing:
        return (p?.isAdmin ?? false) || (p?.isTeamLead ?? false);
      case AppRoutes.personal:
      case AppRoutes.finance:
      case AppRoutes.auditLog:
      // Besetzungs-Profil (P3.1): Kassendaten-Auswertung -> admin-only.
      case AppRoutes.staffingProfile:
      // Laden-Benchmark (P2.3): Umsatz-/Beleg-Auswertung -> admin-only.
      case AppRoutes.storeHealth:
      // Kassierer-Prüfung (P3.2): Leistungskontrolle-sensibel -> admin-only.
      case AppRoutes.cashierAnomaly:
      // Bestand-Insights/Sortimentsanalyse zeigen EK-Preise / Marge / gebundenes
      // Kapital -> admin-only, enger als die übrige Warenwirtschaft
      // (canViewInventory == isActive).
      case AppRoutes.bestandInsights:
      case AppRoutes.sortiment:
      // Kassenbericht (Kassen-Modul M4): Umsatz/Käufe/Rohertrag (EK/Marge/Gewinn)
      // -> admin-only, gleiche Begründung wie bestandInsights/sortiment.
      case AppRoutes.kassenbericht:
        return p?.isAdmin ?? false;
      // Werbe-Displays (Digital Signage): zentrale Verwaltung der Store-TVs
      // (Werbebilder hochladen, Playlists, öffentliche Player-URLs) -> admin-only
      // UND nur bei aktivem Feature-Flag (sonst könnte ein Admin per Deep-Link in
      // den Bereich, obwohl die Hub-Kachel aus ist — analog /passwoerter).
      // Server-seitig in firestore.rules gespiegelt (isAdmin auf signageDisplays/
      // adMedia/publicDisplays).
      case AppRoutes.signage:
        return (p?.isAdmin ?? false) && AppConfig.signageEnabled;
      // Passwortmanager (§11): jeder aktive Nutzer sieht eigene + freigegebene
      // Einträge; die zentrale Verwaltung ist im Screen gegatet. Nur bei
      // aktivem Feature (Blaze/KMS) erreichbar.
      case AppRoutes.passwords:
        return (p?.isActive ?? false) && AppConfig.passwordManagerEnabled;
      case AppRoutes.feedbackInbox:
        return p?.canManageFeedback ?? false;
      // Management-Dashboard (REPORTING-4): org-weite Kennzahlen für Führung —
      // Admin UND Schichtleitung (canManageShifts, konsistent mit den
      // workEntries-/OrgZeit-Rules). Einzelne Kennzahlen blendet der Screen über
      // KpiPermissions zusätzlich aus (z. B. Lohn/EK nur Admin).
      case AppRoutes.kennzahlen:
        return (p?.isAdmin ?? false) || (p?.canManageShifts ?? false);
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
