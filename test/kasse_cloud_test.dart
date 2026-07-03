import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/daily_closing.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/pos_daily_stat.dart';
import 'package:worktime_app/models/pos_receipt.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/repositories/firestore_inventory_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Kassen-Modul M2: Modelle (Firestore-Round-Trip), Repository-Methoden und
/// InventoryProvider-Mutatoren (cloud-only-Verhalten, AuditSink).
void main() {
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;
  late FirestoreInventoryRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
    repo = FirestoreInventoryRepository(firestore: firestore);
  });

  Future<InventoryProvider> newCloudProvider() async {
    final provider = InventoryProvider(
      firestoreService: firestoreService,
      inventoryRepository: repo,
      disableAuthentication: false,
    );
    await provider.updateSession(user, localStorageOnly: false);
    return provider;
  }

  CashCount count({
    String siteId = 'site-1',
    DateTime? countedAt,
    int countedCents = 20000,
    int? expectedCents,
    String source = CashCount.sourceManual,
  }) {
    final at = countedAt ?? DateTime(2026, 7, 2, 10);
    return CashCount(
      orgId: 'org-1',
      siteId: siteId,
      businessDay: '2026-07-02',
      countedAt: at,
      countedCents: countedCents,
      expectedCents: expectedCents,
      differenceCents:
          expectedCents == null ? null : countedCents - expectedCents,
      source: source,
      createdByUid: 'owner-1',
    );
  }

  group('Modelle (Firestore-Round-Trip)', () {
    test('CashCount überlebt set/get inkl. Stückelung und Kiosk-Feldern',
        () async {
      final original = count(expectedCents: 19500).copyWith(
        cashRegisterId: 2,
        denominations: {'50.00': 3, '0.50': 10},
        note: 'Wechselgeld eingelegt',
        source: CashCount.sourceKiosk,
        countedByLabel: 'Maria',
        countedByUserId: 'emp-maria',
        kioskSessionId: 'sess-1',
      );
      final doc = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('cashCounts')
          .doc('c-1');
      await doc.set(original.toFirestoreMap());
      final loaded = CashCount.fromFirestore('c-1', (await doc.get()).data()!);

      expect(loaded.siteId, 'site-1');
      expect(loaded.cashRegisterId, 2);
      expect(loaded.countedCents, 20000);
      expect(loaded.expectedCents, 19500);
      expect(loaded.differenceCents, 500);
      expect(loaded.denominations, {'50.00': 3, '0.50': 10});
      expect(loaded.source, CashCount.sourceKiosk);
      expect(loaded.countedByLabel, 'Maria');
      expect(loaded.countedByUserId, 'emp-maria');
      expect(loaded.kioskSessionId, 'sess-1');
      expect(loaded.createdByUid, 'owner-1');
      expect(loaded.createdAt, isNotNull); // serverTimestamp aufgelöst
    });

    test('PosDailyStat überlebt set/get inkl. Steuern/Zahlarten/COGS', () async {
      const original = PosDailyStat(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-07-01',
        salesCount: 12,
        refundCount: 1,
        revenueGrossCents: 11900,
        revenueNetCents: 10000,
        netUncoveredGrossCents: 500,
        taxes: [
          ReceiptTax(
              ratePercent: 19, netCents: 10000, taxCents: 1900,
              grossCents: 11900),
        ],
        paymentsByMethod: {'bar': 7000, 'karte': 4900},
        cashMovementCents: -2000,
        cogsCents: 6000,
        cogsCoveredGrossCents: 11000,
      );
      final doc = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('posDailyStats')
          .doc('2026-07-01-site-1');
      await doc.set(original.toFirestoreMap());
      final loaded = PosDailyStat.fromFirestore(
          '2026-07-01-site-1', (await doc.get()).data()!);

      expect(loaded.salesCount, 12);
      expect(loaded.revenueNetCents, 10000);
      expect(loaded.netUncoveredGrossCents, 500);
      expect(loaded.taxes.single.taxCents, 1900);
      expect(loaded.paymentsByMethod['bar'], 7000);
      expect(loaded.cashMovementCents, -2000);
      expect(loaded.cogsCents, 6000);
      expect(loaded.cogsCoveredGrossCents, 11000);
    });

    test('CashClosing.fromDailyClosing rechnet die Differenz aus der Zählung',
        () {
      const closing = DailyClosing(
        businessDay: '2026-07-02',
        siteId: 'site-1',
        salesCount: 10,
        refundCount: 1,
        revenueGrossCents: 15000,
        taxBuckets: [
          TaxBucket(
              ratePercent: 19, netCents: 12605, taxCents: 2395,
              grossCents: 15000),
        ],
        paymentsByMethod: {'bar': 9000, 'karte': 6000},
        cashMovementCents: -2000,
      );
      final snapshot = CashClosing.fromDailyClosing(
        closing: closing,
        orgId: 'org-1',
        closedByUid: 'owner-1',
        cashExpectedCents: 19500,
        zaehlung: count(countedCents: 19380),
      );
      expect(snapshot.businessDay, '2026-07-02');
      expect(snapshot.revenueGrossCents, 15000);
      expect(snapshot.taxes.single.ratePercent, 19);
      expect(snapshot.cashExpectedCents, 19500);
      expect(snapshot.cashCountedCents, 19380);
      expect(snapshot.cashDifferenceCents, -120);
      expect(snapshot.bookedToFinance, isFalse);

      // Ohne Zählung bleibt die Differenz offen (null, nicht 0).
      final ohneZaehlung = CashClosing.fromDailyClosing(
        closing: closing,
        orgId: 'org-1',
        closedByUid: 'owner-1',
        cashExpectedCents: 19500,
      );
      expect(ohneZaehlung.cashDifferenceCents, isNull);
    });
  });

  group('Repository', () {
    test('addCashCount + getCashCountsInRange: Filter, Fenster, jüngste zuerst',
        () async {
      await repo.addCashCount(count(countedAt: DateTime(2026, 7, 1, 9)));
      await repo.addCashCount(count(countedAt: DateTime(2026, 7, 2, 10)));
      await repo.addCashCount(
          count(countedAt: DateTime(2026, 7, 2, 11), siteId: 'site-2'));
      await repo.addCashCount(count(countedAt: DateTime(2026, 5, 1, 9)));

      final loaded = await repo.getCashCountsInRange(
        'org-1',
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 3),
        siteId: 'site-1',
      );
      expect(loaded, hasLength(2));
      expect(loaded.first.countedAt, DateTime(2026, 7, 2, 10)); // jüngste zuerst
      expect(loaded.every((c) => c.siteId == 'site-1'), isTrue);
    });

    test('createCashClosing ist create-only (zweiter Abschluss wirft)',
        () async {
      const closing = CashClosing(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-07-02',
        revenueGrossCents: 15000,
        closedByUid: 'owner-1',
      );
      await repo.createCashClosing(closing);

      final doc = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('cashClosings')
          .doc('2026-07-02-site-1')
          .get();
      expect(doc.exists, isTrue);

      await expectLater(
        repo.createCashClosing(closing.copyWith(revenueGrossCents: 1)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('bereits abgeschlossen'),
        )),
      );
      // Erstschreibung wurde nicht überschrieben.
      final unchanged = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('cashClosings')
          .doc('2026-07-02-site-1')
          .get();
      expect(unchanged.data()!['revenueGrossCents'], 15000);
    });

    test('markCashClosingBooked kippt nur das Flag', () async {
      await repo.createCashClosing(const CashClosing(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-07-02',
        revenueGrossCents: 15000,
        closedByUid: 'owner-1',
      ));
      await repo.markCashClosingBooked(
          orgId: 'org-1', closingId: '2026-07-02-site-1');
      final loaded = (await repo.getCashClosingsInRange(
              'org-1', '2026-07-01', '2026-07-03'))
          .single;
      expect(loaded.bookedToFinance, isTrue);
      expect(loaded.revenueGrossCents, 15000);
    });

    test('getPosDailyStatsInRange filtert Tag-Range und Standort', () async {
      final statsCol = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('posDailyStats');
      for (final entry in const [
        ('2026-06-30', 'site-1', 100),
        ('2026-07-01', 'site-1', 200),
        ('2026-07-01', 'site-2', 900),
        ('2026-05-01', 'site-1', 50),
      ]) {
        await statsCol.doc('${entry.$1}-${entry.$2}').set(PosDailyStat(
              orgId: 'org-1',
              siteId: entry.$2,
              businessDay: entry.$1,
              revenueGrossCents: entry.$3,
            ).toFirestoreMap());
      }

      final loaded = await repo.getPosDailyStatsInRange(
        'org-1',
        '2026-06-01',
        '2026-07-02',
        siteId: 'site-1',
      );
      expect(loaded, hasLength(2));
      expect(loaded.first.businessDay, '2026-07-01'); // jüngste zuerst
      expect(loaded.map((s) => s.revenueGrossCents), [200, 100]);
    });
  });

  group('InventoryProvider (cloud-only Mutatoren + AuditSink)', () {
    test('saveCashCount wirft im lokalen Modus (kein Hybrid-Fallback)',
        () async {
      final provider = InventoryProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(user);
      await expectLater(
        provider.saveCashCount(count()),
        throwsA(isA<StateError>()),
      );
      expect(await provider.loadKassenbericht(
        granularity: ReportGranularity.week,
        purchasePricesIncludeVat: false,
      ), isEmpty);
    });

    test('saveCashCount pinnt orgId/createdByUid und auditiert', () async {
      final provider = await newCloudProvider();
      final audits = <String>[];
      provider.setAuditSink((
          {required AuditAction action,
          required String entityType,
          String? entityId,
          required String summary}) {
        audits.add('$entityType|$summary');
      });

      await provider.saveCashCount(CashCount(
        orgId: 'falsche-org',
        siteId: 'site-1',
        businessDay: '2026-07-02',
        countedAt: DateTime(2026, 7, 2, 10),
        countedCents: 12345,
        createdByUid: '',
      ));

      final stored = (await repo.getCashCountsInRange(
              'org-1', DateTime(2026, 7, 1), DateTime(2026, 7, 3)))
          .single;
      expect(stored.orgId, 'org-1');
      expect(stored.createdByUid, 'owner-1');
      // App-Pfad: die zählende Person ist der angemeldete Nutzer (ZV-4.1).
      expect(stored.countedByUserId, 'owner-1');
      expect(audits.single, contains('Kassenzählung'));
      expect(audits.single, contains('123,45 €'));
    });

    test('closeBusinessDay schreibt fest, doppelt wirft, Buchen markiert',
        () async {
      final provider = await newCloudProvider();
      final audits = <String>[];
      provider.setAuditSink((
          {required AuditAction action,
          required String entityType,
          String? entityId,
          required String summary}) {
        audits.add(summary);
      });

      const closing = CashClosing(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-07-02',
        revenueGrossCents: 15000,
        cashExpectedCents: 19500,
        cashCountedCents: 19380,
        cashDifferenceCents: -120,
        closedByUid: '',
      );
      await provider.closeBusinessDay(closing);
      final stored = (await repo.getCashClosingsInRange(
              'org-1', '2026-07-01', '2026-07-03'))
          .single;
      expect(stored.id, '2026-07-02-site-1');
      expect(stored.closedByUid, 'owner-1');
      expect(audits.single, contains('festgeschrieben'));
      expect(audits.single, contains('-1,20 €'));

      await expectLater(
        provider.closeBusinessDay(closing),
        throwsA(isA<StateError>()),
      );

      await provider.markClosingBooked(closingId: '2026-07-02-site-1');
      final booked = (await repo.getCashClosingsInRange(
              'org-1', '2026-07-01', '2026-07-03'))
          .single;
      expect(booked.bookedToFinance, isTrue);
    });

    test('loadCashState: Soll = Zählung + Bar/cash seit Anker', () async {
      final provider = await newCloudProvider();
      final receiptsCol = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts');
      await receiptsCol.doc('r-1').set(PosReceipt(
            orgId: 'org-1',
            siteId: 'site-1',
            referenceNumber: 'r-1',
            type: 'sales',
            isRevenue: true,
            businessDay: '2026-07-02',
            transactionDate: DateTime(2026, 7, 2, 12),
            grossCents: 700,
            payments: const [PaymentLine(method: 'bar', amountCents: 700)],
          ).toFirestoreMap());
      await provider.saveCashCount(count(
        countedAt: DateTime(2026, 7, 2, 10),
        countedCents: 20000,
      ));

      final state = await provider.loadCashState(
        siteId: 'site-1',
        asOf: DateTime(2026, 7, 2, 20),
      );
      expect(state.verankert, isTrue);
      expect(state.sollCents, 20700);
      expect(state.tagesBareinnahmenCents, 700);
    });

    test('loadKassenbericht bevorzugt Server-Aggregate (posDailyStats)',
        () async {
      final provider = await newCloudProvider();
      // Ein posDailyStats-Doc für heute — soll gegenüber Belegen gewinnen.
      final today = DateTime(2026, 7, 2);
      final dayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('posDailyStats')
          .doc('$dayStr-site-1')
          .set(const PosDailyStat(
            orgId: 'org-1',
            siteId: 'site-1',
            businessDay: '2026-07-02',
            salesCount: 7,
            revenueGrossCents: 5000,
            revenueNetCents: 4200,
          ).toFirestoreMap());

      final bericht = await provider.loadKassenbericht(
        granularity: ReportGranularity.week,
        purchasePricesIncludeVat: false,
        siteId: 'site-1',
        bucketCount: 1,
        asOf: DateTime(2026, 7, 2, 20),
      );
      final periode = bericht.single;
      expect(periode.umsatzBruttoCents, 5000); // aus Server-Stat, nicht Belegen
      expect(periode.umsatzNettoCents, 4200);
      expect(periode.belege, 7);
    });

    test('loadKassenbericht aggregiert das Belege-Fenster zu Wochen', () async {
      final provider = await newCloudProvider();
      final receiptsCol = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('posReceipts');
      await receiptsCol.doc('r-1').set(PosReceipt(
            orgId: 'org-1',
            siteId: 'site-1',
            referenceNumber: 'r-1',
            type: 'sales',
            isRevenue: true,
            businessDay: '2026-07-01',
            transactionDate: DateTime(2026, 7, 1, 12),
            grossCents: 1190,
            taxes: const [
              ReceiptTax(
                  ratePercent: 19, netCents: 1000, taxCents: 190,
                  grossCents: 1190),
            ],
          ).toFirestoreMap());

      final bericht = await provider.loadKassenbericht(
        granularity: ReportGranularity.week,
        purchasePricesIncludeVat: false,
        siteId: 'site-1',
        bucketCount: 1,
        asOf: DateTime(2026, 7, 2, 20),
      );
      final periode = bericht.single;
      expect(periode.hatDaten, isTrue);
      expect(periode.umsatzBruttoCents, 1190);
      expect(periode.umsatzNettoCents, 1000);
    });
  });
}
