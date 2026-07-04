import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/third_party_cash.dart';

/// DH-M0: Roundtrip-Tests für die Fremdgeld-Modelle. Prüft beide
/// Serialisierungen (camelCase Firestore / snake_case lokal), Toleranz beim
/// Parsen und die copyWith-`clearX`-Semantik.
void main() {
  group('ThirdPartyCashType', () {
    const type = ThirdPartyCashType(
      id: 'lotto',
      name: 'Lotto',
      enabled: true,
      required: true,
      hint: 'Lottokasse separat zählen',
      sortOrder: 3,
    );

    test('Firestore-Roundtrip (camelCase) erhält alle Felder', () {
      final back = ThirdPartyCashType.fromFirestore(type.toFirestoreMap());
      expect(back.id, 'lotto');
      expect(back.name, 'Lotto');
      expect(back.enabled, isTrue);
      expect(back.required, isTrue);
      expect(back.hint, 'Lottokasse separat zählen');
      expect(back.sortOrder, 3);
    });

    test('lokaler Roundtrip (snake_case) erhält alle Felder', () {
      final map = type.toMap();
      expect(map['sort_order'], 3);
      final back = ThirdPartyCashType.fromMap(map);
      expect(back.id, 'lotto');
      expect(back.required, isTrue);
      expect(back.sortOrder, 3);
    });

    test('Defaults bei fehlenden Feldern (tolerant)', () {
      final back = ThirdPartyCashType.fromFirestore({'id': 'post', 'name': 'Post'});
      expect(back.enabled, isTrue);
      expect(back.required, isFalse);
      expect(back.hint, isNull);
      expect(back.sortOrder, 0);
    });

    test('parst String-/num-Werte tolerant', () {
      final back = ThirdPartyCashType.fromFirestore({
        'id': 'kvg',
        'name': 'KVG',
        'enabled': 'false',
        'required': 'true',
        'sortOrder': '7',
      });
      expect(back.enabled, isFalse);
      expect(back.required, isTrue);
      expect(back.sortOrder, 7);
    });

    test('copyWith(clearHint) leert den Hinweis', () {
      final cleared = type.copyWith(clearHint: true);
      expect(cleared.hint, isNull);
      expect(cleared.name, 'Lotto');
    });
  });

  group('ThirdPartyAmount', () {
    const amount = ThirdPartyAmount(
      typeId: 'lotto',
      typeName: 'Lotto',
      amountCents: 4500,
      expectedCents: 4000,
      note: 'aus Terminal',
    );

    test('Firestore-Roundtrip (camelCase) erhält alle Felder', () {
      final back = ThirdPartyAmount.fromFirestore(amount.toFirestoreMap());
      expect(back.typeId, 'lotto');
      expect(back.typeName, 'Lotto');
      expect(back.amountCents, 4500);
      expect(back.expectedCents, 4000);
      expect(back.note, 'aus Terminal');
    });

    test('lokaler Roundtrip (snake_case) erhält alle Felder', () {
      final map = amount.toMap();
      expect(map['amount_cents'], 4500);
      expect(map['expected_cents'], 4000);
      final back = ThirdPartyAmount.fromMap(map);
      expect(back.typeId, 'lotto');
      expect(back.amountCents, 4500);
      expect(back.expectedCents, 4000);
    });

    test('reine Ist-Erfassung (expectedCents null) round-trippt', () {
      const ist = ThirdPartyAmount(typeId: 'post', typeName: 'Post', amountCents: 1200);
      final back = ThirdPartyAmount.fromFirestore(ist.toFirestoreMap());
      expect(back.expectedCents, isNull);
      expect(back.amountCents, 1200);
    });

    test('default amountCents = 0 bei fehlendem Betrag', () {
      final back = ThirdPartyAmount.fromFirestore({'typeId': 'x', 'typeName': 'X'});
      expect(back.amountCents, 0);
    });

    test('copyWith(clearExpectedCents/clearNote) leert die Felder', () {
      final cleared = amount.copyWith(clearExpectedCents: true, clearNote: true);
      expect(cleared.expectedCents, isNull);
      expect(cleared.note, isNull);
      expect(cleared.amountCents, 4500);
    });
  });
}
