import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Ein festes Fach/Regalplatz im Paketshop mit **eigenem Bin-Barcode**.
///
/// Die Belegung wird NICHT hier gespeichert (kein `occupied`-Feld), sondern aus
/// den offenen `ParcelShipment.compartmentId` abgeleitet — dadurch trägt ein
/// Fach automatisch mehrere Pakete und bei Teilausgabe bleibt es belegt
/// (Plan §6.2). [barcode] ist je Standort eindeutig (clientseitig geprüft).
class ShelfCompartment {
  const ShelfCompartment({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    required this.label,
    required this.barcode,
    this.active = true,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String? siteName;

  /// Frei wählbares Label, z. B. „A2".
  final String label;

  /// Fach-Bin-Barcode (roher Scan-String), je Standort eindeutig.
  final String barcode;

  /// Deaktivierbar statt löschen (belegte Fächer bleiben so referenzierbar).
  final bool active;

  final DateTime? createdAt;

  /// Abgeleiteter Sortier-/Suchschlüssel des Labels.
  String get labelLower => label.trim().toLowerCase();

  factory ShelfCompartment.fromFirestore(String id, Map<String, dynamic> map) {
    return ShelfCompartment(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      label: (map['label'] ?? '').toString(),
      barcode: (map['barcode'] ?? '').toString(),
      active: parse.toBool(map['active']) ?? true,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory ShelfCompartment.fromMap(Map<String, dynamic> map) {
    return ShelfCompartment(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      label: (map['label'] ?? '').toString(),
      barcode: (map['barcode'] ?? '').toString(),
      active: parse.toBool(map['active']) ?? true,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  /// camelCase + [Timestamp], **ohne** `id` und **ohne** `createdAt`
  /// (Repository setzt `createdAt` via `FieldValue.serverTimestamp()`).
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'siteName': _trimmedOrNull(siteName),
      'label': label.trim(),
      'labelLower': labelLower,
      'barcode': barcode.trim(),
      'active': active,
    };
  }

  /// snake_case + ISO-8601, **mit** `id`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'site_name': siteName,
      'label': label,
      'label_lower': labelLower,
      'barcode': barcode,
      'active': active,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  ShelfCompartment copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    String? label,
    String? barcode,
    bool? active,
    DateTime? createdAt,
    bool clearSiteName = false,
  }) {
    return ShelfCompartment(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      label: label ?? this.label,
      barcode: barcode ?? this.barcode,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
