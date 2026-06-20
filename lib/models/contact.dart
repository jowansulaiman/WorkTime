import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

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
    bool? isFavorite,
    bool? isActive,
    bool clearContactPerson = false,
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
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
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
