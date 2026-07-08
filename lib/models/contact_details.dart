import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Sub-Objekte eines [Contact] für die AllTec-1:1-Parität: mehrere Adressen,
/// typisierte Kommunikationskanäle, Ansprechpartner-Verknüpfungen und
/// Bankverbindungen. Alle sind — wie `ContactActivity` — **eingebettet** als
/// Arrays direkt im Contact-Dokument (keine Sub-Collections; Spark-frugal) und
/// tragen die WorkTime-Zwei-Serialisierung: `toFirestoreMap`/`fromFirestoreMap`
/// (camelCase) und `toMap`/`fromMap` (snake_case).

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

/// Kontakt ist eine natürliche Person oder eine Firma/Organisation. Steuert,
/// welche Stammdaten-Felder greifen (Vor-/Nachname vs. Firmenname). Ergänzt die
/// bestehende [ContactType]-Kategorie (Kunde/Lieferant/…), ersetzt sie nicht.
enum ContactKind { person, company }

extension ContactKindX on ContactKind {
  String get value => switch (this) {
        ContactKind.person => 'person',
        ContactKind.company => 'company',
      };

  String get label => switch (this) {
        ContactKind.person => 'Person',
        ContactKind.company => 'Firma',
      };

  static ContactKind fromValue(String? value) => switch (value) {
        'person' => ContactKind.person,
        _ => ContactKind.company,
      };
}

/// Status eines Kontakts (aktiv/inaktiv/gesperrt).
enum ContactStatus { aktiv, inaktiv, gesperrt }

extension ContactStatusX on ContactStatus {
  String get value => switch (this) {
        ContactStatus.aktiv => 'aktiv',
        ContactStatus.inaktiv => 'inaktiv',
        ContactStatus.gesperrt => 'gesperrt',
      };

  String get label => switch (this) {
        ContactStatus.aktiv => 'Aktiv',
        ContactStatus.inaktiv => 'Inaktiv',
        ContactStatus.gesperrt => 'Gesperrt',
      };

  static ContactStatus fromValue(String? value) => switch (value) {
        'inaktiv' => ContactStatus.inaktiv,
        'gesperrt' => ContactStatus.gesperrt,
        _ => ContactStatus.aktiv,
      };
}

/// Geschlecht/Anrede einer Kontaktperson.
enum Gender { maennlich, weiblich, divers, unbekannt }

extension GenderX on Gender {
  String get value => switch (this) {
        Gender.maennlich => 'maennlich',
        Gender.weiblich => 'weiblich',
        Gender.divers => 'divers',
        Gender.unbekannt => 'unbekannt',
      };

  String get label => switch (this) {
        Gender.maennlich => 'Männlich',
        Gender.weiblich => 'Weiblich',
        Gender.divers => 'Divers',
        Gender.unbekannt => 'Unbekannt',
      };

  /// Anrede-Kurzform für Formulare (Herr/Frau/Divers/—).
  String get salutation => switch (this) {
        Gender.maennlich => 'Herr',
        Gender.weiblich => 'Frau',
        Gender.divers => 'Divers',
        Gender.unbekannt => '—',
      };

  static Gender fromValue(String? value) => switch (value) {
        'maennlich' => Gender.maennlich,
        'weiblich' => Gender.weiblich,
        'divers' => Gender.divers,
        _ => Gender.unbekannt,
      };
}

/// Art einer Adresse. Der gespeicherte [value] (snake_case) ist stabil.
enum AddressType { haupt, rechnung, lieferung, niederlassung }

extension AddressTypeX on AddressType {
  String get value => switch (this) {
        AddressType.haupt => 'haupt',
        AddressType.rechnung => 'rechnung',
        AddressType.lieferung => 'lieferung',
        AddressType.niederlassung => 'niederlassung',
      };

  String get label => switch (this) {
        AddressType.haupt => 'Hauptadresse',
        AddressType.rechnung => 'Rechnungsadresse',
        AddressType.lieferung => 'Lieferadresse',
        AddressType.niederlassung => 'Niederlassung',
      };

  static AddressType fromValue(String? value) => switch (value) {
        'rechnung' => AddressType.rechnung,
        'lieferung' => AddressType.lieferung,
        'niederlassung' => AddressType.niederlassung,
        _ => AddressType.haupt,
      };
}

/// Art eines Kommunikationskanals.
enum ChannelType { email, phone, mobile, fax, website }

extension ChannelTypeX on ChannelType {
  String get value => switch (this) {
        ChannelType.email => 'email',
        ChannelType.phone => 'phone',
        ChannelType.mobile => 'mobile',
        ChannelType.fax => 'fax',
        ChannelType.website => 'website',
      };

