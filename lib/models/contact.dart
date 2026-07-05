import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'contact_activity.dart';
import 'contact_details.dart';

/// Art eines Kontakts (Kategorie fuer Filter und Gruppierung).
///
/// Der gespeicherte Wert ([value], snake_case) ist stabil und darf nicht mehr
/// umbenannt werden; das [label] ist die deutsche UI-Beschriftung.
enum ContactType {
  customer,
  supplier,
  wholesaler,
  company,
  serviceProvider,
  authority,
  landlord,
  bankInsurance,
  taxAdvisor,
  other,
}

extension ContactTypeX on ContactType {
  String get value => switch (this) {
        ContactType.customer => 'customer',
        ContactType.supplier => 'supplier',
        ContactType.wholesaler => 'wholesaler',
        ContactType.company => 'company',
        ContactType.serviceProvider => 'service_provider',
        ContactType.authority => 'authority',
        ContactType.landlord => 'landlord',
        ContactType.bankInsurance => 'bank_insurance',
        ContactType.taxAdvisor => 'tax_advisor',
        ContactType.other => 'other',
      };

  String get label => switch (this) {
        ContactType.customer => 'Kunde',
        ContactType.supplier => 'Lieferant',
        ContactType.wholesaler => 'Großhändler',
        ContactType.company => 'Unternehmen / Partner',
        ContactType.serviceProvider => 'Dienstleister',
        ContactType.authority => 'Behörde',
        ContactType.landlord => 'Vermieter',
        ContactType.bankInsurance => 'Bank / Versicherung',
        ContactType.taxAdvisor => 'Steuerberater',
        ContactType.other => 'Sonstige',
      };

  /// Kurzform fuer enge Badges/Spalten (z. B. im PDF-Export).
  String get shortLabel => switch (this) {
        ContactType.customer => 'Kunde',
        ContactType.supplier => 'Lieferant',
        ContactType.wholesaler => 'Großhändler',
        ContactType.company => 'Partner',
        ContactType.serviceProvider => 'Dienstleister',
        ContactType.authority => 'Behörde',
        ContactType.landlord => 'Vermieter',
        ContactType.bankInsurance => 'Bank/Vers.',
        ContactType.taxAdvisor => 'Steuerberater',
        ContactType.other => 'Sonstige',
      };

  static ContactType fromValue(String? value) => switch (value) {
        'customer' => ContactType.customer,
        'supplier' => ContactType.supplier,
        'wholesaler' => ContactType.wholesaler,
        'company' => ContactType.company,
        'service_provider' => ContactType.serviceProvider,
        'authority' => ContactType.authority,
        'landlord' => ContactType.landlord,
        'bank_insurance' => ContactType.bankInsurance,
        'tax_advisor' => ContactType.taxAdvisor,
        _ => ContactType.other,
      };

  /// Reihenfolge fuer Filter-Chips und Gruppierung im UI/PDF.
  static const List<ContactType> ordered = ContactType.values;
}

