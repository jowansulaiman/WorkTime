import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/daily_closing.dart';
import 'package:worktime_app/core/daily_closing_posting.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/finance_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Tests für P2.0 — Tagesabschluss → DATEV-Buchung (n JournalEntries je USt-Satz).
void main() {
  const admin = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  DailyClosing closing({
    String day = '2026-06-30',
    String siteId = 'site-1',
    required List<TaxBucket> taxes,
  }) =>
      DailyClosing(
        businessDay: day,
        siteId: siteId,
        salesCount: 1,
        refundCount: 0,
        revenueGrossCents: taxes.fold(0, (s, t) => s + t.grossCents),
        taxBuckets: taxes,
        paymentsByMethod: const {},
        cashMovementCents: 0,
      );

  group('buildDailyClosingEntries (pure)', () {
    test('je USt-Satz eine Netto-Erlös-Zeile mit deterministischer ID', () {
      final entries = buildDailyClosingEntries(
        closing(taxes: const [
          TaxBucket(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
          TaxBucket(ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107),
        ]),
        orgId: 'org-1',
        costCenterId: 'cc-1',
        revenueCostTypeIdByRate: {19: 'ct19', 7: 'ct7'},
      );
      expect(entries, hasLength(2));
      final e19 = entries.firstWhere((e) => e.costTypeId == 'ct19');
      expect(e19.id, 'pos-2026-06-30-site-1-19');
      expect(e19.amountCents, -1000); // netto, negativ (Erlös)
      expect(e19.isCredit, isTrue);
      expect(e19.costCenterId, 'cc-1');
      expect(e19.reference, '2026-06-30');
      final e7 = entries.firstWhere((e) => e.costTypeId == 'ct7');
      expect(e7.amountCents, -100);
    });

    test('Satz ohne zugeordnetes Konto / unbekannter Satz / netto 0 wird übersprungen', () {
      final entries = buildDailyClosingEntries(
        closing(taxes: const [
          TaxBucket(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
          TaxBucket(ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107), // kein Konto
          TaxBucket(ratePercent: null, netCents: 50, taxCents: 0, grossCents: 50),
          TaxBucket(ratePercent: 0, netCents: 0, taxCents: 0, grossCents: 0),
        ]),
        orgId: 'org-1',
        costCenterId: 'cc-1',
        revenueCostTypeIdByRate: {19: 'ct19'},
      );
      expect(entries, hasLength(1));
      expect(entries.single.costTypeId, 'ct19');
    });
  });

  group('FinanceProvider.postDailyClosing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('bucht je Satz eine Zeile und ist idempotent', () async {
      final provider = FinanceProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin, localStorageOnly: true);

      await provider.saveCostCenter(const CostCenter(
          orgId: 'org-1', number: '1001', name: 'Strichmännchen', siteId: 'site-1'));
      await provider.saveCostType(
          const CostType(orgId: 'org-1', number: '8400', name: 'Erlöse 19%'));
      await provider.saveCostType(
          const CostType(orgId: 'org-1', number: '8300', name: 'Erlöse 7%'));

      final ct19 =
          provider.costTypes.firstWhere((t) => t.number == '8400').id!;
      final ct7 = provider.costTypes.firstWhere((t) => t.number == '8300').id!;

      final count = await provider.postDailyClosing(
        closing(taxes: const [
          TaxBucket(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
          TaxBucket(ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107),
        ]),
        revenueCostTypeIdByRate: {19: ct19, 7: ct7},
      );

      expect(count, 2);
      final posted =
          provider.journalEntries.where((e) => e.id!.startsWith('pos-')).toList();
      expect(posted, hasLength(2));
      expect(posted.map((e) => e.amountCents).toSet(), {-1000, -100});

      // Erneut buchen -> deterministische IDs -> keine Doppelbuchung.
      await provider.postDailyClosing(
        closing(taxes: const [
          TaxBucket(ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190),
          TaxBucket(ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107),
        ]),
        revenueCostTypeIdByRate: {19: ct19, 7: ct7},
      );
      expect(provider.journalEntries.where((e) => e.id!.startsWith('pos-')),
          hasLength(2));
    });
  });
}
