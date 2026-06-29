import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/zeitkonto_calculator.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/work_entry.dart';

WorkEntry _entry(DateTime date, double hours) {
  final start = DateTime(date.year, date.month, date.day, 8);
  return WorkEntry(
    orgId: 'org-1',
    userId: 'emp-1',
    date: date,
    startTime: start,
    endTime: start.add(Duration(minutes: (hours * 60).round())),
    breakMinutes: 0,
  );
}

void main() {
  group('computeZeitkonto (H-B2)', () {
    test('Tagessoll je Wochentag summiert + Saldo aus Ist (WorkEntry)', () {
      // 8h Mo–Fr, 0 am Wochenende, gültig ab 2025.
      final profile = SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2025, 1, 1),
        montagMinutes: 480,
        dienstagMinutes: 480,
        mittwochMinutes: 480,
        donnerstagMinutes: 480,
        freitagMinutes: 480,
      );
      // Juni 2026: 22 Werktage (Mo–Fr) → Soll = 22 × 480 = 10560 min = 176 h.
      final result = computeZeitkonto(
        year: 2026,
        month: 6,
        profiles: [profile],
        entries: [
          _entry(DateTime(2026, 6, 1), 9), // Montag, 1h über
          _entry(DateTime(2026, 6, 2), 8),
        ],
      );

      expect(result.hasSollProfile, isTrue);
      expect(result.sollHours, 176);
      expect(result.istHours, 17); // 9 + 8
      expect(result.saldoHours, 17 - 176);
    });

    test('Monatsarbeitszeit überschreibt die Tagessoll-Summe', () {
      final profile = SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2025, 1, 1),
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 9000, // 150 h fix
        montagMinutes: 480, // wird ignoriert
      );
      final result = computeZeitkonto(
        year: 2026,
        month: 6,
        profiles: [profile],
        entries: [_entry(DateTime(2026, 6, 3), 10)],
      );
      expect(result.sollHours, 150);
      expect(result.istHours, 10);
      expect(result.saldoMinutes, 600 - 9000);
    });

    test('gültig-ab: das am Monatsende aktive Profil bestimmt Monatsarbeitszeit',
        () {
      final alt = SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2025, 1, 1),
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 6000,
      );
      final neu = SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2026, 6, 15),
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 9000,
      );
      final result = computeZeitkonto(
        year: 2026,
        month: 6,
        profiles: [alt, neu], // unsortiert übergeben
        entries: const [],
      );
      expect(result.sollMinutes, 9000); // das ab 15.06. gültige gewinnt
    });

    test('ohne Profil: hasSollProfile=false, Soll=0, nur Ist', () {
      final result = computeZeitkonto(
        year: 2026,
        month: 6,
        profiles: const [],
        entries: [_entry(DateTime(2026, 6, 2), 7.5)],
      );
      expect(result.hasSollProfile, isFalse);
      expect(result.sollMinutes, 0);
      expect(result.istHours, 7.5);
      expect(result.saldoMinutes, 450);
    });

    test('zählt nur Einträge des Abrechnungsmonats', () {
      final profile = SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2025, 1, 1),
      );
      final result = computeZeitkonto(
        year: 2026,
        month: 6,
        profiles: [profile],
        entries: [
          _entry(DateTime(2026, 6, 2), 8),
          _entry(DateTime(2026, 5, 31), 8), // Vormonat → ignoriert
          _entry(DateTime(2026, 7, 1), 8), // Folgemonat → ignoriert
        ],
      );
      expect(result.istHours, 8);
    });
  });
}
