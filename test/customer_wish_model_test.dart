import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/app_config.dart';
import 'package:worktime_app/models/customer_wish.dart';

void main() {
  // Tripwire: der öffentliche Schreibpfad pinnt die orgId in firestore.rules
  // (publicWishOrg() == 'main-org'). Der Client schreibt
  // AppConfig.defaultOrganizationId. Weicht der Default ab, ohne dass die Regel
  // nachgezogen wird, bricht /wunsch still (permission-denied). Dieser Test
  // schlägt dann fehl und erinnert an die Kopplung.
  test('Default-Org passt zum publicWishOrg-Pin in firestore.rules', () {
    expect(AppConfig.defaultOrganizationId, 'main-org');
  });

  group('CustomerWish Referenznummer', () {
    test('hat Format XXX-XXX ohne verwechselbare Zeichen', () {
      final code = CustomerWish.generateReferenceCode(Random(42));
      expect(code, matches(RegExp(r'^[A-Z2-9]{3}-[A-Z2-9]{3}$')));
      // Keine 0/O/1/I/L (Vorlese-/Verwechslungsgefahr).
      expect(code.contains(RegExp('[01OIL]')), isFalse);
    });

    test('ist deterministisch bei gleichem Seed', () {
      expect(
        CustomerWish.generateReferenceCode(Random(7)),
        CustomerWish.generateReferenceCode(Random(7)),
      );
    });
  });

  group('CustomerWish Enums', () {
    test('Kategorie fromValue fällt auf other zurück', () {
      expect(CustomerWishCategoryX.fromValue('magazine'),
          CustomerWishCategory.magazine);
      expect(CustomerWishCategoryX.fromValue('quatsch'),
          CustomerWishCategory.other);
      expect(CustomerWishCategoryX.fromValue(null), CustomerWishCategory.other);
    });

    test('Status fromValue fällt auf pending (neu) zurück', () {
      expect(CustomerWishStatusX.fromValue('erledigt'), CustomerWishStatus.done);
      expect(CustomerWishStatusX.fromValue(null), CustomerWishStatus.pending);
      expect(CustomerWishStatus.pending.value, 'neu');
    });
  });

  group('CustomerWish öffentlicher Submission-Payload', () {
    test('enthält exakt die in firestore.rules erlaubten Felder', () {
      const wish = CustomerWish(
        orgId: 'main-org',
        referenceCode: 'ABC-DEF',
        storeName: 'Tabak Börse',
        category: CustomerWishCategory.cigarettes,
        wishText: 'Stange Marlboro',
        quantity: 2,
        // Status absichtlich abweichend -> Payload muss trotzdem 'neu' sein.
        status: CustomerWishStatus.done,
        // Internes Feld: darf NIE in den öffentlichen Payload (Allowlist).
        contactId: 'kontakt-1',
      );

      final map = wish.toPublicSubmissionMap();

      expect(
        map.keys.toSet(),
        {
          'orgId',
          'referenceCode',
          'storeName',
          'category',
          'wishText',
          'quantity',
          'desiredDate',
          'customerName',
          'customerContact',
          'status',
          'source',
        },
      );
      // Tripwire: contactId (H-D2, internes Feld) darf NICHT im öffentlichen
      // Create-Payload landen — die `firestore.rules`-hasOnly-Allowlist kennt
      // es nicht, sonst bräche der anonyme /wunsch-Schreibpfad still.
      expect(map.containsKey('contactId'), isFalse);
      // Invarianten, die die Rule serverseitig erzwingt:
      expect(map['status'], 'neu');
      expect(map['source'], CustomerWish.publicWebSource);
      expect(map['category'], 'cigarettes');
      expect(map['quantity'], 2);
    });
  });

  group('CustomerWish Serialisierung (Zwei-Formate)', () {
    test('toMap/fromMap (snake_case) trippt rund', () {
      final wish = CustomerWish(
        id: 'w1',
        orgId: 'main-org',
        referenceCode: 'K7Q-9X2',
        storeName: 'Strichmännchen',
        category: CustomerWishCategory.magazine,
        wishText: 'Spiegel Ausgabe 26',
        quantity: 3,
        desiredDate: DateTime(2026, 7, 1, 12),
        customerName: 'Max Muster',
        customerContact: 'max@example.com',
        contactId: 'kontakt-7',
        status: CustomerWishStatus.seen,
        notes: 'liegt bereit',
      );

      final restored = CustomerWish.fromMap(wish.toMap());

      expect(restored.referenceCode, 'K7Q-9X2');
      expect(restored.storeName, 'Strichmännchen');
      expect(restored.category, CustomerWishCategory.magazine);
      expect(restored.wishText, 'Spiegel Ausgabe 26');
      expect(restored.quantity, 3);
      expect(restored.desiredDate, DateTime(2026, 7, 1, 12));
      expect(restored.customerName, 'Max Muster');
      expect(restored.customerContact, 'max@example.com');
      expect(restored.contactId, 'kontakt-7');
      expect(restored.status, CustomerWishStatus.seen);
      expect(restored.notes, 'liegt bereit');
    });

    test('toFirestoreMap/fromFirestore (camelCase) trippt contactId rund', () {
      const wish = CustomerWish(
        id: 'w1',
        orgId: 'main-org',
        referenceCode: 'K7Q-9X2',
        storeName: 'Strichmännchen',
        category: CustomerWishCategory.magazine,
        wishText: 'Spiegel Ausgabe 26',
        contactId: 'kontakt-7',
      );

      final restored =
          CustomerWish.fromFirestore('w1', wish.toFirestoreMap());

      expect(restored.contactId, 'kontakt-7');
    });

    test('clearContactId löst die Verknüpfung in copyWith', () {
      const wish = CustomerWish(
        orgId: 'main-org',
        referenceCode: 'K7Q-9X2',
        storeName: 'Strichmännchen',
        category: CustomerWishCategory.magazine,
        wishText: 'Spiegel Ausgabe 26',
        contactId: 'kontakt-7',
      );

      expect(wish.copyWith(contactId: 'kontakt-9').contactId, 'kontakt-9');
      expect(wish.copyWith(clearContactId: true).contactId, isNull);
      // Ohne Argument bleibt der bestehende Wert erhalten.
      expect(wish.copyWith().contactId, 'kontakt-7');
    });
  });
}
