import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/staffing_profile.dart';
import 'package:worktime_app/models/pos_receipt.dart';

/// Reine Tests für P3.1 (umsatzbasiertes Besetzungs-Profil).
void main() {
  // [count] Belege eines Standorts zu einer konkreten Stunde an [date] (DateTime).
  List<PosReceipt> receiptsAt(DateTime when, int count,
      {bool revenue = true, bool training = false}) {
    return List.generate(
      count,
      (i) => PosReceipt(
        orgId: 'org-1',
        siteId: 'site-1',
        referenceNumber: '${when.toIso8601String()}-$i',
        type: revenue ? 'sales' : 'cash',
        isRevenue: revenue,
        training: training,
        transactionDate: when.add(Duration(minutes: i % 60)),
      ),
    );
  }

  test('mittelt Belege je Wochentag-Stunde über beobachtete Tage', () {
    // Zwei Freitage (2026-06-19, 2026-06-26), je 16 Uhr: 10 bzw. 30 Belege.
    final receipts = [
      ...receiptsAt(DateTime(2026, 6, 19, 16), 10),
      ...receiptsAt(DateTime(2026, 6, 26, 16), 30),
    ];
    final profile = computeStaffingProfile(
      siteId: 'site-1',
      receipts: receipts,
      receiptsPerStaffPerHour: 30,
    );
    final friday = DateTime(2026, 6, 26).weekday; // 5
    final cell = profile.cellAt(friday, 16)!;
    expect(cell.totalReceipts, 40);
    expect(cell.sampleDays, 2);
    expect(cell.avgReceipts, 20); // 40 / 2 Freitage
  });

  test('Besetzungs-Vorschlag folgt der Stoßzeit-Stunde im Fenster', () {
    // Freitag: 17 Uhr ruhig (10/Std), 18 Uhr Stoßzeit (60/Std). Ein Freitag.
    final receipts = [
      ...receiptsAt(DateTime(2026, 6, 26, 17), 10),
      ...receiptsAt(DateTime(2026, 6, 26, 18), 60),
    ];
    final profile = computeStaffingProfile(
      siteId: 'site-1',
      receipts: receipts,
      receiptsPerStaffPerHour: 30,
    );
    final friday = DateTime(2026, 6, 26).weekday;
    // Fenster 16:00–19:00 -> Spitze 60/Std -> ceil(60/30) = 2 Kräfte.
    expect(
      profile.suggestRequiredCount(
          weekday: friday, startMinute: 16 * 60, endMinute: 19 * 60),
      2,
    );
    // Ruhiges Fenster 17:00–18:00 -> 10/Std -> 1 Kraft.
    expect(
      profile.suggestRequiredCount(
          weekday: friday, startMinute: 17 * 60, endMinute: 18 * 60),
      1,
    );
  });

  test('Fenster ohne Belege ⇒ Mindestbesetzung 1', () {
    final profile = computeStaffingProfile(
      siteId: 'site-1',
      receipts: const [],
    );
    expect(
      profile.suggestRequiredCount(
          weekday: 3, startMinute: 8 * 60, endMinute: 12 * 60),
      1,
    );
    expect(profile.cells, isEmpty);
  });

  test('training/cash und Belege ohne Datum zählen nicht', () {
    final receipts = [
      ...receiptsAt(DateTime(2026, 6, 26, 16), 4),
      ...receiptsAt(DateTime(2026, 6, 26, 16), 50, revenue: false), // cash
      ...receiptsAt(DateTime(2026, 6, 26, 16), 50, training: true),
      const PosReceipt(
          orgId: 'org-1',
          siteId: 'site-1',
          referenceNumber: 'nodate',
          isRevenue: true), // kein transactionDate
    ];
    final profile = computeStaffingProfile(siteId: 'site-1', receipts: receipts);
    final friday = DateTime(2026, 6, 26).weekday;
    expect(profile.cellAt(friday, 16)!.totalReceipts, 4);
  });

  test('großer Stoßzeit-Schnitt skaliert die Besetzung hoch', () {
    final receipts = receiptsAt(DateTime(2026, 6, 26, 12), 95);
    final profile = computeStaffingProfile(
      siteId: 'site-1',
      receipts: receipts,
      receiptsPerStaffPerHour: 30,
    );
    final friday = DateTime(2026, 6, 26).weekday;
    // 95/Std -> ceil(95/30) = 4 Kräfte.
    expect(
      profile.suggestRequiredCount(
          weekday: friday, startMinute: 12 * 60, endMinute: 13 * 60),
      4,
    );
  });
}
