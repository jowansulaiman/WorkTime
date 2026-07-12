import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/ean.dart';
import 'package:worktime_app/core/gs1.dart';

/// Neue Barcode-Toleranzen (UPC-E, GTIN-14) und die fachliche GS1-Auswertung.
/// Bestands-Basics (EAN-Pruefziffer, Leading-Zero) deckt scanner_foundation_test.
void main() {
  const gs = '\u001D'; // FNC1/Group-Separator, wie ihn Scanner liefern

  group('upcEToUpcA', () {
    test('expandiert die Kompressions-Muster korrekt', () {
      // Muster d6 = 0-2: Hersteller d1 d2 d6 00, Artikel 00 d3 d4 d5.
      expect(upcEToUpcA('01201303'), '012000000133');
      // Muster d6 = 1 (ebenfalls 0-2), bekanntes Beispiel.
      expect(upcEToUpcA('01245714'), '012100004574');
      // Muster d6 = 4: Hersteller d1..d4 0, Artikel 0000 d5.
      expect(upcEToUpcA('01234145'), '012340000015');
      // Muster d6 = 5-9: Hersteller d1..d5, Artikel 0000 d6.
      expect(upcEToUpcA('01245752'), '012457000052');
    });

    test('liefert null bei falscher Pruefziffer/Nummernsystem/Laenge', () {
      expect(upcEToUpcA('01201304'), isNull); // Pruefziffer falsch
      expect(upcEToUpcA('91245714'), isNull); // Nummernsystem 9
      expect(upcEToUpcA('0124571'), isNull); // 7 Stellen
      expect(upcEToUpcA('abcdefgh'), isNull);
    });
  });

  group('gtin14ToGtin13', () {
    test('liefert die enthaltene GTIN-13 mit NEU berechneter Pruefziffer', () {
      // GTIN-13 4011200296908 als GTIN-14 mit Indikator 0.
      expect(gtin14ToGtin13('04011200296908'), '4011200296908');
    });

    test('Indikator > 0 aendert die Pruefziffer (kein blindes Abschneiden)', () {
      // 4006381333931 (gueltige EAN-13) als Karton-GTIN-14 mit Indikator 1.
      expect(gtin14ToGtin13('14006381333938'), '4006381333931');
    });

    test('lehnt ungueltige Eingaben ab', () {
      expect(gtin14ToGtin13('04011200296901'), isNull); // Pruefziffer falsch
      expect(gtin14ToGtin13('4011200296908'), isNull); // nur 13 Stellen
    });
  });

  group('isPlausibleRetailCode', () {
    test('akzeptiert gueltige EAN/UPC-A, UPC-E und GTIN-14', () {
      expect(isPlausibleRetailCode('4006381333931'), isTrue); // EAN-13
      expect(isPlausibleRetailCode('96385074'), isTrue); // EAN-8
      expect(isPlausibleRetailCode('01201303'), isTrue); // UPC-E (keine EAN-8)
      expect(isPlausibleRetailCode('04011200296908'), isTrue); // GTIN-14
    });

    test('lehnt Standard-Laengen mit kaputter Pruefziffer ab', () {
      expect(isPlausibleRetailCode('4006381333930'), isFalse);
      // Weder gueltige EAN-8 noch UPC-E (Nummernsystem 9).
      expect(isPlausibleRetailCode('91245714'), isFalse);
      expect(isPlausibleRetailCode('04011200296901'), isFalse); // GTIN-14
    });

    test('laesst Hauscodes anderer Laenge passieren', () {
      expect(isPlausibleRetailCode('12345'), isTrue);
      expect(isPlausibleRetailCode('ABC-123'), isTrue);
    });
  });

  group('gtinLookupVariants (UPC-E/GTIN-14)', () {
    test('UPC-E liefert UPC-A- und EAN-13-Variante', () {
      expect(
        gtinLookupVariants('01201303'),
        {'01201303', '012000000133', '0012000000133'},
      );
    });

    test('GTIN-14 liefert die enthaltene GTIN-13 samt deren Varianten', () {
      expect(
        gtinLookupVariants('04011200296908'),
        {'04011200296908', '4011200296908'},
      );
      // Enthaltene GTIN-13 beginnt mit 0 -> zusaetzlich UPC-A-Form.
      expect(
        gtinLookupVariants('00123456789128'),
        {'00123456789128', '0123456789128', '123456789128'},
      );
    });

    test('gueltige EAN-8 ohne UPC-E-Deutung bleibt unangetastet', () {
      expect(gtinLookupVariants('96385074'), {'96385074'});
    });
  });

  group('canonicalGtin', () {
    test('vereinheitlicht Schreibweisen auf die EAN-13-Form', () {
      expect(canonicalGtin('036000291452'), '0036000291452'); // UPC-A -> 0+12
      expect(canonicalGtin('0036000291452'), '0036000291452'); // schon EAN-13
      expect(canonicalGtin('04011200296908'), '4011200296908'); // GTIN-14
      expect(canonicalGtin('01201303'), '0012000000133'); // reiner UPC-E
    });

    test('EAN-8 und Hauscodes bleiben sie selbst', () {
      expect(canonicalGtin('96385074'), '96385074');
      expect(canonicalGtin('HAUS-42'), 'HAUS-42');
    });
  });

  group('parseGs1', () {
    test('Element-String: GTIN + MHD + Charge (Fix-Felder ohne Trenner)', () {
      final data = parseGs1('01040112002969081726123110BATCH-7');
      expect(data, isNotNull);
      expect(data!.gtin, '04011200296908');
      expect(data.expiryDate, DateTime(2026, 12, 31, 12));
      expect(data.lot, 'BATCH-7');
    });

    test('variables Feld vor Fix-Feld wird per GS-Trenner beendet', () {
      final data = parseGs1('10CHARGE-1${gs}0104011200296908');
      expect(data, isNotNull);
      expect(data!.lot, 'CHARGE-1');
      expect(data.gtin, '04011200296908');
    });

    test('Symbology-Prefix ]C1 wird abgestreift', () {
      final data = parseGs1(']C10104011200296908');
      expect(data, isNotNull);
      expect(data!.gtin, '04011200296908');
    });

    test('Klammer-Notation', () {
      final data = parseGs1('(01)04011200296908(17)260731(10)L42');
      expect(data, isNotNull);
      expect(data!.gtin, '04011200296908');
      expect(data.expiryDate, DateTime(2026, 7, 31, 12));
      expect(data.lot, 'L42');
      expect(data.elements['17'], '260731');
    });

    test('GS1 Digital Link (Pfad-AIs + Query-AIs)', () {
      final data = parseGs1(
        'https://id.gs1.org/01/04011200296908/10/CHARGE7?17=261231',
      );
      expect(data, isNotNull);
      expect(data!.gtin, '04011200296908');
      expect(data.lot, 'CHARGE7');
      expect(data.expiryDate, DateTime(2026, 12, 31, 12));
    });

    test('nackte GTIN im QR wird als AI 01 gedeutet', () {
      final data = parseGs1('4011200296908');
      expect(data, isNotNull);
      expect(data!.gtin, '4011200296908');
      expect(data.expiryDate, isNull);
    });

    test('MHD-Tag 00 bedeutet Monatsende', () {
      final data = parseGs1('(01)04011200296908(17)260200');
      expect(data!.expiryDate, DateTime(2026, 2, 28, 12));
    });

    test('Menge aus AI 30', () {
      final data = parseGs1('(01)04011200296908(30)12');
      expect(data!.quantity, 12);
    });

    test('gewoehnliche URL ohne GS1-Pfad ist kein GS1', () {
      expect(parseGs1('https://example.com/aktion'), isNull);
      expect(parseGs1(''), isNull);
    });

    test('unbekannter AI beendet den Parse tolerant', () {
      final data = parseGs1('0104011200296908XX99');
      expect(data, isNotNull);
      expect(data!.gtin, '04011200296908');
    });

    test('rein numerische Hauscodes werden NICHT als GS1 gedeutet', () {
      // 7-stelliger Hauscode, beginnt zufaellig mit "01": AI-01-Feld waere
      // abgeschnitten -> kein Phantom-GTIN "23456".
      expect(parseGs1('0123456'), isNull);
      // 10-stellig, beginnt mit "17": Rest "78" ist kein AI -> nicht
      // vollstaendig konsumiert -> kein GS1 (kein Phantom-MHD).
      expect(parseGs1('1712345678'), isNull);
      // Vollstaendig konsumierbarer numerischer Element-String bleibt GS1.
      expect(parseGs1('0104011200296908')!.gtin, '04011200296908');
    });
  });
}
