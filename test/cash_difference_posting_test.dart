import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/cash_difference_posting.dart';
import 'package:worktime_app/models/cash_closing.dart';

/// Reine Tests der Kassendifferenz-Buchung (Kassen-Modul M6, §8a).
void main() {
  CashClosing closing({int? diff}) => CashClosing(
        orgId: 'org-1',
        siteId: 'site-1',
        businessDay: '2026-06-30',
        cashDifferenceCents: diff,
        closedByUid: 'u1',
      );

  test('Fehlbetrag → positive Kosten, idempotente ID', () {
    final entry = buildCashDifferenceEntry(
      closing(diff: -250),
      orgId: 'org-1',
      costCenterId: 'cc-1',
      costTypeId: 'ct-1',
      createdByUid: 'u1',
    );
    expect(entry, isNotNull);
    expect(entry!.id, 'pos-diff-2026-06-30-site-1');
    expect(entry.amountCents, 250); // Kosten (Fehlbetrag) = positiv
    expect(entry.costCenterId, 'cc-1');
    expect(entry.costTypeId, 'ct-1');
    expect(entry.description, contains('Fehlbetrag'));
    expect(entry.date, DateTime(2026, 6, 30, 12));
  });

  test('Überschuss → negative Gutschrift', () {
    final entry = buildCashDifferenceEntry(
      closing(diff: 120),
      orgId: 'org-1',
      costCenterId: 'cc-1',
      costTypeId: 'ct-1',
    );
    expect(entry!.amountCents, -120); // Gutschrift (Überschuss) = negativ
    expect(entry.description, contains('Überschuss'));
  });

  test('keine Differenz (null oder 0) → keine Buchung', () {
    expect(
      buildCashDifferenceEntry(closing(diff: null),
          orgId: 'org-1', costCenterId: 'cc-1', costTypeId: 'ct-1'),
      isNull,
    );
    expect(
      buildCashDifferenceEntry(closing(diff: 0),
          orgId: 'org-1', costCenterId: 'cc-1', costTypeId: 'ct-1'),
      isNull,
    );
  });

  test('kein Konto/keine Kostenstelle → keine Buchung', () {
    expect(
      buildCashDifferenceEntry(closing(diff: -100),
          orgId: 'org-1', costCenterId: '', costTypeId: 'ct-1'),
      isNull,
    );
    expect(
      buildCashDifferenceEntry(closing(diff: -100),
          orgId: 'org-1', costCenterId: 'cc-1', costTypeId: ''),
      isNull,
    );
  });
}
