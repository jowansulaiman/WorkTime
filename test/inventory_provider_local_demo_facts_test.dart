import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/core/local_demo_inventory_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  const orgId = 'org-local-demo-facts';
  final demoUser = LocalDemoData.adminAccount.toProfile(orgId: orgId);
  const normalLocalUser = AppUserProfile(
    uid: 'local-owner',
    orgId: orgId,
    email: 'owner@example.invalid',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Lokaler Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  InventoryProvider localProvider() => InventoryProvider(
    firestoreService: firestoreService,
    disableAuthentication: true,
  );

  String dayKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  test(
    'lokale Demo liefert mit UI-Defaults aussagekraeftige POS-Analysen',
    () async {
      final provider = localProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(demoUser);

      final now = DateTime.now();
      final sites = LocalDemoInventoryData.siteIdsForOrg(orgId);
      expect(
        provider.products.map((item) => item.siteId).toSet(),
        sites.toSet(),
      );

      for (final siteId in sites) {
        expect(await provider.loadPriceDeviations(siteId: siteId), isNotEmpty);

        final velocities = await provider.computeSiteVelocities(siteId: siteId);
        expect(
          velocities.where((item) => item.soldUnits > 0).length,
          greaterThanOrEqualTo(2),
        );

        final anomalies = await provider.loadCashierAnomalies(
          siteId: siteId,
          asOf: now,
        );
        expect(anomalies.stats, hasLength(6));
        expect(
          anomalies.flagged,
          isNotEmpty,
          reason: 'Die unveraenderte UI-Schwelle z>=2 soll sichtbar greifen.',
        );

        expect(
          await provider.loadDailyClosings(siteId: siteId, asOf: now),
          isNotEmpty,
        );
        expect(
          (await provider.loadBasketAnalysis(siteId: siteId, asOf: now)).pairs,
          isNotEmpty,
        );
        expect(
          (await provider.loadAssortmentAnalysis(
            siteId: siteId,
            asOf: now,
          )).items,
          isNotEmpty,
        );

        final weekdayFactors = await provider.loadWeekdayDemandFactors(
          siteId: siteId,
          asOf: now,
        );
        expect(weekdayFactors.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});

        final staffing = await provider.loadStaffingProfile(
          siteId: siteId,
          asOf: now,
        );
        expect(staffing.cells, isNotEmpty);
        expect(staffing.cells.any((item) => item.sampleDays >= 3), isTrue);
      }

      final benchmark = await provider.loadStoreBenchmark(asOf: now);
      expect(benchmark.perSite, hasLength(3));
      expect(
        benchmark.perSite.every(
          (item) => item.weekdaySampleCount >= 3 && item.weekdayAverage != null,
        ),
        isTrue,
      );
    },
  );

  test(
    'lokale Demo speist Kassen-Reads und Tagesaggregate in-memory',
    () async {
      final provider = localProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(demoUser);

      final now = DateTime.now();
      final sites = LocalDemoInventoryData.siteIdsForOrg(orgId);
      for (final siteId in sites) {
        expect(
          await provider.loadCashCounts(siteId: siteId, asOf: now),
          isNotEmpty,
        );
        final cashState = await provider.loadCashState(
          siteId: siteId,
          asOf: now,
        );
        expect(cashState.verankert, isTrue);
        expect(cashState.letzteZaehlung, isNotNull);
        expect(
          await provider.loadCashClosings(siteId: siteId, asOf: now),
          isNotEmpty,
        );
      }

      final report = await provider.loadKassenbericht(
        granularity: ReportGranularity.week,
        purchasePricesIncludeVat: false,
        asOf: now,
      );
      expect(report, isNotEmpty);
    },
  );

  test(
    'Demo-Kassenmutatoren aendern nur den laufenden In-Memory-State',
    () async {
      final provider = localProvider();
      addTearDown(provider.dispose);
      await provider.updateSession(demoUser);

      final now = DateTime.now();
      final siteId = LocalDemoData.tabakSiteId(orgId);
      final countsBefore = await provider.loadCashCounts(
        siteId: siteId,
        asOf: now,
      );
      await provider.saveCashCount(
        CashCount(
          orgId: '',
          siteId: siteId,
          businessDay: dayKey(now),
          countedAt: now,
          countedCents: 42424,
          note: 'Nur diese Demo-Session',
          createdByUid: '',
        ),
      );
      final countsAfter = await provider.loadCashCounts(
        siteId: siteId,
        asOf: now,
      );
      expect(countsAfter, hasLength(countsBefore.length + 1));
      final addedCount = countsAfter.singleWhere(
        (item) => item.countedCents == 42424,
      );
      expect(addedCount.id, startsWith('demo-cash-count-'));
      expect(addedCount.orgId, orgId);
      expect(addedCount.countedByUserId, demoUser.uid);

      final closingDate = now.add(const Duration(days: 2));
      final closingDay = dayKey(closingDate);
      await provider.closeBusinessDay(
        CashClosing(
          orgId: '',
          siteId: siteId,
          businessDay: closingDay,
          revenueGrossCents: 12345,
          closedByUid: '',
        ),
      );
      await expectLater(
        provider.closeBusinessDay(
          CashClosing(
            orgId: '',
            siteId: siteId,
            businessDay: closingDay,
            closedByUid: '',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      var closings = await provider.loadCashClosings(
        siteId: siteId,
        asOf: closingDate,
      );
      final addedClosing = closings.singleWhere(
        (item) => item.businessDay == closingDay,
      );
      expect(addedClosing.bookedToFinance, isFalse);
      await provider.markClosingBooked(closingId: addedClosing.id!);
      closings = await provider.loadCashClosings(
        siteId: siteId,
        asOf: closingDate,
      );
      expect(
        closings
            .singleWhere((item) => item.businessDay == closingDay)
            .bookedToFinance,
        isTrue,
      );

      // Session beenden und neu aufbauen: die Mutationen wurden nicht in den
      // lokalen Cache geschrieben und sind deshalb verschwunden.
      await provider.updateSession(null);
      await provider.updateSession(demoUser);
      expect(
        (await provider.loadCashCounts(
          siteId: siteId,
          asOf: now,
        )).where((item) => item.countedCents == 42424),
        isEmpty,
      );
      expect(
        (await provider.loadCashClosings(
          siteId: siteId,
          asOf: closingDate,
        )).where((item) => item.businessDay == closingDay),
        isEmpty,
      );
    },
  );

  test(
    'Nicht-Demo-local und Demo-cloud behalten ihr bisheriges Verhalten',
    () async {
      final local = localProvider();
      addTearDown(local.dispose);
      await local.updateSession(normalLocalUser);
      final siteId = LocalDemoData.tabakSiteId(orgId);

      expect(await local.loadDailyClosings(siteId: siteId), isEmpty);
      expect((await local.loadCashierAnomalies(siteId: siteId)).stats, isEmpty);
      expect(await local.loadCashCounts(siteId: siteId), isEmpty);
      await expectLater(
        local.loadPriceDeviations(siteId: siteId),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        local.saveCashCount(
          CashCount(
            orgId: orgId,
            siteId: siteId,
            businessDay: dayKey(DateTime.now()),
            countedAt: DateTime.now(),
            countedCents: 100,
            createdByUid: normalLocalUser.uid,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final cloud = InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: false,
      );
      addTearDown(cloud.dispose);
      await cloud.updateSession(demoUser, localStorageOnly: false);
      await Future<void>.delayed(Duration.zero);

      expect(
        await cloud.loadDailyClosings(siteId: siteId),
        isEmpty,
        reason:
            'Ein Demo-Konto im Cloud-Modus darf keine lokalen Fakten sehen.',
      );
      expect(await cloud.loadCashCounts(siteId: siteId), isEmpty);
    },
  );
}
