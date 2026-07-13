// lib/core/kpi_permissions.dart

import '../models/app_user.dart';

/// Kennzahlen-Katalog des Reporting-Bereichs (REPORTING-1).
///
/// Jede Kennzahl, die ein Dashboard/Screen anzeigen kann, bekommt hier eine
/// stabile ID. Die Sichtbarkeit entscheidet AUSSCHLIESSLICH
/// [KpiPermissions.isKpiAllowed] — keine Streu-`if`s in den Screens.
enum KpiId {
  /// Umsatz (brutto) aus Kassendaten — org-weit oder je Standort.
  umsatz,

  /// Rohertrag / Marge (enthält EK-/Wareneinsatz-Wissen).
  rohertrag,

  /// Lohnquote (Lohnkosten ÷ Umsatz, Richtwert).
  lohnquote,

  /// Betriebsergebnis-Richtwert (Umsatz − Wareneinsatz − Lohn).
  betriebsergebnis,

  /// Warenbestandswert zu Einkaufspreisen (gebundenes Kapital).
  bestandswertEk,

  /// Warenbestandswert zu Verkaufspreisen.
  bestandswertVk,

  /// Org-weites Stundenkonto (Soll/Ist/Saldo aller Mitarbeiter).
  zeitkontoOrg,

  /// Anzahl Zeiteinträge, die auf Freigabe warten (`submitted`).
  offeneFreigaben,

  /// Anzahl offener (pending) Abwesenheitsanträge.
  offeneAbwesenheiten,

  /// Personalstunden je Standort (approved-Ist, org-weit).
  personalstundenSite,

  /// Beleg-/Bon-Anzahl je Standort (Kassendaten).
  belegeSite,

  /// Eigene Zeit-Statistik (nur die eigenen Zeiteinträge, `/statistik`).
  eigeneZeitStatistik,
}

