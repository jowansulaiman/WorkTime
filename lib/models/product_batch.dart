import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Status einer Warencharge im MHD-/Ablauf-Tracking.
///
/// Serialisiert als snake_case-`value` (nicht der Dart-Name); `fromValue` hat
/// einen Default-Branch und wirft nie.
enum BatchStatus {
  /// Charge ist im Umlauf und wird bei Ablauf gewarnt.
  active,

  /// Charge wurde abverkauft (kein Ablauf-Alarm mehr).
  soldOut,

  /// Charge wurde entsorgt (kein Ablauf-Alarm mehr).
  discarded;

  String get value {
    switch (this) {
      case BatchStatus.active:
        return 'active';
      case BatchStatus.soldOut:
        return 'sold_out';
      case BatchStatus.discarded:
        return 'discarded';
    }
  }

  String get label {
    switch (this) {
      case BatchStatus.active:
        return 'Aktiv';
      case BatchStatus.soldOut:
        return 'Abverkauft';
      case BatchStatus.discarded:
        return 'Entsorgt';
    }
  }

  static BatchStatus fromValue(String? value) {
    switch (value) {
      case 'sold_out':
        return BatchStatus.soldOut;
      case 'discarded':
        return BatchStatus.discarded;
      case 'active':
      default:
        return BatchStatus.active;
    }
  }
}

/// Eine Warencharge (Los) eines Artikels mit genau **einem** Mindesthaltbarkeits-
/// datum (MHD). Ein Artikel kann mehrere Chargen mit unterschiedlichem Ablauf
/// haben (zwei Lieferungen → zwei Chargen) — deshalb ein eigenes Model statt
/// eines Feldes am `Product`.
///
/// [quantity] ist eine **weiche** Mengenangabe (nur zur Priorisierung/Anzeige,
/// nicht bilanziell — analog `Product.fridgeStock`). Der bilanzielle Bestand
/// bleibt `Product.currentStock`.
class ProductBatch {
  const ProductBatch({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.productId,
    this.productName,
    required this.expiryDate,
    this.quantity = 0,
    this.note,
    this.status = BatchStatus.active,
    this.resolvedByUid,
    this.resolvedAt,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Laden, zu dem die Charge gehoert (Multi-Tenancy + Kiosk-Skopierung).
  final String siteId;

  /// Artikel, zu dem die Charge gehoert.
  final String productId;

  /// Denormalisierter Artikelname fuer Anzeige ohne Join.
  final String? productName;

  /// Mindesthaltbarkeitsdatum. Auf lokale Mittagszeit (12:00) normalisiert, um
  /// Zeitzonen-/DST-Off-by-one zu vermeiden (wie `WorkEntry.date`).
  final DateTime expiryDate;

  /// Verbleibende Menge dieser Charge (weich, nicht bilanziell).
  final int quantity;

  /// Freitext-Notiz (z.B. „Palette hinten links").
  final String? note;

  final BatchStatus status;

  /// Wer die Charge als abverkauft/entsorgt markiert hat.
  final String? resolvedByUid;
  final DateTime? resolvedAt;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Normalisiert ein Datum auf lokale Mittagszeit (12:00) — kappt die Uhrzeit,
  /// vermeidet Off-by-one an DST-Grenzen.
  static DateTime normalizeDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 12);

  /// `YYYY-MM-DD`-String fuer stabile Sortierung/Query (analog `nameLower`).
  static String dayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get expiryDay => dayKey(expiryDate);

  /// M6/GB: `expiryDate` ist load-bearing (wie `WorkEntry.date`) — ein
  /// fehlendes/kaputtes MHD faellt NICHT mehr still auf 2000-01-01 zurueck
  /// (das erzeugte Dauer-„ueberfaellig"-Warnungen und verdeckte echte
  /// MHD-Probleme), sondern wirft [FormatException]. Die Lesepfade
  /// (Repo-Stream, DatabaseService._loadCollection) ueberspringen solche
  /// Datensaetze protokolliert.
  static DateTime _requireExpiry(DateTime? parsed, String source) {
    if (parsed == null) {
      throw FormatException(
        'ProductBatch ohne lesbares expiryDate ($source)',
      );
    }
    return normalizeDay(parsed);
  }

  factory ProductBatch.fromFirestore(String id, Map<String, dynamic> map) {
    return ProductBatch(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      productId: (map['productId'] ?? '').toString(),
      productName: map['productName'] as String?,
      expiryDate: _requireExpiry(
        FirestoreDateParser.readDate(map['expiryDate']),
        'firestore/$id',
      ),
      quantity: parse.toInt(map['quantity']) ?? 0,
      note: map['note'] as String?,
      status: BatchStatus.fromValue(map['status'] as String?),
      resolvedByUid: map['resolvedByUid'] as String?,
      resolvedAt: FirestoreDateParser.readDate(map['resolvedAt']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory ProductBatch.fromMap(Map<String, dynamic> map) {
    return ProductBatch(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      productId: (map['product_id'] ?? '').toString(),
      productName: map['product_name'] as String?,
      expiryDate: _requireExpiry(
        FirestoreDateParser.readLocalDate(map['expiry_date']),
        'lokal/${map['id'] ?? '?'}',
      ),
      quantity: parse.toInt(map['quantity']) ?? 0,
      note: map['note'] as String?,
      status: BatchStatus.fromValue(map['status'] as String?),
      resolvedByUid: map['resolved_by_uid'] as String?,
      resolvedAt: FirestoreDateParser.readLocalDate(map['resolved_at']),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'productId': productId,
      'productName': _trimmedOrNull(productName),
      'expiryDate': Timestamp.fromDate(normalizeDay(expiryDate)),
      // Stabiler Sortier-/Query-Schluessel (String), analog `nameLower`.
      'expiryDay': expiryDay,
      'quantity': quantity,
      'note': _trimmedOrNull(note),
      'status': status.value,
      'resolvedByUid': resolvedByUid,
      'resolvedAt':
          resolvedAt == null ? null : Timestamp.fromDate(resolvedAt!),
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'product_id': productId,
      'product_name': productName,
      'expiry_date': normalizeDay(expiryDate).toIso8601String(),
      'quantity': quantity,
      'note': note,
      'status': status.value,
      'resolved_by_uid': resolvedByUid,
      'resolved_at': resolvedAt?.toIso8601String(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ProductBatch copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? productId,
    String? productName,
    DateTime? expiryDate,
    int? quantity,
    String? note,
    BatchStatus? status,
    String? resolvedByUid,
    DateTime? resolvedAt,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearProductName = false,
    bool clearNote = false,
    bool clearResolvedByUid = false,
    bool clearResolvedAt = false,
  }) {
    return ProductBatch(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      productId: productId ?? this.productId,
      productName:
          clearProductName ? null : (productName ?? this.productName),
      expiryDate: expiryDate ?? this.expiryDate,
      quantity: quantity ?? this.quantity,
      note: clearNote ? null : (note ?? this.note),
      status: status ?? this.status,
      resolvedByUid:
          clearResolvedByUid ? null : (resolvedByUid ?? this.resolvedByUid),
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
