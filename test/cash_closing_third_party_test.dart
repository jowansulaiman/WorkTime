import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/daily_closing.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/cash_count.dart';
import 'package:worktime_app/models/third_party_cash.dart';

/// DH-M1: Beweist die härteste Invariante — Fremdgeld ist ein separater,
/// additiver Block und beeinflusst weder die Kassendifferenz noch die
/// Umsatz-Aggregate. Plus Serialisierungs-Roundtrip des erweiterten
/// `CashClosing`/`CashCount`.
void main() {
  DailyClosing closing({int revenue = 10000, int cashMove = 10000}) =>
      DailyClosing(
        businessDay: '2026-07-03',
        siteId: 'site-1',
        salesCount: 5,
        refundCount: 0,
        revenueGrossCents: revenue,
        taxBuckets: const [],
        paymentsByMethod: const {'bar': 10000},
        cashMovementCents: cashMove,
      );

  CashCount zaehlung({
    required int counted,
    List<ThirdPartyAmount> thirdParty = const [],
  }) =>
      CashCount(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-07-03',
        countedAt: DateTime(2026, 7, 3, 20),
        countedCents: counted,
        thirdParty: thirdParty,
        createdByUid: 'u1',
      );

  const lotto = ThirdPartyAmount(typeId: 'lotto', typeName: 'Lotto', amountCents: 4500);
  const post = ThirdPartyAmount(typeId: 'post', typeName: 'Post', amountCents: 1200);

  group('Kassendifferenz bleibt Fremdgeld-frei', () {
    test('cashDifferenceCents = counted - expected, OHNE Fremdgeld', () {
      final withFremd = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 9950, thirdParty: const [lotto, post]),
      );
      // eigene Kasse: 9950 - 10000 = -50 (Fremdgeld 5700 NICHT eingerechnet)
      expect(withFremd.cashDifferenceCents, -50);
    });

    test('identische Kassendifferenz mit und ohne Fremdgeld', () {
      final ohne = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 9950),
      );
      final mit = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 9950, thirdParty: const [lotto, post]),
      );
      expect(mit.cashDifferenceCents, ohne.cashDifferenceCents);
      expect(mit.revenueGrossCents, ohne.revenueGrossCents);
      expect(mit.cashCountedCents, ohne.cashCountedCents);
      expect(mit.cashExpectedCents, ohne.cashExpectedCents);
    });
  });

  group('Additive Summen', () {
    test('thirdPartyTotalCents summiert alle Beträge', () {
      final c = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 10000, thirdParty: const [lotto, post]),
      );
      expect(c.thirdPartyTotalCents, 5700);
    });

    test('grandTotalCashCents = Kasse-Ist + Fremdgeld', () {
      final c = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 10000, thirdParty: const [lotto, post]),
      );
      expect(c.grandTotalCashCents, 15700);
    });

    test('leeres Fremdgeld → Summe 0, grandTotal = Kasse', () {
      final c = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 9800),
      );
      expect(c.thirdPartyTotalCents, 0);
      expect(c.grandTotalCashCents, 9800);
    });
  });

  group('Serialisierung', () {
    test('CashClosing round-trippt thirdParty (camelCase)', () {
      final c = CashClosing.fromDailyClosing(
        closing: closing(),
        orgId: 'org-1',
        closedByUid: 'admin',
        cashExpectedCents: 10000,
        zaehlung: zaehlung(counted: 10000, thirdParty: const [lotto, post]),
      );
      final back = CashClosing.fromFirestore('id-1', c.toFirestoreMap());
      expect(back.thirdParty.length, 2);
      expect(back.thirdParty.first.typeId, 'lotto');
      expect(back.thirdPartyTotalCents, 5700);
      // Kassenfelder unverändert
      expect(back.cashDifferenceCents, 0);
    });

    test('CashCount round-trippt thirdParty (camelCase)', () {
      final z = zaehlung(counted: 5000, thirdParty: const [lotto]);
      final back = CashCount.fromFirestore('cc-1', z.toFirestoreMap());
      expect(back.thirdParty.length, 1);
      expect(back.thirdParty.first.amountCents, 4500);
      expect(back.thirdPartyTotalCents, 4500);
    });

    test('Alt-Doc ohne thirdParty → leere Liste (kein Backfill)', () {
      final map = zaehlung(counted: 5000).toFirestoreMap()..remove('thirdParty');
      final back = CashCount.fromFirestore('cc-2', map);
      expect(back.thirdParty, isEmpty);
      expect(back.thirdPartyTotalCents, 0);
    });
  });
}
