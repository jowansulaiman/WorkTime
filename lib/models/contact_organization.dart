import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Kontakt-Organisation (eigenständiges Adressbuch neben den
/// Kontakten). Der gespeicherte [value] (snake_case) ist stabil.
enum OrganizationType {
  agenturFuerArbeit,
  jobcenter,
  praktikumsbetrieb,
  kooperationspartner,
  behoerde,
  sonstige,
}

extension OrganizationTypeX on OrganizationType {
  String get value => switch (this) {
        OrganizationType.agenturFuerArbeit => 'agentur_fuer_arbeit',
        OrganizationType.jobcenter => 'jobcenter',
        OrganizationType.praktikumsbetrieb => 'praktikumsbetrieb',
        OrganizationType.kooperationspartner => 'kooperationspartner',
        OrganizationType.behoerde => 'behoerde',
        OrganizationType.sonstige => 'sonstige',
      };

  String get label => switch (this) {
        OrganizationType.agenturFuerArbeit => 'Agentur für Arbeit',
        OrganizationType.jobcenter => 'Jobcenter',
        OrganizationType.praktikumsbetrieb => 'Praktikumsbetrieb',
        OrganizationType.kooperationspartner => 'Kooperationspartner',
        OrganizationType.behoerde => 'Behörde',
        OrganizationType.sonstige => 'Sonstige',
      };

  static OrganizationType fromValue(String? value) => switch (value) {
        'agentur_fuer_arbeit' => OrganizationType.agenturFuerArbeit,
        'jobcenter' => OrganizationType.jobcenter,
        'praktikumsbetrieb' => OrganizationType.praktikumsbetrieb,
        'kooperationspartner' => OrganizationType.kooperationspartner,
        'behoerde' => OrganizationType.behoerde,
        _ => OrganizationType.sonstige,
      };

  static const List<OrganizationType> ordered = OrganizationType.values;
}

/// Eine Kontakt-Organisation (z. B. Agentur für Arbeit, Jobcenter, Behörde).
///
/// Org-skopiert unter `organizations/{orgId}/contactOrganizations`. Bewusst
/// eigenständiges Adressbuch (nicht mit einzelnen [Contact]s verknüpft), 1:1 zu
/// AllTecs `ContactOrganization`.
class ContactOrganization {
  const ContactOrganization({
    this.id,
    required this.orgId,
    required this.name,
    this.type = OrganizationType.sonstige,
    this.city,
    this.website,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;
  final OrganizationType type;
  final String? city;
  final String? website;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ContactOrganization copyWith({
    String? id,
    String? orgId,
    String? name,
    OrganizationType? type,
    String? city,
    String? website,
    bool? isActive,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearCity = false,
    bool clearWebsite = false,
  }) {
    return ContactOrganization(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      type: type ?? this.type,
      city: clearCity ? null : (city ?? this.city),
      website: clearWebsite ? null : (website ?? this.website),
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ContactOrganization.fromFirestore(String id, Map<String, dynamic> map) {
    return ContactOrganization(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: OrganizationTypeX.fromValue(map['type']?.toString()),
      city: map['city'] as String?,
      website: map['website'] as String?,
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory ContactOrganization.fromMap(Map<String, dynamic> map) {
    return ContactOrganization(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: OrganizationTypeX.fromValue(map['type']?.toString()),
      city: map['city'] as String?,
      website: map['website'] as String?,
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
      'city': _trimmedOrNull(city),
      'website': _trimmedOrNull(website),
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
      'city': city,
      'website': website,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
