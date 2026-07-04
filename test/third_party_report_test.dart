import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/third_party_report.dart';
import 'package:worktime_app/models/cash_closing.dart';
import 'package:worktime_app/models/third_party_cash.dart';

/// DH-M6: reine Aggregation der Fremdgelder je Art über mehrere Abschlüsse.
void main() {
  CashClosing closing(String day, List<ThirdPartyAmount> tp) => CashClosing(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: day,
        revenueGrossCents: 10000,
        thirdParty: tp,
        closedByUid: 'admin',
      );

  test('leere Liste → leeres Summary', () {
    final s = computeThirdPartySummary(const []);
    expect(s.isEmpty, isTrue);
    expect(s.totalCents, 0);
  });

  test('Abschlüsse ohne Fremdgeld → leer', () {
    final s = computeThirdPartySummary([closing('2026-07-01', const [])]);
    expect(s.isEmpty, isTrue);
    expect(s.totalCents, 0);
  });

  test('summiert je Art über mehrere Abschlüsse + sortiert absteigend', () {
    final s = computeThirdPartySummary([
      closing('2026-07-03', const [
        ThirdPartyAmount(typeId: 'lotto', typeName: 'Lotto', amountCents: 4500),
        ThirdPartyAmount(typeId: 'post', typeName: 'Post', amountCents: 1200),
      ]),
      closing('2026-07-02', const [
        ThirdPartyAmount(typeId: 'lotto', typeName: 'Lotto', amountCents: 500),
        ThirdPartyAmount(typeId: 'post', typeName: 'Post', amountCents: 300),
      ]),
    ]);
    expect(s.totalCents, 6500);
    expect(s.byType.length, 2);
    // Lotto (5000) vor Post (1500)
    expect(s.byType.first.typeId, 'lotto');
    expect(s.byType.first.totalCents, 5000);
    expect(s.byType.first.count, 2);
    expect(s.byType[1].typeId, 'post');
    expect(s.byType[1].totalCents, 1500);
  });

  test('fällt bei leerem typeName auf typeId zurück', () {
    final s = computeThirdPartySummary([
      closing('2026-07-03',
          const [ThirdPartyAmount(typeId: 'kvg', typeName: '', amountCents: 100)]),
    ]);
    expect(s.byType.first.typeName, 'kvg');
  });
}
