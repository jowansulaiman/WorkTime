import 'package:flutter/foundation.dart';

import '../core/assortment_gap.dart';
import '../core/dead_stock.dart';
import '../core/reorder_suggestion.dart';
import '../core/sales_velocity.dart';
import '../core/shrinkage_report.dart';
import '../models/app_user.dart';
import 'inventory_provider.dart';

/// **Read-State der Bestands-Auswertungen (P1.1–P1.3).** Hält das Ergebnis der
/// zustandslosen Rechen-Methoden des [InventoryProvider] (Velocity/Reichweite,
/// Ladenhüter/Umlagerung, Bestellschwellen) für die Auswertungs-UI — bewusst ein
/// EIGENER Provider (nicht den großen InventoryProvider aufblähen), sodass die
/// Inventarliste und die Auswertungen unabhängig voneinander rebuilden.
///
/// Nach Inventory in der Provider-Kette eingehängt; löst sein Cloud-Repository
/// nicht selbst auf, sondern delegiert an die lebende InventoryProvider-Instanz.
class SalesInsightsProvider extends ChangeNotifier {
  InventoryProvider? _inventory;
  String? _orgId;

  bool _loading = false;
  String? _error;
  String? _siteId;
  // Standort, zu dem das aktuell committete Read-State gehört. Bei einem
  // Standort-WECHSEL dürfen fehlgeschlagene Sektionen NICHT die alten (fremden)
  // Daten behalten (sonst Cross-Site-Vermischung); nur ein Refresh DESSELBEN
  // Standorts hält bei Fehler den letzten Stand (stale-while-error).
  String? _dataSiteId;
  int _windowDays = SalesVelocity.defaultReliableDays;
  int _deadStockWindowDays = 60;

  int _shrinkageWindowDays = 90;

  List<ProductVelocity> _velocities = const [];
  List<TransferSuggestion> _transfers = const [];
  List<ReorderSuggestion> _reorders = const [];
  List<ListingGap> _listingGaps = const [];
  ShrinkageReport? _shrinkage;

  bool _disposed = false;

  bool get isLoading => _loading;
  String? get error => _error;
  String? get siteId => _siteId;
  int get windowDays => _windowDays;
  int get deadStockWindowDays => _deadStockWindowDays;

  List<ProductVelocity> get velocities => _velocities;

  /// Ladenhüter (kein Absatz, Bestand > 0) — nach gebundenem Kapital absteigend.
  List<ProductVelocity> get deadStock {
    final list = _velocities.where((v) => v.isDeadStock).toList()
      ..sort((a, b) => b.tiedUpCapitalCents.compareTo(a.tiedUpCapitalCents));
    return list;
  }

  /// Umlagerungsvorschläge, deren Quelle der aktuell gewählte Standort ist.
  List<TransferSuggestion> get transfers => _transfers;

  /// Listungslücken: Renner anderer Läden, die der gewählte Laden nicht führt.
  List<ListingGap> get listingGaps => _listingGaps;

  /// Bestellschwellen-Vorschläge, die vom aktuellen Wert abweichen.
  List<ReorderSuggestion> get reorderChanges =>
      _reorders.where((r) => r.hasChange).toList(growable: false);

  /// Gesamtes totes Kapital (EK) der Ladenhüter in Cent.
  int get tiedUpDeadCapitalCents =>
      deadStock.fold(0, (sum, v) => sum + v.tiedUpCapitalCents);

  int get shrinkageWindowDays => _shrinkageWindowDays;

  /// Schwund-/Inventurdifferenz-Report (P2.2); `null` solange nicht geladen.
  ShrinkageReport? get shrinkage => _shrinkage;

  /// Artikel mit Fehlbestand (negativer Netto-Wert), größter Verlust zuerst.
  List<ShrinkageItem> get shrinkageLosses =>
      (_shrinkage?.items ?? const [])
          .where((i) => i.isValuated && (i.netValueCents ?? 0) < 0)
          .toList(growable: false);

