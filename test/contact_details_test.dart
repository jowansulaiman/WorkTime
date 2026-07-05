import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_details.dart';

void main() {
  group('ContactAddress Zwei-Serialisierung', () {
    const address = ContactAddress(
      id: 'addr-1',
      type: AddressType.rechnung,
      label: 'Buchhaltung',
      street: 'Holtenauer Str.',
      houseNumber: '1a',
      zip: '24105',
      city: 'Kiel',
      country: 'Deutschland',
      addressExtra: 'Hinterhaus',
      postbox: '12 34',
      postboxZip: '24100',
    );

    void expectSame(ContactAddress a) {
      expect(a.id, 'addr-1');
      expect(a.type, AddressType.rechnung);
      expect(a.label, 'Buchhaltung');
      expect(a.street, 'Holtenauer Str.');
      expect(a.houseNumber, '1a');
      expect(a.zip, '24105');
      expect(a.city, 'Kiel');
      expect(a.country, 'Deutschland');
      expect(a.addressExtra, 'Hinterhaus');
      expect(a.postbox, '12 34');
      expect(a.postboxZip, '24100');
    }

    test('snake_case (local) round-trip', () {
      expectSame(ContactAddress.fromMap(address.toMap()));
    });
    test('camelCase (Firestore) round-trip', () {
      expectSame(ContactAddress.fromFirestoreMap(address.toFirestoreMap()));
    });
    test('country faellt auf Deutschland zurueck', () {
      final a = ContactAddress.fromMap({'id': 'x', 'country': ''});
      expect(a.country, 'Deutschland');
    });
  });

  group('CommunicationChannel Zwei-Serialisierung', () {
    const channel = CommunicationChannel(
      type: ChannelType.mobile,
      value: '0170 1234567',
      context: CommunicationContext.privat,
      label: 'Notfall',
      availability: 'Mo-Fr 9-17 Uhr',
      isPrimary: true,
    );

    void expectSame(CommunicationChannel c) {
      expect(c.type, ChannelType.mobile);
      expect(c.value, '0170 1234567');
      expect(c.context, CommunicationContext.privat);
      expect(c.label, 'Notfall');
      expect(c.availability, 'Mo-Fr 9-17 Uhr');
      expect(c.isPrimary, isTrue);
    }

    test('snake_case (local) round-trip', () {
      expectSame(CommunicationChannel.fromMap(channel.toMap()));
    });
    test('camelCase (Firestore) round-trip', () {
      expectSame(
          CommunicationChannel.fromFirestoreMap(channel.toFirestoreMap()));
    });
    test('copyWith setzt isPrimary + kann Label leeren', () {
      final c = channel.copyWith(isPrimary: false, clearLabel: true);
      expect(c.isPrimary, isFalse);
      expect(c.label, isNull);
      expect(c.value, '0170 1234567');
    });
  });

  group('ContactPerson Zwei-Serialisierung', () {
    const person = ContactPerson(
      id: 'rel-1',
      personContactId: 'kontakt-9',
      role: 'Geschäftsführer',
      isPrimary: true,
    );

    void expectSame(ContactPerson p) {
      expect(p.id, 'rel-1');
      expect(p.personContactId, 'kontakt-9');
      expect(p.role, 'Geschäftsführer');
      expect(p.isPrimary, isTrue);
    }

    test('snake_case (local) round-trip', () {
      expectSame(ContactPerson.fromMap(person.toMap()));
    });
    test('camelCase (Firestore) round-trip', () {
      expectSame(ContactPerson.fromFirestoreMap(person.toFirestoreMap()));
    });
  });

  group('BankAccount Zwei-Serialisierung', () {
    const bank = BankAccount(
      id: 'bank-1',
      iban: 'DE89370400440532013000',
      bic: 'COBADEFFXXX',
      bankName: 'Commerzbank',
      accountHolder: 'Strichmännchen GmbH',
      deactivated: true,
    );

    void expectSame(BankAccount b) {
      expect(b.id, 'bank-1');
      expect(b.iban, 'DE89370400440532013000');
      expect(b.bic, 'COBADEFFXXX');
      expect(b.bankName, 'Commerzbank');
      expect(b.accountHolder, 'Strichmännchen GmbH');
      expect(b.deactivated, isTrue);
    }

    test('snake_case (local) round-trip', () {
      expectSame(BankAccount.fromMap(bank.toMap()));
    });
    test('camelCase (Firestore) round-trip', () {
      expectSame(BankAccount.fromFirestoreMap(bank.toFirestoreMap()));
    });
  });

  group('Enum fromValue-Defaults (nie werfen)', () {
    test('unbekannte Werte fallen auf Default', () {
      expect(AddressTypeX.fromValue('quatsch'), AddressType.haupt);
      expect(ChannelTypeX.fromValue('quatsch'), ChannelType.email);
      expect(CommunicationContextX.fromValue('quatsch'),
          CommunicationContext.dienst);
      expect(AddressTypeX.fromValue(null), AddressType.haupt);
    });
  });

  group('Contact mit allen Sub-Listen round-trippt', () {
    const contact = Contact(
      id: 'c-1',
      orgId: 'org-1',
      name: 'Nord-Tabak GmbH',
      type: ContactType.wholesaler,
      addresses: [
        ContactAddress(
          id: 'a-1',
          type: AddressType.lieferung,
          street: 'Lagerweg 5',
          zip: '24106',
          city: 'Kiel',
        ),
      ],
      channels: [
        CommunicationChannel(
          type: ChannelType.email,
          value: 'info@nord-tabak.test',
          isPrimary: true,
        ),
        CommunicationChannel(
          type: ChannelType.phone,
          value: '0431 999',
          context: CommunicationContext.firma,
        ),
      ],
      contactPersons: [
        ContactPerson(id: 'p-1', personContactId: 'c-9', role: 'Einkauf'),
      ],
      bankAccounts: [
        BankAccount(id: 'b-1', iban: 'DE00', bankName: 'Sparkasse'),
      ],
    );

    void expectLists(Contact c) {
      expect(c.addresses, hasLength(1));
      expect(c.addresses.single.type, AddressType.lieferung);
      expect(c.addresses.single.city, 'Kiel');
      expect(c.channels, hasLength(2));
      expect(c.channels.first.type, ChannelType.email);
      expect(c.channels.first.isPrimary, isTrue);
      expect(c.channels[1].context, CommunicationContext.firma);
      expect(c.contactPersons, hasLength(1));
      expect(c.contactPersons.single.role, 'Einkauf');
      expect(c.bankAccounts, hasLength(1));
      expect(c.bankAccounts.single.bankName, 'Sparkasse');
    }

    test('snake_case (SharedPreferences) round-trip', () {
      expectLists(Contact.fromMap(contact.toMap()));
    });

    test('camelCase (Firestore) round-trip', () {
      // toFirestoreMap enthält keine id (Doc-ID) → separat übergeben.
      expectLists(Contact.fromFirestore('c-1', contact.toFirestoreMap()));
    });

    test('leere Listen sind der Default (rückwärtskompatibel)', () {
      const plain = Contact(orgId: 'org-1', name: 'Alt');
      final restored = Contact.fromMap(plain.toMap());
      expect(restored.addresses, isEmpty);
      expect(restored.channels, isEmpty);
      expect(restored.contactPersons, isEmpty);
      expect(restored.bankAccounts, isEmpty);
    });
  });

  group('Contact Person/Firma-Split + Status (M3) round-trippt', () {
    final person = Contact(
      id: 'p-1',
      orgId: 'org-1',
      name: 'Dr. Anna Meier',
      kind: ContactKind.person,
      status: ContactStatus.gesperrt,
      blacklisted: true,
      alias: 'Praxis Meier',
      firstName: 'Anna',
      lastName: 'Meier',
      title: 'Dr.',
      gender: Gender.weiblich,
      birthday: DateTime(1985, 3, 14),
      position: 'Inhaberin',
      department: 'Leitung',
      debitorNumber: 'D-100',
      creditorNumber: 'K-200',
      customerSince: DateTime(2020, 1, 1),
    );

    final company = Contact(
      id: 'f-1',
      orgId: 'org-1',
      name: 'Nord-Tabak GmbH',
      kind: ContactKind.company,
      companyName: 'Nord-Tabak GmbH',
      legalName: 'Nord-Tabak Handelsgesellschaft mbH',
      registrationNumber: 'HRB 12345',
      companyAnniversary: DateTime(1999, 6, 1),
      avatarUrl: 'https://example.test/logo.png',
    );

    void expectPerson(Contact c) {
      expect(c.kind, ContactKind.person);
      expect(c.status, ContactStatus.gesperrt);
      expect(c.blacklisted, isTrue);
      expect(c.alias, 'Praxis Meier');
      expect(c.firstName, 'Anna');
      expect(c.lastName, 'Meier');
      expect(c.title, 'Dr.');
      expect(c.gender, Gender.weiblich);
      expect(c.birthday, DateTime(1985, 3, 14));
      expect(c.position, 'Inhaberin');
      expect(c.department, 'Leitung');
      expect(c.debitorNumber, 'D-100');
      expect(c.creditorNumber, 'K-200');
      expect(c.customerSince, DateTime(2020, 1, 1));
    }

    void expectCompany(Contact c) {
      expect(c.kind, ContactKind.company);
      expect(c.companyName, 'Nord-Tabak GmbH');
      expect(c.legalName, 'Nord-Tabak Handelsgesellschaft mbH');
      expect(c.registrationNumber, 'HRB 12345');
      expect(c.companyAnniversary, DateTime(1999, 6, 1));
      expect(c.avatarUrl, 'https://example.test/logo.png');
    }

    test('Person snake_case round-trip', () {
      expectPerson(Contact.fromMap(person.toMap()));
    });
    test('Person camelCase round-trip', () {
      expectPerson(Contact.fromFirestore('p-1', person.toFirestoreMap()));
    });
    test('Firma snake_case round-trip', () {
      expectCompany(Contact.fromMap(company.toMap()));
    });
    test('Firma camelCase round-trip', () {
      expectCompany(Contact.fromFirestore('f-1', company.toFirestoreMap()));
    });

    test('displayName: alias → Firma → Person → name-Fallback', () {
      expect(person.displayName, 'Praxis Meier'); // alias hat Vorrang
      expect(company.displayName, 'Nord-Tabak GmbH'); // companyName
      const bare = Contact(
        orgId: 'org-1',
        name: 'Fallback',
        kind: ContactKind.person,
      );
      expect(bare.displayName, 'Fallback'); // kein first/last → name
    });

    test('Defaults rückwärtskompatibel (alte Kontakte)', () {
      const old = Contact(orgId: 'org-1', name: 'Alt');
      final r = Contact.fromMap(old.toMap());
      expect(r.kind, ContactKind.company);
      expect(r.status, ContactStatus.aktiv);
      expect(r.blacklisted, isFalse);
      expect(r.gender, Gender.unbekannt);
      expect(r.firstName, isNull);
    });

    test('copyWith clearX leert Person-Felder', () {
      final cleared = person.copyWith(
        clearFirstName: true,
        clearBirthday: true,
        clearAlias: true,
      );
      expect(cleared.firstName, isNull);
      expect(cleared.birthday, isNull);
      expect(cleared.alias, isNull);
      expect(cleared.lastName, 'Meier'); // unberührt
    });
  });

  group('Contact-Enum fromValue-Defaults', () {
    test('unbekannte Werte fallen auf Default', () {
      expect(ContactKindX.fromValue('quatsch'), ContactKind.company);
      expect(ContactStatusX.fromValue('quatsch'), ContactStatus.aktiv);
      expect(GenderX.fromValue('quatsch'), Gender.unbekannt);
    });
  });
}