  String get label => switch (this) {
        ChannelType.email => 'E-Mail',
        ChannelType.phone => 'Telefon',
        ChannelType.mobile => 'Mobil',
        ChannelType.fax => 'Fax',
        ChannelType.website => 'Website',
      };

  static ChannelType fromValue(String? value) => switch (value) {
        'phone' => ChannelType.phone,
        'mobile' => ChannelType.mobile,
        'fax' => ChannelType.fax,
        'website' => ChannelType.website,
        _ => ChannelType.email,
      };
}

/// Art einer DSGVO-Einwilligung.
enum ConsentType { dataProcessing, emailContact, phoneContact, dataSharing }

extension ConsentTypeX on ConsentType {
  String get value => switch (this) {
        ConsentType.dataProcessing => 'data_processing',
        ConsentType.emailContact => 'email_contact',
        ConsentType.phoneContact => 'phone_contact',
        ConsentType.dataSharing => 'data_sharing',
      };

  String get label => switch (this) {
        ConsentType.dataProcessing => 'Datenverarbeitung',
        ConsentType.emailContact => 'E-Mail-Kontakt',
        ConsentType.phoneContact => 'Telefon-Kontakt',
        ConsentType.dataSharing => 'Datenweitergabe',
      };

  static ConsentType fromValue(String? value) => switch (value) {
        'email_contact' => ConsentType.emailContact,
        'phone_contact' => ConsentType.phoneContact,
        'data_sharing' => ConsentType.dataSharing,
        _ => ConsentType.dataProcessing,
      };
}

/// Kontext eines Kommunikationskanals (dienstlich/privat/firmenweit).
enum CommunicationContext { dienst, privat, firma }

extension CommunicationContextX on CommunicationContext {
  String get value => switch (this) {
        CommunicationContext.dienst => 'dienst',
        CommunicationContext.privat => 'privat',
        CommunicationContext.firma => 'firma',
      };

  String get label => switch (this) {
        CommunicationContext.dienst => 'Dienstlich',
        CommunicationContext.privat => 'Privat',
        CommunicationContext.firma => 'Firma',
      };

