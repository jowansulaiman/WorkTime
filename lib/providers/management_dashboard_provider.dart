import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/kasse_report.dart';
import '../core/kpi_permissions.dart';
import '../core/org_zeit_kpis.dart';
import '../core/site_comparison.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/payroll_record.dart';
import '../models/site_definition.dart';
import '../models/sollzeit_profile.dart';
import '../models/work_entry.dart';
import 'inventory_provider.dart';
import 'personal_provider.dart';
import 'schedule_provider.dart';
import 'zeitwirtschaft_provider.dart';

/// **REPORTING-3 — Management-Dashboard-Read-State.** ChangeNotifier OHNE
/// eigenes Cloud-Repo (Muster `SalesInsightsProvider`): [bind]et die lebenden
/// Quell-Provider und komponiert deren fertige Engines/Getter zu Dashboard-
/// Kennzahlen.
///
/// - **Teilerfolg:** eine fehlgeschlagene Sektion reißt die anderen NICHT mit.
/// - **Stale-Guard:** ein späterer Lauf für einen anderen Zeitraum/Standort
///   verwirft die alten Ergebnisse nicht falsch (zusammengesetzter Lauf-Schlüssel).
/// - **Sichtbarkeit:** jede Sektion wird nur berechnet, wenn [KpiPermissions]
///   sie für das gebundene Profil erlaubt (die Daten-Rules bleiben maßgeblich).
class ManagementDashboardProvider extends ChangeNotifier {
  ZeitwirtschaftProvider? _zeit;
  PersonalProvider? _personal;
  InventoryProvider? _inventory;
  ScheduleProvider? _schedule;
  AppUserProfile? _profile;
  String? _orgId;

  bool _loading = false;
  String? _error;
  bool _disposed = false;

  // Lauf-Schlüssel des aktuell committeten Read-States (year-month:siteId).
  String? _dataKey;

  OrgZeitKpis? _orgZeit;
  int? _bestandswertEkCents;
  int? _bestandswertVkCents;
  int? _offeneAbwesenheiten;

  // Standortvergleich (REPORTING-5) — eigener Read-State mit eigenem Lauf-
  // Schlüssel, weil er unabhängig vom Kennzahlen-Load angestoßen wird.
  SiteVergleich? _siteVergleich;
  bool _siteVergleichLoading = false;
  String? _siteVergleichError;
  String? _siteVergleichKey;

  bool get isLoading => _loading;
  String? get error => _error;

  /// Org-weite Zeit-Kennzahlen (nur bei `canManageShifts`), sonst null.
  OrgZeitKpis? get orgZeit => _orgZeit;

  /// Warenbestandswert zu EK (nur Admin), sonst null.
  int? get bestandswertEkCents => _bestandswertEkCents;

  /// Warenbestandswert zu VK (nur `canManageInventory`), sonst null.
  int? get bestandswertVkCents => _bestandswertVkCents;

  /// Anzahl offener (pending) Abwesenheitsanträge (nur `canManageShifts`).
  int? get offeneAbwesenheiten => _offeneAbwesenheiten;

  /// Standortvergleich des zuletzt geladenen Zeitraums (REPORTING-5); `null`,
  /// solange nichts geladen wurde oder das Profil den Vergleich nicht sehen darf.
  SiteVergleich? get siteVergleich => _siteVergleich;
  bool get isSiteVergleichLoading => _siteVergleichLoading;
  String? get siteVergleichError => _siteVergleichError;

  /// Die für das gebundene Profil sichtbaren Kennzahlen (Katalog-gesteuert).
  List<KpiId> get visibleKpis => KpiPermissions.visibleKpis(_profile);

  /// Verknüpft die lebenden Quell-Provider (aus dem Proxy in `main.dart`).
  /// Setzt bei Org-/User-Wechsel das Read-State zurück.
  void bind({
    required ZeitwirtschaftProvider zeit,
    required PersonalProvider personal,
    required InventoryProvider inventory,
    required ScheduleProvider schedule,
    required AppUserProfile? profile,
  }) {
    _zeit = zeit;
    _personal = personal;
    _inventory = inventory;
    _schedule = schedule;
    _profile = profile;
    final orgId = profile?.orgId;
    if (orgId != _orgId) {
      _orgId = orgId;
      _resetData();
      _safeNotify();
    }
  }

  bool _allowed(KpiId kpi) => KpiPermissions.isKpiAllowed(kpi, _profile);

