import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/dead_stock.dart';
import 'package:worktime_app/core/reorder_suggestion.dart';
import 'package:worktime_app/core/sales_velocity.dart';
import 'package:worktime_app/core/shrinkage_report.dart';
import 'package:worktime_app/core/assortment_gap.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/sales_insights_provider.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Liefert für site-1 einen Ladenhüter; lässt für die Velocity bei Bedarf einen
/// Fehler werfen (Standort-Wechsel-Szenario).
class _FakeInventory extends InventoryProvider {
  _FakeInventory()
      : super(
            firestoreService:
                FirestoreService(firestore: FakeFirebaseFirestore()));

  bool failVelocities = false;

  @override
  Future<List<ProductVelocity>> computeSiteVelocities({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minReliableDays = SalesVelocity.defaultReliableDays,
    DateTime? asOf,
  }) async {
    if (failVelocities) throw Exception('boom');
    return [
      ProductVelocity(
        productId: 'p-$siteId',
        siteId: siteId,
        soldUnits: 0, // Ladenhüter
        windowDays: 28,
        currentStock: 10,
        purchasePriceCents: 100,
      ),
    ];
  }

  @override
  Future<List<TransferSuggestion>> suggestStockTransfers({
    int windowDays = 60,
    double destinationMaxCoverageDays = 14,
    double targetCoverageDays = 21,
    int minTransferQuantity = 1,
    DateTime? asOf,
  }) async =>
      const [];

  @override
  Future<List<ReorderSuggestion>> suggestReorderLevels({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int safetyDays = 3,
    int coverageDays = 14,
    int defaultLeadTimeDays = 3,
    DateTime? asOf,
  }) async =>
      const [];

  @override
  Future<ShrinkageReport> loadShrinkageReport({
    required String siteId,
    int windowDays = 30,
    DateTime? asOf,
  }) async =>
      const ShrinkageReport(
        items: [],
        shrinkageValueCents: 0,
        surplusValueCents: 0,
        netValueCents: 0,
        netValueByCategory: {},
        unvaluatedCount: 0,
      );

  @override
  Future<List<ListingGap>> loadListingGaps({
    required String siteId,
    int windowDays = SalesVelocity.defaultReliableDays,
    int minSoldUnits = 1,
    DateTime? asOf,
  }) async =>
      const [];
}

void main() {
  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  test('Standort-Wechsel mit Fehler zeigt KEINE fremden Altdaten', () async {
    final inv = _FakeInventory();
    final insights = SalesInsightsProvider()..bind(inv, admin);

    await insights.load(siteId: 'site-1');
    expect(insights.deadStock, isNotEmpty); // site-1 Ladenhüter da
    expect(insights.deadStock.first.productId, 'p-site-1');

    // Wechsel auf site-2, aber die Velocity scheitert.
    inv.failVelocities = true;
    await insights.load(siteId: 'site-2');

    // Es dürfen NICHT site-1-Ladenhüter unter site-2 erscheinen.
    expect(insights.deadStock, isEmpty);
  });

  test('Refresh DESSELBEN Standorts hält bei Fehler den letzten Stand', () async {
    final inv = _FakeInventory();
    final insights = SalesInsightsProvider()..bind(inv, admin);

    await insights.load(siteId: 'site-1');
    expect(insights.deadStock, isNotEmpty);

    inv.failVelocities = true;
    await insights.load(siteId: 'site-1'); // gleicher Standort

    // stale-while-error: letzter Stand bleibt sichtbar.
    expect(insights.deadStock, isNotEmpty);
  });
}
