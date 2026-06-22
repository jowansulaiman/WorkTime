import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/core/money.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  group('Money', () {
    test('format de_DE', () {
      expect(const Money(1234).format(), contains('12,34'));
      expect(const Money(1234).format(), contains('€'));
      expect(Money.formatCents(null), '–');
    });

    test('Arithmetik bleibt in Cent (kein Float-Drift)', () {
      var sum = Money.zero;
      for (var i = 0; i < 10; i++) {
        sum = sum + const Money(10); // 10 × 0,10 €
      }
      expect(sum.cents, 100);
      expect((const Money(500) - const Money(150)).cents, 350);
      expect((const Money(99) * 3).cents, 297);
    });

    test('parseCents: Komma als Dezimaltrenner (de_DE)', () {
      expect(Money.parseCents('12,34'), 1234);
      expect(Money.parseCents('1.234,56'), 123456);
      expect(Money.parseCents('12,34 €'), 1234);
      expect(Money.parseCents('1,99'), 199);
    });

    test('parseCents: Punkt als Dezimaltrenner (1–2 Nachkommastellen)', () {
      // Footgun-Fix: Punkt darf NICHT als Tausender verschluckt werden, sonst
      // wird "1.99" zu 199,00 € (100×-Fehler). Siehe probleme/01-kritisch-hoch.
      expect(Money.parseCents('1.99'), 199);
      expect(Money.parseCents('12.34'), 1234);
      expect(Money.parseCents('0.99'), 99);
      expect(Money.parseCents('12.5'), 1250);
    });

    test('parseCents: Punkt mit 3 Nachkommastellen bleibt Tausender', () {
      // „1.234" sind weiterhin 1234 € (konsistent mit der App).
      expect(Money.parseCents('1.234'), 123400);
      expect(Money.parseCents('1.234.567'), 123456700);
    });

    test('parseCents: gemischte Trenner, letzter zählt als Dezimal', () {
      expect(Money.parseCents('1.234,56'), 123456); // de
      expect(Money.parseCents('1,234.56'), 123456); // en
    });

    test('parseCents: leer/ungültig -> null', () {
      expect(Money.parseCents(''), isNull);
      expect(Money.parseCents('abc'), isNull);
    });

    test('fromEuros rundet kaufmännisch', () {
      expect(Money.fromEuros(12.345).cents, 1235);
      expect(Money.fromEuros(12.344).cents, 1234);
    });

    test('Gleichheit + Vergleich', () {
      expect(const Money(100) == const Money(100), isTrue);
      expect(const Money(100).compareTo(const Money(200)), lessThan(0));
    });
  });
}