/// **Single Source of Truth** für die KPI-Sichtbarkeit (Muster
/// [RoutePermissions] in `lib/routing/route_permissions.dart`).
///
/// **Permission- statt rollenbasiert**, wo die deckenden `firestore.rules`
/// Flag-basiert sind (per-User überschreibbare `UserPermissions`). Einzige
/// bewusste Ausnahme: Kassendaten (`posDailyStats`/`posReceipts`) — deren
/// Rules sind ROLLENbasiert (`isAdmin() || roleIsTeamLeadValue(...)`); ein
/// Flag-Gate wie `canManageShifts` würde dort Rechte ERWEITERN (ein Employee
/// mit `canEditSchedule`-Override hat `canManageShifts == true`, aber die
/// Rules verweigern ihm den Kassendaten-Read).
///
/// **Der Katalog darf Rechte nur VERENGEN; die Daten-Rules bleiben
/// maßgeblich.** Eine hier erlaubte Kennzahl, deren Daten die Rules
/// verweigern, wäre ein Bug — umgekehrt (hier enger als die Rules) ist
/// bewusstes Design.
abstract final class KpiPermissions {
  /// Darf der Nutzer [p] die Kennzahl [kpi] sehen?
  ///
  /// `null`-Profil und inaktive Nutzer sehen NIE eine Kennzahl (alle
  /// KPI-Quell-Collections verlangen via `sameOrg()` einen aktiven Nutzer).
  static bool isKpiAllowed(KpiId kpi, AppUserProfile? p) {
    if (p == null || !p.isActive) {
      return false;
    }
    switch (kpi) {
      // Eigene Zeit-Statistik: Rules-Block `workEntries` erlaubt den
      // Self-Read via `userId == uid && (canViewTimeTracking || canViewReports)`;
      // die Statistik ist die Report-Sicht darauf → `canViewReports`
      // (per-User abschaltbares Flag, spiegelt das bisherige Screen-Gate).
      case KpiId.eigeneZeitStatistik:
        return p.canViewReports;

      // Org-weites Zeitkonto: Rules-Blöcke `workEntries` (read org-weit) und
      // `zeitkontoSnapshots` (read fremde Snapshots) verlangen beide
      // `canManageShifts()` — Freigeber-Recht, schließt Admin ein.
      case KpiId.zeitkontoOrg:
        return p.canManageShifts;

      // Offene Freigaben (`submitted`-Zeiteinträge): Rules-Block `workEntries`
      // read org-weit = `canManageShifts()` (nur Freigeber sehen fremde Zeiten).
      case KpiId.offeneFreigaben:
        return p.canManageShifts;

      // Offene Abwesenheitsanträge org-weit: Rules-Block `absenceRequests`
      // read = `canManageShifts() || self` — die org-weite Zählung braucht
      // den Manager-Zweig.
      case KpiId.offeneAbwesenheiten:
        return p.canManageShifts;

      // Personalstunden je Standort: aggregiert org-weite `workEntries`
      // (approved-Ist) → gleicher Rules-Block/gleiches Recht wie zeitkontoOrg.
      case KpiId.personalstundenSite:
        return p.canManageShifts;

      // Umsatz + Belege: Rules-Blöcke `posDailyStats`/`posReceipts` read =
      // `isAdmin() || roleIsTeamLeadValue(...)` — ROLLENbasiert (siehe
      // Klassen-Doku); deshalb hier `isTeamLead` statt `canManageShifts`.
      case KpiId.umsatz:
      case KpiId.belegeSite:
        return p.isAdmin || p.isTeamLead;

      // Rohertrag/Marge enthält EK-/Wareneinsatz-Wissen → admin-only, wie die
      // bestehenden Gates `/kassenbericht`, `/bestand-insights`, `/sortiment`
      // in `RoutePermissions` (bewusst ENGER als der teamlead-lesbare
      // `posDailyStats`-Rules-Block — Katalog darf nur verengen).
      case KpiId.rohertrag:
        return p.isAdmin;

      // Lohnquote: Zähler sind Lohndaten — Rules-Block `payrollRecords`
      // read = `isAdmin()` (Self-Read nur freigegeben/bezahlt, reicht für die
      // org-weite Quote nicht) → admin-only.
      case KpiId.lohnquote:
        return p.isAdmin;

      // Betriebsergebnis = Umsatz − Wareneinsatz − Lohn: braucht Lohndaten
      // (`payrollRecords` read = `isAdmin()`) UND EK-Wissen → admin-only.
      case KpiId.betriebsergebnis:
        return p.isAdmin;

      // Bestandswert zu EK: gebundenes Kapital/EK-Preise → admin-only, wie
      // das bestehende `/bestand-insights`-Gate in `RoutePermissions`
      // (Rules-Block `products` read = sameOrg; bewusste Verengung).
      case KpiId.bestandswertEk:
        return p.isAdmin;

      // Bestandswert zu VK: kein EK-Wissen, aber eine Führungs-Kennzahl —
      // Bestand VERWALTEN dürfen Admin + Schichtleitung (`canManageInventory`,
      // enthält `isActive`). Rules-Block `products` read = sameOrg (jedes
      // aktive Mitglied sieht einzelne VK-Preise) — Verengung auf die
      // Aggregat-Sicht ist bewusst.
      case KpiId.bestandswertVk:
        return p.canManageInventory;

      // Bewusst INVERTIERTER Routen-Default: eine (künftige) Kennzahl ohne
      // expliziten Eintrag ist für NIEMANDEN sichtbar — Kennzahlen sind
      // sensibler als Navigation (`RoutePermissions` defaultet auf erlaubt).
      // ignore: unreachable_switch_default
      default:
        return false;
    }
  }

  /// Alle für [p] sichtbaren Kennzahlen in Deklarationsreihenfolge — für
  /// Dashboards, die ihre Kacheln aus dem Katalog bauen (keine Streu-`if`s).
  static List<KpiId> visibleKpis(AppUserProfile? p) =>
      [for (final kpi in KpiId.values) if (isKpiAllowed(kpi, p)) kpi];
}