  static CommunicationContext fromValue(String? value) => switch (value) {
        'privat' => CommunicationContext.privat,
        'firma' => CommunicationContext.firma,
        _ => CommunicationContext.dienst,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-Modelle
// ─────────────────────────────────────────────────────────────────────────────

/// Eine (Zusatz-)Adresse eines Kontakts (Rechnung/Lieferung/Niederlassung …).
/// Die flache Hauptadresse bleibt weiterhin direkt am [Contact]; diese Liste
/// hält die **weiteren** Adressen.
class ContactAddress {
  const ContactAddress({
    required this.id,
    this.type = AddressType.haupt,
    this.label,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
    this.country = 'Deutschland',
    this.addressExtra,
    this.postbox,
    this.postboxZip,
  });

  final String id;
  final AddressType type;
  final String? label;
  final String? street;
  final String? houseNumber;
  final String? zip;
  final String? city;
  final String country;
  final String? addressExtra;
  final String? postbox;
  final String? postboxZip;

  factory ContactAddress.fromMap(Map<String, dynamic> map) {
    return ContactAddress(
      id: (map['id'] ?? '').toString(),
      type: AddressTypeX.fromValue(map['type']?.toString()),
      label: map['label'] as String?,
      street: map['street'] as String?,
      houseNumber: map['house_number'] as String?,
      zip: map['zip'] as String?,
      city: map['city'] as String?,
      country: (map['country'] as String?)?.trim().isNotEmpty == true
          ? map['country'] as String
          : 'Deutschland',
      addressExtra: map['address_extra'] as String?,
      postbox: map['postbox'] as String?,
      postboxZip: map['postbox_zip'] as String?,
    );
  }

  factory ContactAddress.fromFirestoreMap(Map<String, dynamic> map) {
    return ContactAddress(
      id: (map['id'] ?? '').toString(),
      type: AddressTypeX.fromValue(map['type']?.toString()),
      label: map['label'] as String?,
      street: map['street'] as String?,
      houseNumber: map['houseNumber'] as String?,
      zip: map['zip'] as String?,
      city: map['city'] as String?,
      country: (map['country'] as String?)?.trim().isNotEmpty == true
          ? map['country'] as String
          : 'Deutschland',
      addressExtra: map['addressExtra'] as String?,
      postbox: map['postbox'] as String?,
      postboxZip: map['postboxZip'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'label': label,
      'street': street,
      'house_number': houseNumber,
      'zip': zip,
      'city': city,
      'country': country,
      'address_extra': addressExtra,
      'postbox': postbox,
      'postbox_zip': postboxZip,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'type': type.value,
      'label': label,
      'street': street,
      'houseNumber': houseNumber,
      'zip': zip,
      'city': city,
      'country': country,
      'addressExtra': addressExtra,
      'postbox': postbox,
      'postboxZip': postboxZip,
    };
  }

  /// Einzeilige Anschrift für Anzeige/Export.
  String get displayLine {
    final streetPart =
        [street?.trim() ?? '', houseNumber?.trim() ?? ''].where((v) => v.isNotEmpty).join(' ');
    final cityPart =
        [zip?.trim() ?? '', city?.trim() ?? ''].where((v) => v.isNotEmpty).join(' ');
    return [streetPart, cityPart].where((v) => v.isNotEmpty).join(', ');
  }
}

/// Ein typisierter Kommunikationskanal (E-Mail/Telefon/Mobil/Fax/Website) mit
/// Kontext (dienstlich/privat/firma), optionalem Label und Erreichbarkeit.
class CommunicationChannel {
  const CommunicationChannel({
    required this.type,
    required this.value,
    this.context = CommunicationContext.dienst,
    this.label,
    this.availability,
    this.isPrimary = false,
  });

  final ChannelType type;
  final String value;
  final CommunicationContext context;
  final String? label;
  final String? availability;
  final bool isPrimary;

  CommunicationChannel copyWith({
    ChannelType? type,
    String? value,
    CommunicationContext? context,
    String? label,
    String? availability,
    bool? isPrimary,
    bool clearLabel = false,
    bool clearAvailability = false,
  }) {
    return CommunicationChannel(
      type: type ?? this.type,
      value: value ?? this.value,
      context: context ?? this.context,
      label: clearLabel ? null : (label ?? this.label),
      availability: clearAvailability ? null : (availability ?? this.availability),
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  factory CommunicationChannel.fromMap(Map<String, dynamic> map) {
    return CommunicationChannel(
      type: ChannelTypeX.fromValue(map['type']?.toString()),
      value: (map['value'] ?? '').toString(),
      context: CommunicationContextX.fromValue(map['context']?.toString()),
      label: map['label'] as String?,
      availability: map['availability'] as String?,
      isPrimary: parse.toBool(map['is_primary']) ?? false,
    );
  }

  factory CommunicationChannel.fromFirestoreMap(Map<String, dynamic> map) {
    return CommunicationChannel(
      type: ChannelTypeX.fromValue(map['type']?.toString()),
      value: (map['value'] ?? '').toString(),
      context: CommunicationContextX.fromValue(map['context']?.toString()),
      label: map['label'] as String?,
      availability: map['availability'] as String?,
      isPrimary: parse.toBool(map['isPrimary']) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.value,
      'value': value,
      'context': context.value,
      'label': label,
      'availability': availability,
      'is_primary': isPrimary,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'type': type.value,
      'value': value,
      'context': context.value,
      'label': label,
      'availability': availability,
      'isPrimary': isPrimary,
    };
  }
}

/// Eine Ansprechpartner-Verknüpfung: **Referenz** ([personContactId]) auf einen
/// anderen (Personen-)Kontakt, mit Rolle und Haupt-Ansprechpartner-Flag.
class ContactPerson {
  const ContactPerson({
    required this.id,
    required this.personContactId,
    this.role,
    this.isPrimary = false,
  });

  final String id;
  final String personContactId;
  final String? role;
  final bool isPrimary;

  ContactPerson copyWith({
    String? id,
    String? personContactId,
    String? role,
    bool? isPrimary,
    bool clearRole = false,
  }) {
    return ContactPerson(
      id: id ?? this.id,
      personContactId: personContactId ?? this.personContactId,
      role: clearRole ? null : (role ?? this.role),
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  factory ContactPerson.fromMap(Map<String, dynamic> map) {
    return ContactPerson(
      id: (map['id'] ?? '').toString(),
      personContactId: (map['person_contact_id'] ?? '').toString(),
      role: map['role'] as String?,
      isPrimary: parse.toBool(map['is_primary']) ?? false,
    );
  }

  factory ContactPerson.fromFirestoreMap(Map<String, dynamic> map) {
    return ContactPerson(
      id: (map['id'] ?? '').toString(),
      personContactId: (map['personContactId'] ?? '').toString(),
      role: map['role'] as String?,
      isPrimary: parse.toBool(map['isPrimary']) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_contact_id': personContactId,
      'role': role,
      'is_primary': isPrimary,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'personContactId': personContactId,
      'role': role,
      'isPrimary': isPrimary,
    };
  }
}

/// Eine Bankverbindung des Kontakts.
class BankAccount {
  const BankAccount({
    required this.id,
    required this.iban,
    this.bic,
    this.bankName,
    this.accountHolder,
    this.deactivated = false,
  });

  final String id;
  final String iban;
  final String? bic;
  final String? bankName;
  final String? accountHolder;
  final bool deactivated;

  BankAccount copyWith({
    String? id,
    String? iban,
    String? bic,
    String? bankName,
    String? accountHolder,
    bool? deactivated,
    bool clearBic = false,
    bool clearBankName = false,
    bool clearAccountHolder = false,
  }) {
    return BankAccount(
      id: id ?? this.id,
      iban: iban ?? this.iban,
      bic: clearBic ? null : (bic ?? this.bic),
      bankName: clearBankName ? null : (bankName ?? this.bankName),
      accountHolder:
          clearAccountHolder ? null : (accountHolder ?? this.accountHolder),
      deactivated: deactivated ?? this.deactivated,
    );
  }

  factory BankAccount.fromMap(Map<String, dynamic> map) {
    return BankAccount(
      id: (map['id'] ?? '').toString(),
      iban: (map['iban'] ?? '').toString(),
      bic: map['bic'] as String?,
      bankName: map['bank_name'] as String?,
      accountHolder: map['account_holder'] as String?,
      deactivated: parse.toBool(map['deactivated']) ?? false,
    );
  }

  factory BankAccount.fromFirestoreMap(Map<String, dynamic> map) {
    return BankAccount(
      id: (map['id'] ?? '').toString(),
      iban: (map['iban'] ?? '').toString(),
      bic: map['bic'] as String?,
      bankName: map['bankName'] as String?,
      accountHolder: map['accountHolder'] as String?,
      deactivated: parse.toBool(map['deactivated']) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'iban': iban,
      'bic': bic,
      'bank_name': bankName,
      'account_holder': accountHolder,
      'deactivated': deactivated,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'iban': iban,
      'bic': bic,
      'bankName': bankName,
      'accountHolder': accountHolder,
      'deactivated': deactivated,
    };
  }
}

/// Eine DSGVO-Einwilligung des Kontakts. Wie die übrigen Sub-Objekte
/// **eingebettet** in den Contact (Spark-frugal); Daten als ISO-8601-Strings
/// (einfacher als Timestamps in Arrays). Ein aktiver Consent hat
/// `withdrawnAt == null`.
class ContactConsent {
  const ContactConsent({
    required this.id,
    required this.consentType,
    required this.grantedAt,
    this.withdrawnAt,
    this.note,
  });

  final String id;
  final ConsentType consentType;
  final DateTime grantedAt;
  final DateTime? withdrawnAt;
  final String? note;

  bool get isActive => withdrawnAt == null;

  ContactConsent copyWith({
    DateTime? withdrawnAt,
    bool clearWithdrawnAt = false,
  }) {
    return ContactConsent(
      id: id,
      consentType: consentType,
      grantedAt: grantedAt,
      withdrawnAt: clearWithdrawnAt ? null : (withdrawnAt ?? this.withdrawnAt),
      note: note,
    );
  }

  factory ContactConsent.fromMap(Map<String, dynamic> map) {
    return ContactConsent(
      id: (map['id'] ?? '').toString(),
      consentType: ConsentTypeX.fromValue(map['consent_type']?.toString()),
      grantedAt: FirestoreDateParser.readLocalDate(map['granted_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      withdrawnAt: FirestoreDateParser.readLocalDate(map['withdrawn_at']),
      note: map['note'] as String?,
    );
  }

  factory ContactConsent.fromFirestoreMap(Map<String, dynamic> map) {
    return ContactConsent(
      id: (map['id'] ?? '').toString(),
      consentType: ConsentTypeX.fromValue(map['consentType']?.toString()),
      grantedAt: FirestoreDateParser.readLocalDate(map['grantedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      withdrawnAt: FirestoreDateParser.readLocalDate(map['withdrawnAt']),
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'consent_type': consentType.value,
      'granted_at': grantedAt.toIso8601String(),
      'withdrawn_at': withdrawnAt?.toIso8601String(),
      'note': note,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'consentType': consentType.value,
      'grantedAt': grantedAt.toIso8601String(),
      'withdrawnAt': withdrawnAt?.toIso8601String(),
      'note': note,
    };
  }
}