  /// Lädt/aktualisiert die Kennzahlen für [year]/[month] und optional [siteId].
  /// Jede Sektion ist unabhängig (Teilerfolg); Sichtbarkeit über
  /// [KpiPermissions]. Ein späterer Lauf für einen anderen Schlüssel gewinnt.
  Future<void> load({
    required int year,
    required int month,
    String? siteId,
  }) async {
    final key = '$year-$month:${siteId ?? ''}';
    _dataKey = key;
    _loading = true;
    _error = null;
    _safeNotify();

    final zeit = _zeit;
    final personal = _personal;
    final inventory = _inventory;
    final schedule = _schedule;

    OrgZeitKpis? orgZeit;
    int? ekCents;
    int? vkCents;
    int? offeneAbw;
    var sections = 0;
    var failures = 0;

    // Org-Zeit (canManageShifts) — komponiert die pure Engine über den
    // ZeitwirtschaftProvider (Gate + Kiosk-Ausschluss dort).
    if (_allowed(KpiId.zeitkontoOrg) && zeit != null && personal != null) {
      sections++;
      try {
        final memberIds =
            personal.members.map((m) => m.uid).toList(growable: false);
        final profilesByUser = <String, List<SollzeitProfile>>{
          for (final m in personal.members)
            m.uid: personal.sollzeitProfilesForUser(m.uid),
        };
        orgZeit = await zeit.loadOrgZeitKpis(
          jahr: year,
          monat: month,
          memberIds: memberIds,
          profilesByUser: profilesByUser,
        );
      } catch (error) {
        failures++;
        AppLogger.warning('Dashboard: Org-Zeit-Sektion fehlgeschlagen',
            error: error);
      }
    }

    // Bestandswert EK (admin) — sync-Getter des InventoryProviders.
    if (_allowed(KpiId.bestandswertEk) && inventory != null) {
      sections++;
      try {
        ekCents = inventory.totalStockValuePurchaseCents(siteId: siteId);
      } catch (error) {
        failures++;
        AppLogger.warning('Dashboard: Bestandswert-EK-Sektion fehlgeschlagen',
            error: error);
      }
    }

    // Bestandswert VK (canManageInventory).
    if (_allowed(KpiId.bestandswertVk) && inventory != null) {
      sections++;
      try {
        vkCents = inventory.totalStockValueSellingCents(siteId: siteId);
      } catch (error) {
        failures++;
        AppLogger.warning('Dashboard: Bestandswert-VK-Sektion fehlgeschlagen',
            error: error);
      }
    }

    // Offene Abwesenheiten (canManageShifts) — pending aus dem ScheduleProvider.
    if (_allowed(KpiId.offeneAbwesenheiten) && schedule != null) {
      sections++;
      try {
        offeneAbw = schedule.allAbsenceRequests
            .where((a) => a.status == AbsenceStatus.pending)
            .length;
      } catch (error) {
        failures++;
        AppLogger.warning('Dashboard: Abwesenheiten-Sektion fehlgeschlagen',
            error: error);
      }
    }

    // Stale-Guard: nur committen, wenn zwischenzeitlich kein neuerer Lauf für
    // einen anderen Schlüssel gestartet wurde.
    if (_disposed || _dataKey != key) return;

    _orgZeit = orgZeit;
    _bestandswertEkCents = ekCents;
    _bestandswertVkCents = vkCents;
    _offeneAbwesenheiten = offeneAbw;
    _loading = false;
    // Vollständiger Fehler nur, wenn ALLE (mind. 1) Sektionen scheiterten.
    _error = (sections > 0 && failures == sections)
        ? 'Die Kennzahlen konnten nicht geladen werden.'
        : null;
    _safeNotify();
  }

