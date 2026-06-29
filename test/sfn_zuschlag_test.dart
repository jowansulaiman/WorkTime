import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/sfn_zuschlag.dart';

void main() {
  group('SfnZuschlagsart Sätze (§3b EStG)', () {
    test('Basispunkte/Prozente entsprechen den gesetzlichen Höchstsätzen', () {
      expect(SfnZuschlagsart.nacht.basispunkte, 2500);
      expect(SfnZuschlagsart.nachtTief.basispunkte, 4000);
      expect(SfnZuschlagsart.sonntag.basispunkte, 5000);
      expect(SfnZuschlagsart.feiertag.basispunkte, 12500);
      expect(SfnZuschlagsart.feiertagHoch.basispunkte, 15000);

      expect(SfnZuschlagsart.nacht.prozent, 0.25);
      expect(SfnZuschlagsart.sonntag.prozent, 0.50);
      expect(SfnZuschlagsart.feiertagHoch.prozent, 1.50);
    });
  });

  group('computeSfn3bAnteil – Grundlohn-Caps (50 € / 25 €)', () {
    test('unter beiden Grenzen: alles steuer- UND SV-frei', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 2000, // 20 €/h
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 500); // 25 % × 20 € × 1 h
      expect(a.steuerfreiCents, 500);
      expect(a.svFreiCents, 500);
      expect(a.steuerpflichtigCents, 0);
      expect(a.svPflichtigCents, 0);
    });

    test('zwischen 25 € und 50 €: voll steuerfrei, teils SV-pflichtig', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 3000, // 30 €/h
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 750);
      expect(a.steuerfreiCents, 750); // 30 € ≤ 50 € → keine Steuerkappung
      expect(a.svFreiCents, 625); // SV nur bis 25 € → 25 % × 25 € = 6,25 €
      expect(a.steuerpflichtigCents, 0);
      expect(a.svPflichtigCents, 125);
    });

    test('über beiden Grenzen: Steuer- und SV-Anteil gedeckelt', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 6000, // 60 €/h
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 1500); // 25 % × 60 €
      expect(a.steuerfreiCents, 1250); // 25 % × 50 €
      expect(a.svFreiCents, 625); // 25 % × 25 €
      expect(a.steuerpflichtigCents, 250);
      expect(a.svPflichtigCents, 875);
    });
  });

  group('computeSfn3bAnteil – Sätze je Art', () {
    test('Sonntag 50 %, über SV-Grenze', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.sonntag,
        grundlohnCentsProStunde: 3000,
        dauer: const Duration(hours: 2),
      );
      expect(a.gesamtCents, 3000); // 50 % × 30 € × 2 h
      expect(a.steuerfreiCents, 3000);
      expect(a.svFreiCents, 2500); // 50 % × 25 € × 2 h
      expect(a.svPflichtigCents, 500);
    });

    test('Feiertag hoch 150 %, über beiden Grenzen', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.feiertagHoch,
        grundlohnCentsProStunde: 6000,
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 9000); // 150 % × 60 €
      expect(a.steuerfreiCents, 7500); // 150 % × 50 €
      expect(a.svFreiCents, 3750); // 150 % × 25 €
      expect(a.steuerpflichtigCents, 1500);
    });

    test('nachtTief 40 % auf Teilstunde', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nachtTief,
        grundlohnCentsProStunde: 2000,
        dauer: const Duration(minutes: 30),
      );
      expect(a.gesamtCents, 400); // 40 % × 20 € × 0,5 h
    });

    test('Feiertag 125 % (Satz fließt korrekt in den Betrag)', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.feiertag,
        grundlohnCentsProStunde: 2000,
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 2500); // 125 % × 20 €
      expect(a.steuerfreiCents, 2500);
      expect(a.svFreiCents, 2500);
    });
  });

  group('computeSfn3bAnteil – Grenzwerte der Caps (inklusiv)', () {
    test('Grundlohn exakt 25 €/h: noch voll SV-frei', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 2500, // == SV-Cap
        dauer: const Duration(hours: 1),
      );
      // min(2500, 2500) = 2500 → SV-frei deckt den ganzen Zuschlag.
      expect(a.gesamtCents, 625); // 25 % × 25 €
      expect(a.steuerfreiCents, 625);
      expect(a.svFreiCents, 625);
      expect(a.svPflichtigCents, 0);
    });

    test('Grundlohn exakt 50 €/h: noch voll steuerfrei, SV gedeckelt', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 5000, // == Steuer-Cap
        dauer: const Duration(hours: 1),
      );
      expect(a.gesamtCents, 1250); // 25 % × 50 €
      expect(a.steuerfreiCents, 1250); // min(5000,5000) → voll steuerfrei
      expect(a.steuerpflichtigCents, 0);
      expect(a.svFreiCents, 625); // SV weiter bei 25 € gedeckelt
      expect(a.svPflichtigCents, 625);
    });
  });

  group('computeSfn3bAnteil – Rundung & Invarianten', () {
    test('kaufmännische Rundung auf ganze Cent', () {
      final a = computeSfn3bAnteil(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 3333, // krummer Grundlohn
        dauer: const Duration(minutes: 90),
      );
      // 25 % × 33,33 € × 1,5 h = 12,49875 € → 12,50 €
      expect(a.gesamtCents, 1250);
      // SV: 25 % × 25 € × 1,5 h = 9,375 € → 9,38 €
      expect(a.svFreiCents, 938);
    });

    test('Invariante 0 ≤ svFrei ≤ steuerfrei ≤ gesamt', () {
      for (final art in SfnZuschlagsart.values) {
        for (final grundlohn in [1000, 2500, 4000, 5000, 9000]) {
          final a = computeSfn3bAnteil(
            art: art,
            grundlohnCentsProStunde: grundlohn,
            dauer: const Duration(hours: 1),
          );
          expect(a.svFreiCents, greaterThanOrEqualTo(0));
          expect(a.svFreiCents, lessThanOrEqualTo(a.steuerfreiCents));
          expect(a.steuerfreiCents, lessThanOrEqualTo(a.gesamtCents));
          expect(a.steuerpflichtigCents, greaterThanOrEqualTo(0));
          expect(a.svPflichtigCents, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('computeSfn3bAnteil – Guards', () {
    test('Null-/Negativ-Eingaben ergeben zero', () {
      expect(
        computeSfn3bAnteil(
          art: SfnZuschlagsart.nacht,
          grundlohnCentsProStunde: 2000,
          dauer: Duration.zero,
        ).isZero,
        isTrue,
      );
      expect(
        computeSfn3bAnteil(
          art: SfnZuschlagsart.nacht,
          grundlohnCentsProStunde: 0,
          dauer: const Duration(hours: 1),
        ).isZero,
        isTrue,
      );
      expect(
        computeSfn3bAnteil(
          art: SfnZuschlagsart.nacht,
          grundlohnCentsProStunde: -2000,
          dauer: const Duration(hours: 1),
        ).isZero,
        isTrue,
      );
    });
  });

  group('computeSfn3bGesamt – Lage-Summe', () {
    test('Nacht + Sonntag kumulieren linear', () {
      final total = computeSfn3bGesamt(
        lage: const {
          SfnZuschlagsart.nacht: Duration(hours: 1),
          SfnZuschlagsart.sonntag: Duration(hours: 1),
        },
        grundlohnCentsProStunde: 2000,
      );
      // Nacht 25 % × 20 € = 5 €, Sonntag 50 % × 20 € = 10 € → 15 €.
      expect(total.gesamtCents, 1500);
      expect(total.steuerfreiCents, 1500);
      expect(total.svFreiCents, 1500);
    });

    test('über den Caps: Anteile summieren je Art GEKAPPT (≠ gesamt)', () {
      final total = computeSfn3bGesamt(
        lage: const {
          SfnZuschlagsart.nacht: Duration(hours: 1),
          SfnZuschlagsart.feiertagHoch: Duration(hours: 1),
        },
        grundlohnCentsProStunde: 6000, // 60 €/h, über beiden Grenzen
      );
      // Nacht: gesamt 1500 / steuerfrei 1250 / svFrei 625
      // FeiertagHoch: gesamt 9000 / steuerfrei 7500 / svFrei 3750
      expect(total.gesamtCents, 10500);
      expect(total.steuerfreiCents, 8750);
      expect(total.svFreiCents, 4375);
      // Summe der gekappten Anteile divergiert vom gezahlten Gesamtbetrag.
      expect(total.steuerfreiCents, lessThan(total.gesamtCents));
      expect(total.steuerpflichtigCents, 1750);
      expect(total.svPflichtigCents, 6125);
    });

    test('leere Lage ergibt zero', () {
      final total = computeSfn3bGesamt(
        lage: const {},
        grundlohnCentsProStunde: 2000,
      );
      expect(total.isZero, isTrue);
    });
  });
}