/// Ein Kontakt (Kunde, Lieferant, Geschaeftspartner, Behoerde, …).
///
/// Org-skopiert unter `organizations/{orgId}/contacts`. Kontakte gelten
/// organisationsweit; ueber das optionale [siteId]/[siteName] koennen sie einem
/// einzelnen Laden zugeordnet werden ("Allgemein" = ohne Standort), damit sich
/// die Liste pro Standort filtern laesst.
class Contact {
  const Contact({
    this.id,
    required this.orgId,
    required this.name,
    this.type = ContactType.customer,
    this.contactPerson,
    this.email,
    this.phone,
    this.mobile,
    this.website,
    this.street,
    this.postalCode,
    this.city,
    this.taxId,
    this.customerNumber,
    this.notes,
    this.siteId,
    this.siteName,
    this.tags = const [],
    this.activities = const [],
    this.addresses = const [],
    this.channels = const [],
    this.contactPersons = const [],
    this.bankAccounts = const [],
    this.kind = ContactKind.company,
    this.status = ContactStatus.aktiv,
    this.blacklisted = false,
    this.alias,
    this.firstName,
    this.lastName,
    this.title,
    this.gender = Gender.unbekannt,
    this.birthday,
    this.position,
    this.department,
    this.companyName,
    this.legalName,
    this.registrationNumber,
    this.companyAnniversary,
    this.debitorNumber,
    this.creditorNumber,
    this.avatarUrl,
    this.customerSince,
    this.isFavorite = false,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Firmen- bzw. Kontaktname (Pflichtfeld, Sortier-/Suchschluessel).
  final String name;
  final ContactType type;

  /// Ansprechpartner (Person), falls [name] eine Firma ist.
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? website;
  final String? street;
  final String? postalCode;
  final String? city;

  /// USt-IdNr. / Steuernummer.
  final String? taxId;

  /// Eigene Kunden-/Lieferantennummer bei diesem Kontakt.
  final String? customerNumber;
  final String? notes;

  /// Optionale Standort-Zuordnung. `null` = gilt fuer beide Laeden (Allgemein).
  final String? siteId;
  final String? siteName;

  /// Freie Schlagworte zum zusaetzlichen Filtern.
  final List<String> tags;

  /// Eingebettete Kontakthistorie (Anrufe, E-Mails, Notizen …), neueste zuerst.
  final List<ContactActivity> activities;

  /// Zusätzliche Adressen (Rechnung/Lieferung/Niederlassung …). Die flache
  /// Hauptadresse bleibt in [street]/[postalCode]/[city]. (AllTec-1:1, M2)
  final List<ContactAddress> addresses;

  /// Typisierte Kommunikationskanäle (E-Mail/Telefon/Mobil/Fax/Website) mit
  /// Kontext/Primär. Ergänzt die flachen [email]/[phone]/[mobile]/[website].
  final List<CommunicationChannel> channels;

  /// Ansprechpartner-Verknüpfungen (Referenzen auf Personen-Kontakte).
  final List<ContactPerson> contactPersons;

  /// Bankverbindungen des Kontakts.
  final List<BankAccount> bankAccounts;

  // ── Person/Firma-Split + Klassifizierung (AllTec-1:1, M3) ──────────────────

  /// Natürliche Person oder Firma. Steuert Stammdaten-Felder + Anzeige.
  final ContactKind kind;

  /// Feiner Status (ergänzt das grobe [isActive]-Archiv-Flag).
  final ContactStatus status;

  /// Auf der Blacklist (z. B. Zahlungsausfall).
  final bool blacklisted;

  /// Anzeigename/Alias (hat Vorrang vor Firmen-/Personenname).
  final String? alias;

  // Person-Felder (nur sinnvoll bei [ContactKind.person]).
  final String? firstName;
  final String? lastName;

  /// Titel/Grad der Person (z. B. „Dr.").
  final String? title;
  final Gender gender;
  final DateTime? birthday;
  final String? position;
  final String? department;

  // Firma-Felder (nur sinnvoll bei [ContactKind.company]).
  final String? companyName;

  /// Offizieller/vollständiger Name (Handelsregister).
  final String? legalName;
  final String? registrationNumber;
  final DateTime? companyAnniversary;

  // Nummern (Finanzbuchhaltung). [customerNumber]/[taxId] existieren bereits.
  final String? debitorNumber;
  final String? creditorNumber;

  /// Profilbild-URL (Firebase Storage; Upload folgt in M8).
  final String? avatarUrl;

  /// Kunde seit.
  final DateTime? customerSince;

  /// Anzeigename: [alias] → Firmenname → Personenname → [name]-Fallback.
  String get displayName {
    final a = alias?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (kind == ContactKind.company) {
      final c = companyName?.trim();
      if (c != null && c.isNotEmpty) return c;
    } else {
      final person =
          [firstName?.trim() ?? '', lastName?.trim() ?? ''].where((v) => v.isNotEmpty).join(' ');
      if (person.isNotEmpty) return person;
    }
    return name;
  }

  /// Als wichtig markiert (Favorit).
  final bool isFavorite;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Erste(r) Buchstabe(n) fuer den Avatar.
  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  bool get hasAddress =>
      (street?.trim().isNotEmpty ?? false) ||
      (postalCode?.trim().isNotEmpty ?? false) ||
      (city?.trim().isNotEmpty ?? false);

  /// Einzeilige Adresse fuer Anzeige/Export (z. B. "Holtenauer Str. 1, 24105 Kiel").
  String get displayAddress {
    final streetPart = street?.trim() ?? '';
    final cityPart = [
      postalCode?.trim() ?? '',
      city?.trim() ?? '',
    ].where((value) => value.isNotEmpty).join(' ');
    return [streetPart, cityPart]
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  /// Bevorzugte Telefonnummer: Festnetz, sonst Mobil.
  String? get primaryPhone {
    final landline = phone?.trim();
    if (landline != null && landline.isNotEmpty) {
      return landline;
    }
    final cell = mobile?.trim();
    if (cell != null && cell.isNotEmpty) {
      return cell;
    }
    return null;
  }

  factory Contact.fromFirestore(String id, Map<String, dynamic> map) {
    return Contact(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: ContactTypeX.fromValue(map['type']?.toString()),
      contactPerson: map['contactPerson'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      mobile: map['mobile'] as String?,
      website: map['website'] as String?,
      street: map['street'] as String?,
      postalCode: map['postalCode'] as String?,
      city: map['city'] as String?,
      taxId: map['taxId'] as String?,
      customerNumber: map['customerNumber'] as String?,
      notes: map['notes'] as String?,
      siteId: map['siteId'] as String?,
      siteName: map['siteName'] as String?,
      tags: _tagsFromList(map['tags']),
      activities: _activitiesFromList(map['activities'], firestore: true),
      addresses: _addressesFromList(map['addresses'], firestore: true),
      channels: _channelsFromList(map['channels'], firestore: true),
      contactPersons:
          _contactPersonsFromList(map['contactPersons'], firestore: true),
      bankAccounts: _bankAccountsFromList(map['bankAccounts'], firestore: true),
      kind: ContactKindX.fromValue(map['kind']?.toString()),
      status: ContactStatusX.fromValue(map['status']?.toString()),
      blacklisted: parse.toBool(map['blacklisted']) ?? false,
      alias: map['alias'] as String?,
      firstName: map['firstName'] as String?,
      lastName: map['lastName'] as String?,
      title: map['title'] as String?,
      gender: GenderX.fromValue(map['gender']?.toString()),
      birthday: FirestoreDateParser.readDate(map['birthday']),
      position: map['position'] as String?,
      department: map['department'] as String?,
      companyName: map['companyName'] as String?,
      legalName: map['legalName'] as String?,
      registrationNumber: map['registrationNumber'] as String?,
      companyAnniversary: FirestoreDateParser.readDate(map['companyAnniversary']),
      debitorNumber: map['debitorNumber'] as String?,
      creditorNumber: map['creditorNumber'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      customerSince: FirestoreDateParser.readDate(map['customerSince']),
      isFavorite: parse.toBool(map['isFavorite']) ?? false,
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: ContactTypeX.fromValue(map['type']?.toString()),
      contactPerson: map['contact_person'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      mobile: map['mobile'] as String?,
      website: map['website'] as String?,
      street: map['street'] as String?,
      postalCode: map['postal_code'] as String?,
      city: map['city'] as String?,
      taxId: map['tax_id'] as String?,
      customerNumber: map['customer_number'] as String?,
      notes: map['notes'] as String?,
      siteId: map['site_id'] as String?,
      siteName: map['site_name'] as String?,
      tags: _tagsFromList(map['tags']),
      activities: _activitiesFromList(map['activities'], firestore: false),
      addresses: _addressesFromList(map['addresses'], firestore: false),
      channels: _channelsFromList(map['channels'], firestore: false),
      contactPersons:
          _contactPersonsFromList(map['contact_persons'], firestore: false),
      bankAccounts:
          _bankAccountsFromList(map['bank_accounts'], firestore: false),
      kind: ContactKindX.fromValue(map['kind']?.toString()),
      status: ContactStatusX.fromValue(map['status']?.toString()),
      blacklisted: parse.toBool(map['blacklisted']) ?? false,
      alias: map['alias'] as String?,
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      title: map['title'] as String?,
      gender: GenderX.fromValue(map['gender']?.toString()),
      birthday: FirestoreDateParser.readLocalDate(map['birthday']),
      position: map['position'] as String?,
      department: map['department'] as String?,
      companyName: map['company_name'] as String?,
      legalName: map['legal_name'] as String?,
      registrationNumber: map['registration_number'] as String?,
      companyAnniversary:
          FirestoreDateParser.readLocalDate(map['company_anniversary']),
      debitorNumber: map['debitor_number'] as String?,
      creditorNumber: map['creditor_number'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      customerSince: FirestoreDateParser.readLocalDate(map['customer_since']),
      isFavorite: parse.toBool(map['is_favorite']) ?? false,
      isActive: parse.toBool(map['is_active']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'type': type.value,
      'contactPerson': _trimmedOrNull(contactPerson),
      'email': _trimmedOrNull(email),
      'phone': _trimmedOrNull(phone),
      'mobile': _trimmedOrNull(mobile),
      'website': _trimmedOrNull(website),
      'street': _trimmedOrNull(street),
      'postalCode': _trimmedOrNull(postalCode),
      'city': _trimmedOrNull(city),
      'taxId': _trimmedOrNull(taxId),
      'customerNumber': _trimmedOrNull(customerNumber),
      'notes': _trimmedOrNull(notes),
      'siteId': _trimmedOrNull(siteId),
      'siteName': _trimmedOrNull(siteName),
      'tags': tags,
      'activities': activities.map((a) => a.toFirestoreMap()).toList(),
      'addresses': addresses.map((a) => a.toFirestoreMap()).toList(),
      'channels': channels.map((c) => c.toFirestoreMap()).toList(),
      'contactPersons': contactPersons.map((p) => p.toFirestoreMap()).toList(),
      'bankAccounts': bankAccounts.map((b) => b.toFirestoreMap()).toList(),
      'kind': kind.value,
      'status': status.value,
      'blacklisted': blacklisted,
      'alias': _trimmedOrNull(alias),
      'firstName': _trimmedOrNull(firstName),
      'lastName': _trimmedOrNull(lastName),
      'title': _trimmedOrNull(title),
      'gender': gender.value,
      'birthday': birthday,
      'position': _trimmedOrNull(position),
      'department': _trimmedOrNull(department),
      'companyName': _trimmedOrNull(companyName),
      'legalName': _trimmedOrNull(legalName),
      'registrationNumber': _trimmedOrNull(registrationNumber),
      'companyAnniversary': companyAnniversary,
      'debitorNumber': _trimmedOrNull(debitorNumber),
      'creditorNumber': _trimmedOrNull(creditorNumber),
      'avatarUrl': _trimmedOrNull(avatarUrl),
      'customerSince': customerSince,
      'isFavorite': isFavorite,
      'isActive': isActive,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'type': type.value,
      'contact_person': contactPerson,
      'email': email,
      'phone': phone,
      'mobile': mobile,
      'website': website,
      'street': street,
      'postal_code': postalCode,
      'city': city,
      'tax_id': taxId,
      'customer_number': customerNumber,
      'notes': notes,
      'site_id': siteId,
      'site_name': siteName,
      'tags': tags,
      'activities': activities.map((a) => a.toMap()).toList(),
      'addresses': addresses.map((a) => a.toMap()).toList(),
      'channels': channels.map((c) => c.toMap()).toList(),
      'contact_persons': contactPersons.map((p) => p.toMap()).toList(),
      'bank_accounts': bankAccounts.map((b) => b.toMap()).toList(),
      'kind': kind.value,
      'status': status.value,
      'blacklisted': blacklisted,
      'alias': alias,
      'first_name': firstName,
      'last_name': lastName,
      'title': title,
      'gender': gender.value,
      'birthday': birthday?.toIso8601String(),
      'position': position,
      'department': department,
      'company_name': companyName,
      'legal_name': legalName,
      'registration_number': registrationNumber,
      'company_anniversary': companyAnniversary?.toIso8601String(),
      'debitor_number': debitorNumber,
      'creditor_number': creditorNumber,
      'avatar_url': avatarUrl,
      'customer_since': customerSince?.toIso8601String(),
      'is_favorite': isFavorite,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Contact copyWith({
    String? id,
    String? orgId,
    String? name,
    ContactType? type,
    String? contactPerson,
    String? email,
    String? phone,
    String? mobile,
    String? website,
    String? street,
    String? postalCode,
    String? city,
    String? taxId,
    String? customerNumber,
    String? notes,
    String? siteId,
    String? siteName,
    List<String>? tags,
    List<ContactActivity>? activities,
    List<ContactAddress>? addresses,
    List<CommunicationChannel>? channels,
    List<ContactPerson>? contactPersons,
    List<BankAccount>? bankAccounts,
    ContactKind? kind,
    ContactStatus? status,
    bool? blacklisted,
    String? alias,
    String? firstName,
    String? lastName,
    String? title,
    Gender? gender,
    DateTime? birthday,
    String? position,
    String? department,
    String? companyName,
    String? legalName,
    String? registrationNumber,
    DateTime? companyAnniversary,
    String? debitorNumber,
    String? creditorNumber,
    String? avatarUrl,
    DateTime? customerSince,
    bool? isFavorite,
    bool? isActive,
    bool clearContactPerson = false,
    bool clearAlias = false,
    bool clearFirstName = false,
    bool clearLastName = false,
    bool clearTitle = false,
    bool clearBirthday = false,
    bool clearPosition = false,
    bool clearDepartment = false,
    bool clearCompanyName = false,
    bool clearLegalName = false,
    bool clearRegistrationNumber = false,
    bool clearCompanyAnniversary = false,
    bool clearDebitorNumber = false,
    bool clearCreditorNumber = false,
    bool clearAvatarUrl = false,
    bool clearCustomerSince = false,
    bool clearEmail = false,
    bool clearPhone = false,
    bool clearMobile = false,
    bool clearWebsite = false,
    bool clearStreet = false,
    bool clearPostalCode = false,
    bool clearCity = false,
    bool clearTaxId = false,
    bool clearCustomerNumber = false,
    bool clearNotes = false,
    bool clearSite = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      type: type ?? this.type,
      contactPerson:
          clearContactPerson ? null : (contactPerson ?? this.contactPerson),
      email: clearEmail ? null : (email ?? this.email),
      phone: clearPhone ? null : (phone ?? this.phone),
      mobile: clearMobile ? null : (mobile ?? this.mobile),
      website: clearWebsite ? null : (website ?? this.website),
      street: clearStreet ? null : (street ?? this.street),
      postalCode: clearPostalCode ? null : (postalCode ?? this.postalCode),
      city: clearCity ? null : (city ?? this.city),
      taxId: clearTaxId ? null : (taxId ?? this.taxId),
      customerNumber:
          clearCustomerNumber ? null : (customerNumber ?? this.customerNumber),
      notes: clearNotes ? null : (notes ?? this.notes),
      siteId: clearSite ? null : (siteId ?? this.siteId),
      siteName: clearSite ? null : (siteName ?? this.siteName),
      tags: tags ?? this.tags,
      activities: activities ?? this.activities,
      addresses: addresses ?? this.addresses,
      channels: channels ?? this.channels,
      contactPersons: contactPersons ?? this.contactPersons,
      bankAccounts: bankAccounts ?? this.bankAccounts,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      blacklisted: blacklisted ?? this.blacklisted,
      alias: clearAlias ? null : (alias ?? this.alias),
      firstName: clearFirstName ? null : (firstName ?? this.firstName),
      lastName: clearLastName ? null : (lastName ?? this.lastName),
      title: clearTitle ? null : (title ?? this.title),
      gender: gender ?? this.gender,
      birthday: clearBirthday ? null : (birthday ?? this.birthday),
      position: clearPosition ? null : (position ?? this.position),
      department: clearDepartment ? null : (department ?? this.department),
      companyName: clearCompanyName ? null : (companyName ?? this.companyName),
      legalName: clearLegalName ? null : (legalName ?? this.legalName),
      registrationNumber: clearRegistrationNumber
          ? null
          : (registrationNumber ?? this.registrationNumber),
      companyAnniversary: clearCompanyAnniversary
          ? null
          : (companyAnniversary ?? this.companyAnniversary),
      debitorNumber:
          clearDebitorNumber ? null : (debitorNumber ?? this.debitorNumber),
      creditorNumber:
          clearCreditorNumber ? null : (creditorNumber ?? this.creditorNumber),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      customerSince:
          clearCustomerSince ? null : (customerSince ?? this.customerSince),
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<ContactActivity> _activitiesFromList(
    dynamic value, {
    required bool firestore,
  }) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) {
          final map = item.cast<String, dynamic>();
          return firestore
              ? ContactActivity.fromFirestoreMap(map)
              : ContactActivity.fromMap(map);
        })
        .toList(growable: false);
  }

  static List<ContactAddress> _addressesFromList(
    dynamic value, {
    required bool firestore,
  }) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      final map = item.cast<String, dynamic>();
      return firestore
          ? ContactAddress.fromFirestoreMap(map)
          : ContactAddress.fromMap(map);
    }).toList(growable: false);
  }

  static List<CommunicationChannel> _channelsFromList(
    dynamic value, {
    required bool firestore,
  }) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      final map = item.cast<String, dynamic>();
      return firestore
          ? CommunicationChannel.fromFirestoreMap(map)
          : CommunicationChannel.fromMap(map);
    }).toList(growable: false);
  }

  static List<ContactPerson> _contactPersonsFromList(
    dynamic value, {
    required bool firestore,
  }) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      final map = item.cast<String, dynamic>();
      return firestore
          ? ContactPerson.fromFirestoreMap(map)
          : ContactPerson.fromMap(map);
    }).toList(growable: false);
  }

  static List<BankAccount> _bankAccountsFromList(
    dynamic value, {
    required bool firestore,
  }) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      final map = item.cast<String, dynamic>();
      return firestore
          ? BankAccount.fromFirestoreMap(map)
          : BankAccount.fromMap(map);
    }).toList(growable: false);
  }

  static List<String> _tagsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