  /// **REPORTING-5 — Standortvergleich laden.** Komponiert je Standort die
  /// Monats-Kassenperiode ([InventoryProvider.loadKassenbericht]) und die
  /// Bestandswerte, dazu die org-weiten Monats-Zeiteinträge
  /// ([ZeitwirtschaftProvider.loadOrgWorkEntriesForMonth]) und die
  /// finalisierten Monats-Abrechnungen, und reicht sie in die pure Engine
  /// [computeSiteVergleich].
  ///
  /// - **Teilerfolg** (Muster [load]): eine fehlgeschlagene Sektion (Zeit oder
  ///   ein einzelner Standort) reißt die anderen NICHT mit; ein Vollfehler wird
  ///   nur gemeldet, wenn ALLE Sektionen scheiterten.
  /// - **Stale-Guard:** ein späterer Lauf für einen anderen Monat gewinnt; der
  ///   alte committet sein Ergebnis nicht mehr.
  /// - **Sichtbarkeit** ([KpiPermissions]): ohne `umsatz`-Recht wird gar nicht
  ///   geladen (die Route ist ohnehin admin-only — dies ist die Defensive); der
  ///   Rohertrag nur bei `rohertrag`, der Lohnkosten-Richtwert nur bei
  ///   `lohnquote`, der EK-/VK-Bestandswert je nach `bestandswertEk`/`Vk`.
  ///
  /// [purchasePricesIncludeVat] = Org-Schalter §3.4 (aus dem `FeatureFlag`-
  /// Provider; wird vom aufrufenden Screen durchgereicht, damit dieser Provider
  /// keine weitere Provider-Bindung braucht).
  Future<void> loadSiteVergleich({
    required int year,
    required int month,
    required bool purchasePricesIncludeVat,
  }) async {
    final key = '$year-$month';
    _siteVergleichKey = key;
    _siteVergleichLoading = true;
    _siteVergleichError = null;
    _safeNotify();

    // Gate: ohne Recht auf die Umsatz-/Beleg-Kennzahl gibt es nichts zu
    // vergleichen. Leeres Ergebnis, kein Fehler (bewusste stille Degradation).
    if (!_allowed(KpiId.umsatz)) {
      if (_disposed || _siteVergleichKey != key) return;
      _siteVergleich = null;
      _siteVergleichLoading = false;
      _safeNotify();
      return;
    }

    final inventory = _inventory;
    final zeit = _zeit;
    final personal = _personal;
    final schedule = _schedule;

    final includeRohertrag = _allowed(KpiId.rohertrag);
    final showEk = _allowed(KpiId.bestandswertEk);
    final showVk = _allowed(KpiId.bestandswertVk);
    final showLohn = _allowed(KpiId.lohnquote);

    // Repräsentativer Stichtag am MONATSENDE: der Kassenbericht bindet sein
    // Datenfenster an `asOf` — am Monatsanfang lüde er nur den ersten Tag.
    final asOf = DateTime(year, month + 1, 0);
    final monthStart = DateTime(year, month);

    var sections = 0;
    var failures = 0;

    // (A) Org-weite Monats-Zeiteinträge (Personalstunden-Basis; nur approved
    // filtert die Engine via `countsAsIst`).
    var periodEntries = const <WorkEntry>[];
    if (zeit != null) {
      sections++;
      try {
        periodEntries = await zeit.loadOrgWorkEntriesForMonth(monthStart);
      } catch (error) {
        failures++;
        AppLogger.warning(
            'Standortvergleich: Monats-Zeiteinträge fehlgeschlagen',
            error: error);
      }
    }

    // (B) Je konfiguriertem Standort die Monats-Kassenperiode + Bestandswerte.
    final inputs = <SiteVergleichInput>[];
    final sites = schedule?.sites ?? const <SiteDefinition>[];
    for (final site in sites) {
      final id = site.id;
      if (id == null || id.trim().isEmpty) continue; // nicht scope-bar
      sections++;
      KassenPeriode? kassen;
      try {
        if (inventory != null) {
          final periods = await inventory.loadKassenbericht(
            granularity: ReportGranularity.month,
            purchasePricesIncludeVat: purchasePricesIncludeVat,
            siteId: id,
            bucketCount: 1,
            asOf: asOf,
          );
          for (final p in periods) {
            if (p.start.year == year && p.start.month == month) {
              kassen = p;
              break;
            }
          }
          kassen ??= periods.isNotEmpty ? periods.last : null;
        }
      } catch (error) {
        failures++;
        AppLogger.warning(
            'Standortvergleich: Kassenperiode für Standort fehlgeschlagen',
            error: error);
      }
      inputs.add(SiteVergleichInput(
        siteId: id,
        siteName: site.name,
        kassen: kassen,
        bestandswertEkCents: (showEk && inventory != null)
            ? inventory.totalStockValuePurchaseCents(siteId: id)
            : null,
        bestandswertVkCents: (showVk && inventory != null)
            ? inventory.totalStockValueSellingCents(siteId: id)
            : null,
      ));
    }

    // (C) Lohnkosten-Richtwert-Basis: org-weite finalisierte Abrechnungen des
    // Monats (nur bei Lohn-Sichtbarkeit; sonst leer → keine Allokation, kein
    // stiller 50/50-Split — siehe `computeSiteVergleich`).
    final payroll = (showLohn && personal != null)
        ? personal.payrollForPeriod(year, month)
        : const <PayrollRecord>[];

    final result = computeSiteVergleich(
      sites: inputs,
      periodEntries: periodEntries,
      payroll: payroll,
      includeRohertrag: includeRohertrag,
    );

    // Stale-Guard: nur committen, wenn kein neuerer Lauf gestartet wurde.
    if (_disposed || _siteVergleichKey != key) return;
    _siteVergleich = result;
    _siteVergleichLoading = false;
    _siteVergleichError = (sections > 0 && failures == sections)
        ? 'Der Standortvergleich konnte nicht geladen werden.'
        : null;
    _safeNotify();
  }

  void _resetData() {
    _dataKey = null;
    _orgZeit = null;
    _bestandswertEkCents = null;
    _bestandswertVkCents = null;
    _offeneAbwesenheiten = null;
    _loading = false;
    _error = null;
    _siteVergleich = null;
    _siteVergleichKey = null;
    _siteVergleichLoading = false;
    _siteVergleichError = null;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
