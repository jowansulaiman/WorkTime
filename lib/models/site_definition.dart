import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

class SiteDefinition {
  static const String germanyCountryCode = 'DE';
  static const List<String> germanFederalStates = [
    'Baden-Wuerttemberg',
    'Bayern',
    'Berlin',
    'Brandenburg',
    'Bremen',
    'Hamburg',
    'Hessen',
    'Mecklenburg-Vorpommern',
    'Niedersachsen',
    'Nordrhein-Westfalen',
    'Rheinland-Pfalz',
    'Saarland',
    'Sachsen',
    'Sachsen-Anhalt',
    'Schleswig-Holstein',
    'Thueringen',
  ];

  const SiteDefinition({
    this.id,
    required this.orgId,
    required this.name,
    this.code,
    this.street,
    this.postalCode,
    this.city,
    this.federalState,
    this.countryCode = germanyCountryCode,
    this.latitude,
    this.longitude,
    this.description,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;
  final String? code;
  final String? street;
  final String? postalCode;
  final String? city;
  final String? federalState;
  final String countryCode;
  final double? latitude;
  final double? longitude;
  final String? description;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayCode => code?.trim().isNotEmpty == true ? code!.trim() : '';
  String get displayAddress {
    final parts = [
      if (street?.trim().isNotEmpty == true) street!.trim(),
      if (postalCode?.trim().isNotEmpty == true ||
          city?.trim().isNotEmpty == true)
        [
          if (postalCode?.trim().isNotEmpty == true) postalCode!.trim(),
          if (city?.trim().isNotEmpty == true) city!.trim(),
        ].join(' '),
    ];
    return parts.join(', ');
  }

  String get coordinateLabel {
    if (latitude == null || longitude == null) {
      return '';
    }
    return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
  }

  static bool isValidGermanPostalCode(String value) {
    return RegExp(r'^\d{5}$').hasMatch(value.trim());
  }

  static bool isWithinGermanyBounds(double latitude, double longitude) {
    return latitude >= 47.27011 &&
        latitude <= 55.09916 &&
        longitude >= 5.86631 &&
        longitude <= 15.04193;
  }

  static String? normalizeGermanFederalState(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final state in germanFederalStates) {
      if (state.toLowerCase() == normalized) {
        return state;
      }
    }
    return null;
  }

  factory SiteDefinition.fromFirestore(String id, Map<String, dynamic> map) {
    return SiteDefinition(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      code: map['code'] as String?,
      street: map['street'] as String?,
      postalCode: map['postalCode'] as String?,
      city: map['city'] as String?,
      federalState: map['federalState'] as String?,
      countryCode:
          (map['countryCode'] ?? germanyCountryCode).toString().trim().isEmpty
              ? germanyCountryCode
              : (map['countryCode'] ?? germanyCountryCode).toString(),
      latitude: _readDouble(map['latitude']),
      longitude: _readDouble(map['longitude']),
      description: map['description'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory SiteDefinition.fromMap(Map<String, dynamic> map) {
    return SiteDefinition(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      code: map['code'] as String?,
      street: map['street'] as String?,
      postalCode: map['postal_code'] as String?,
      city: map['city'] as String?,
      federalState: map['federal_state'] as String?,
      countryCode:
          (map['country_code'] ?? germanyCountryCode).toString().trim().isEmpty
              ? germanyCountryCode
              : (map['country_code'] ?? germanyCountryCode).toString(),
      latitude: _readDouble(map['latitude']),
      longitude: _readDouble(map['longitude']),
      description: map['description'] as String?,
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
      'code': _trimmedOrNull(code),
      'street': _trimmedOrNull(street),
      'postalCode': _trimmedOrNull(postalCode),
      'city': _trimmedOrNull(city),
      'federalState': _trimmedOrNull(federalState),
      'countryCode':
          countryCode.trim().isEmpty ? germanyCountryCode : countryCode.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'description': _trimmedOrNull(description),
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'code': code,
      'street': street,
      'postal_code': postalCode,
      'city': city,
      'federal_state': federalState,
      'country_code': countryCode,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  SiteDefinition copyWith({
    String? id,
    String? orgId,
    String? name,
    String? code,
    String? street,
    String? postalCode,
    String? city,
    String? federalState,
    String? countryCode,
    double? latitude,
    double? longitude,
    String? description,
    bool clearCode = false,
    bool clearStreet = false,
    bool clearPostalCode = false,
    bool clearCity = false,
    bool clearFederalState = false,
    bool clearLatitude = false,
    bool clearLongitude = false,
    bool clearDescription = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SiteDefinition(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      code: clearCode ? null : (code ?? this.code),
      street: clearStreet ? null : (street ?? this.street),
      postalCode: clearPostalCode ? null : (postalCode ?? this.postalCode),
      city: clearCity ? null : (city ?? this.city),
      federalState:
          clearFederalState ? null : (federalState ?? this.federalState),
      countryCode: countryCode ?? this.countryCode,
      latitude: clearLatitude ? null : (latitude ?? this.latitude),
      longitude: clearLongitude ? null : (longitude ?? this.longitude),
      description: clearDescription ? null : (description ?? this.description),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double? _readDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
