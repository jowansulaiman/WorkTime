import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/de_number_input.dart';

void main() {
  group('rateToPercentInput / percentInputToRate', () {
    test('seeded Sätze runden verlustfrei round-trip', () {
      // Genau die im Lohn-Einstellungen-Editor vorbelegten Werte.
      for (final fraction in [0.0006, 0.0015, 0.0024, 0.011, 0.013, 0.0138,
        0.025, 0.036, 0.146, 0.186, 0.026]) {
        final text = rateToPercentInput(fraction);
        final back = percentInputToRate(text);
        expect(back, isNotNull, reason: 'parse $text');
        expect(back!, closeTo(fraction, 1e-12), reason: '$fraction -> $text');
      }
    });

    test('Anzeige nutzt deutsches Komma ohne Float-Rauschen', () {
      expect(rateToPercentInput(0.146), '14,6');
      expect(rateToPercentInput(0.011), '1,1');
      expect(rateToPercentInput(0.0006), '0,06');
      expect(rateToPercentInput(0.0024), '0,24');
      expect(rateToPercentInput(0.0138), '1,38');
      expect(rateToPercentInput(0.0), '0');
    });

    test('percentInputToRate akzeptiert Komma, %, Leerraum', () {
      expect(percentInputToRate('1,1'), closeTo(0.011, 1e-12));
      expect(percentInputToRate(' 14,6 % '), closeTo(0.146, 1e-12));
      expect(percentInputToRate('2.5'), closeTo(0.025, 1e-12));
    });

    test('percentInputToRate gibt null bei leer/ungültig', () {
      expect(percentInputToRate(''), isNull);
      expect(percentInputToRate('   '), isNull);
      expect(percentInputToRate(','), isNull);
      expect(percentInputToRate('.'), isNull);
      expect(percentInputToRate('%'), isNull);
      expect(percentInputToRate('abc'), isNull);
    });
  });

  group('centsToInput', () {
    test('formatiert Cent mit zwei Nachkommastellen + Komma', () {
      expect(centsToInput(139000), '1390,00');
      expect(centsToInput(60300), '603,00');
      expect(centsToInput(1390), '13,90');
      expect(centsToInput(0), '0,00');
    });
  });
}