  /// Verknüpft die lebende [InventoryProvider]-Instanz und setzt bei Org-/User-
  /// Wechsel das Read-State zurück (aufgerufen aus dem Proxy in `main.dart`).
  void bind(InventoryProvider inventory, AppUserProfile? profile) {
    _inventory = inventory;
    final orgId = profile?.orgId;
    if (orgId != _orgId) {
      _orgId = orgId;
      _resetData();
      _siteId = null;
      _safeNotify();
    }
  }

  /// Lädt alle drei Auswertungen für [siteId]. [windowDays] = Fenster für
  /// Velocity/Bestellschwellen, [deadStockWindowDays] = (längeres) Fenster für
  /// Ladenhüter/Umlagerung. Nicht-reentrant-sicher über einen Stale-Guard auf
  /// dem Standort (ein späterer Lauf für einen anderen Standort verwirft alte
  /// Ergebnisse nicht falsch).
  Future<void> load({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int deadStockWindowDays = 60,
    int shrinkageWindowDays = 90,
    DateTime? asOf,
  }) async {
    _siteId = siteId;
    _windowDays = windowDays;
    _deadStockWindowDays = deadStockWindowDays;
    _shrinkageWindowDays = shrinkageWindowDays;
    _loading = true;
    _error = null;
    _safeNotify();

    final inv = _inventory;
    if (inv == null) {
      _loading = false;
      _error = 'Auswertung ist derzeit nicht verfügbar.';
      _safeNotify();
      return;
    }

    // Jede Teil-Auswertung unabhängig laden: ein Fehler in einer Sektion
    // verwirft NICHT die erfolgreichen anderen (Teilerfolg statt Alles-oder-
    // nichts). Fehlt eine Sektion, bleibt ihr letzter Stand stehen (stale-while-
    // error). Vollständiger Fehler nur, wenn ALLE Sektionen scheitern.
    List<ProductVelocity>? velocities;
    List<TransferSuggestion>? transfers;
    List<ReorderSuggestion>? reorders;
    List<ListingGap>? listingGaps;
    ShrinkageReport? shrinkage;
    var failures = 0;
    try {
      velocities =
          await inv.computeSiteVelocities(siteId: siteId, windowDays: windowDays, asOf: asOf);
    } catch (_) {
      failures++;
    }
    try {
      transfers =
          await inv.suggestStockTransfers(windowDays: deadStockWindowDays, asOf: asOf);
    } catch (_) {
      failures++;
    }
    try {
      reorders =
          await inv.suggestReorderLevels(siteId: siteId, windowDays: windowDays, asOf: asOf);
    } catch (_) {
      failures++;
    }
    try {
      shrinkage = await inv.loadShrinkageReport(
          siteId: siteId, windowDays: shrinkageWindowDays, asOf: asOf);
    } catch (_) {
      failures++;
    }
    try {
      listingGaps =
          await inv.loadListingGaps(siteId: siteId, windowDays: windowDays, asOf: asOf);
    } catch (_) {
      failures++;
    }

    // Veralteter Lauf: ein neuerer load() für einen anderen Standort besitzt den
    // State (inkl. _loading) — hier NICHT committen.
    if (_disposed || siteId != _siteId) return;
    // Bei Standort-Wechsel werden fehlgeschlagene Sektionen geleert (keine
    // fremden Altdaten); bei Refresh desselben Standorts bleibt der letzte Stand.
    final siteChanged = siteId != _dataSiteId;
    _velocities = velocities ?? (siteChanged ? const [] : _velocities);
    _transfers = transfers != null
        ? transfers
            .where((t) => t.fromProduct.siteId == siteId)
            .toList(growable: false)
        : (siteChanged ? const [] : _transfers);
    _reorders = reorders ?? (siteChanged ? const [] : _reorders);
    _shrinkage = shrinkage ?? (siteChanged ? null : _shrinkage);
    _listingGaps = listingGaps ?? (siteChanged ? const [] : _listingGaps);
    _dataSiteId = siteId;
    _loading = false;
    _error = failures == 5
        ? 'Auswertung konnte nicht geladen werden. Bitte erneut versuchen.'
        : null;
    _safeNotify();
  }

  void _resetData() {
    _velocities = const [];
    _transfers = const [];
    _reorders = const [];
    _listingGaps = const [];
    _shrinkage = null;
    _dataSiteId = null;
    _error = null;
    _loading = false;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
