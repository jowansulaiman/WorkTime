import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/kpi_permissions.dart';
import '../core/org_zeit_kpis.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/sollzeit_profile.dart';
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

  void _resetData() {
    _dataKey = null;
    _orgZeit = null;
    _bestandswertEkCents = null;
    _bestandswertVkCents = null;
    _offeneAbwesenheiten = null;
    _loading = false;
    _error = null;
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
