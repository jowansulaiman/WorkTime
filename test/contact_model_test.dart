import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';

void main() {
  group('ContactType', () {
    test('value/fromValue round-trip für alle Werte', () {
      for (final type in ContactType.values) {
        expect(ContactTypeX.fromValue(type.value), type);
      }
    });

    test('unbekannter/null Wert fällt auf other', () {
      expect(ContactTypeX.fromValue('quatsch'), ContactType.other);
      expect(ContactTypeX.fromValue(null), ContactType.other);
    });

    test('jeder Wert hat ein nicht-leeres Label', () {
      for (final type in ContactType.values) {
        expect(type.label.trim(), isNotEmpty);
        expect(type.shortLabel.trim(), isNotEmpty);
      }
    });
  });

  group('Contact Serialisierung', () {
    const contact = Contact(
      id: 'c1',
      orgId: 'org-1',
      name: '  Nord-Tabak GmbH  ',
      type: ContactType.wholesaler,
      contactPerson: 'Frau Petersen',
      email: 'a@b.de',
      phone: '0431 1',
      mobile: '0170 2',
      website: 'https://x.de',
      street: 'Hauptstr. 1',
      postalCode: '24103',
      city: 'Kiel',
      taxId: 'DE123',
      customerNumber: 'K-9',
      notes: 'Notiz; mit Semikolon',
      siteId: 'site-1',
      siteName: 'Laden A',
      tags: ['Tabak', 'VIP'],
      isFavorite: true,
      isActive: false,
      createdByUid: 'u1',
    );

    test('toMap/fromMap round-trip erhält alle Felder', () {
      final restored = Contact.fromMap(contact.toMap());
      expect(restored.id, 'c1');
      expect(restored.name, '  Nord-Tabak GmbH  '); // toMap trimmt bewusst nicht
      expect(restored.type, ContactType.wholesaler);
      expect(restored.contactPerson, 'Frau Petersen');
      expect(restored.email, 'a@b.de');
      expect(restored.mobile, '0170 2');
      expect(restored.website, 'https://x.de');
      expect(restored.postalCode, '24103');
      expect(restored.taxId, 'DE123');
      expect(restored.customerNumber, 'K-9');
      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Laden A');
      expect(restored.tags, ['Tabak', 'VIP']);
      expect(restored.isFavorite, isTrue);
      expect(restored.isActive, isFalse);
    });

    test('toFirestoreMap nutzt camelCase, trimmt und ergänzt nameLower', () {
      final map = contact.toFirestoreMap();
      expect(map['name'], 'Nord-Tabak GmbH');
      expect(map['nameLower'], 'nord-tabak gmbh');
      expect(map['type'], 'wholesaler');
      expect(map['isFavorite'], true);
      expect(map['isActive'], false);
      expect(map['siteId'], 'site-1');
      expect(map.containsKey('updatedAt'), isTrue);
    });

    test('fromFirestore liest camelCase-Felder', () {
      final restored = Contact.fromFirestore('c9', const {
        'orgId': 'org-1',
        'name': 'Amt GmbH',
        'type': 'authority',
        'isFavorite': true,
        'isActive': true,
        'tags': ['a', 'b'],
      });
      expect(restored.id, 'c9');
      expect(restored.type, ContactType.authority);
      expect(restored.isFavorite, isTrue);
      expect(restored.tags, ['a', 'b']);
    });

    test('leere Strings werden in toFirestoreMap zu null', () {
      const sparse = Contact(orgId: 'o', name: 'X', email: '   ');
      expect(sparse.toFirestoreMap()['email'], isNull);
    });
  });

  group('copyWith clearX', () {
    const base = Contact(
      orgId: 'o',
      name: 'N',
      email: 'e@x.de',
      siteId: 's',
      siteName: 'S',
    );

    test('clearEmail entfernt die E-Mail', () {
      expect(base.copyWith(clearEmail: true).email, isNull);
    });

    test('clearSite entfernt siteId und siteName gemeinsam', () {
      final cleared = base.copyWith(clearSite: true);
      expect(cleared.siteId, isNull);
      expect(cleared.siteName, isNull);
    });

    test('ohne clear bleiben unveränderte Felder erhalten', () {
      expect(base.copyWith(name: 'Neu').email, 'e@x.de');
    });
  });

  group('Abgeleitete Felder', () {
    test('initials nutzt bis zu zwei Wörter', () {
      expect(const Contact(orgId: 'o', name: 'Nord Tabak').initials, 'NT');
      expect(const Contact(orgId: 'o', name: 'Einzel').initials, 'E');
    });

    test('displayAddress kombiniert Straße, PLZ und Ort', () {
      const contact = Contact(
        orgId: 'o',
        name: 'X',
        street: 'Hauptstr. 1',
        postalCode: '24103',
        city: 'Kiel',
      );
      expect(contact.displayAddress, 'Hauptstr. 1, 24103 Kiel');
    });

    test('primaryPhone bevorzugt Festnetz vor Mobil', () {
      expect(
        const Contact(orgId: 'o', name: 'X', phone: 'p', mobile: 'm')
            .primaryPhone,
        'p',
      );
      expect(
        const Contact(orgId: 'o', name: 'X', mobile: 'm').primaryPhone,
        'm',
      );
    });
  });
}
