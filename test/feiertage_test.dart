import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/feiertage.dart';

void main() {
  group('Oster-Computus', () {
    test('bekannte Ostersonntage', () {
      expect(ostersonntag(2026), DateTime(2026, 4, 5, 12));
      expect(ostersonntag(2025), DateTime(2025, 4, 20, 12));
      expect(ostersonntag(2024), DateTime(2024, 3, 31, 12));
    });
  });

  group('normalizeBundesland', () {
    test('Namen und Kürzel → Kürzel, Default SH', () {
      expect(normalizeBundesland('Schleswig-Holstein'), 'SH');
      expect(normalizeBundesland('Bayern'), 'BY');
      expect(normalizeBundesland('by'), 'BY');
      expect(normalizeBundesland('Baden-Württemberg'), 'BW');
      expect(normalizeBundesland('Sachsen-Anhalt'), 'ST');
      expect(normalizeBundesland('Sachsen'), 'SN');
      expect(normalizeBundesland(null), 'SH');
      expect(normalizeBundesland('  '), 'SH');
      expect(normalizeBundesland('Quatschland'), 'SH');
    });
  });

  group('Feiertage Schleswig-Holstein 2026', () {
    final sh = feiertageImJahr(2026, bundesland: 'Schleswig-Holstein');

    test('enthält die 10 SH-Feiertage', () {
      final erwartet = {
        DateTime(2026, 1, 1, 12), // Neujahr
        DateTime(2026, 4, 3, 12), // Karfreitag
        DateTime(2026, 4, 6, 12), // Ostermontag
        DateTime(2026, 5, 1, 12), // Tag der Arbeit
        DateTime(2026, 5, 14, 12), // Christi Himmelfahrt
        DateTime(2026, 5, 25, 12), // Pfingstmontag
        DateTime(2026, 10, 3, 12), // Tag der Deutschen Einheit
        DateTime(2026, 10, 31, 12), // Reformationstag (SH seit 2018)
        DateTime(2026, 12, 25, 12), // 1. Weihnachtstag
        DateTime(2026, 12, 26, 12), // 2. Weihnachtstag
      };
      expect(sh, erwartet);
      expect(sh.length, 10);
    });

    test('KEIN Heilige Drei Könige / Fronleichnam / Allerheiligen in SH', () {
      expect(sh.contains(DateTime(2026, 1, 6, 12)), isFalse);
      expect(sh.contains(DateTime(2026, 11, 1, 12)), isFalse);
      // Fronleichnam 2026 = Ostern+60 = 4.6.
      expect(sh.contains(DateTime(2026, 6, 4, 12)), isFalse);
    });

    test('istFeiertag respektiert Tageszeit-Normierung', () {
      expect(istFeiertag(DateTime(2026, 4, 3), bundesland: 'SH'), isTrue);
      expect(istFeiertag(DateTime(2026, 4, 3, 8, 30), bundesland: 'SH'), isTrue);
      expect(istFeiertag(DateTime(2026, 4, 7), bundesland: 'SH'), isFalse);
    });
  });

  group('Bundesland-Spezifika', () {
    test('Heilige Drei Könige nur in BY/BW/ST', () {
      expect(istFeiertag(DateTime(2026, 1, 6), bundesland: 'BY'), isTrue);
      expect(istFeiertag(DateTime(2026, 1, 6), bundesland: 'SH'), isFalse);
    });

    test('Fronleichnam in BY, nicht in SH', () {
      expect(istFeiertag(DateTime(2026, 6, 4), bundesland: 'BY'), isTrue);
      expect(istFeiertag(DateTime(2026, 6, 4), bundesland: 'SH'), isFalse);
    });

    test('Reformationstag in SH erst ab 2018', () {
      expect(istFeiertag(DateTime(2017, 10, 31), bundesland: 'SH'), isFalse);
      expect(istFeiertag(DateTime(2018, 10, 31), bundesland: 'SH'), isTrue);
      // In ST war er immer Feiertag.
      expect(istFeiertag(DateTime(2017, 10, 31), bundesland: 'ST'), isTrue);
    });
  });
}
