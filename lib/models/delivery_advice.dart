import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Status eines Lieferavises (angekündigte Lieferung).
///
/// Serialisiert als snake_case-`value` (nicht der Dart-Name); `fromValue` hat
/// einen Default-Branch und wirft nie (falscher String → [announced]).
enum DeliveryAdviceStatus {
  /// Lieferung wurde angekündigt, noch nicht eingegangen.
  announced,

  /// Lieferung ist eingegangen (Wareneingang gebucht — WW-7).
  received,

  /// Avis wurde storniert.
  cancelled;

  String get value {
    switch (this) {
      case DeliveryAdviceStatus.announced:
        return 'announced';
      case DeliveryAdviceStatus.received:
        return 'received';
      case DeliveryAdviceStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case DeliveryAdviceStatus.announced:
        return 'Angekündigt';
      case DeliveryAdviceStatus.received:
        return 'Eingegangen';
      case DeliveryAdviceStatus.cancelled:
        return 'Storniert';
    }
  }

  /// Avis ist noch offen (angekündigt, weder eingegangen noch storniert).
  bool get isOpen => this == DeliveryAdviceStatus.announced;

  static DeliveryAdviceStatus fromValue(String? value) {
    switch (value) {
      case 'received':
        return DeliveryAdviceStatus.received;
      case 'cancelled':
        return DeliveryAdviceStatus.cancelled;
      case 'announced':
      default:
        return DeliveryAdviceStatus.announced;
    }
  }
}

/// Eine avisierte Position innerhalb eines [DeliveryAdvice] (eingebettet, kein
/// eigenes Dokument — analog `PurchaseOrderItem`). `fromMap` liest tolerant
/// camelCase (Firestore) **und** snake_case (lokal); geschrieben wird je nach
/// Ziel getrennt über [toFirestoreMap]/[toMap].
class DeliveryAdviceItem {
  const DeliveryAdviceItem({
    this.productId,
    required this.name,
    this.sku,
    this.unit = 'Stück',
    required this.announcedQuantity,
    this.note,
  });

  /// Verknüpfter Artikel (falls zuordenbar); kann bei freier Avis-Position
  /// fehlen.
  final String? productId;
  final String name;
  final String? sku;
  final String unit;

  /// Avisierte (angekündigte) Menge dieser Position.
  final int announcedQuantity;
  final String? note;

  factory DeliveryAdviceItem.fromMap(Map<String, dynamic> map) {
    return DeliveryAdviceItem(
      productId: (map['productId'] ?? map['product_id']) as String?,
      name: (map['name'] ?? '').toString(),
      sku: (map['sku']) as String?,
      unit: (map['unit'] ?? 'Stück').toString().trim().isEmpty
          ? 'Stück'
          : (map['unit'] ?? 'Stück').toString(),
      announcedQuantity:
          parse.toInt(map['announcedQuantity'] ?? map['announced_quantity']) ??
              0,
      note: (map['note']) as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'name': name.trim(),
      'sku': _trimmedOrNull(sku),
      'unit': unit.trim().isEmpty ? 'Stück' : unit.trim(),
      'announcedQuantity': announcedQuantity,
      'note': _trimmedOrNull(note),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'name': name,
      'sku': sku,
      'unit': unit,
      'announced_quantity': announcedQuantity,
      'note': note,
    };
  }

  DeliveryAdviceItem copyWith({
    String? productId,
    bool clearProductId = false,
    String? name,
    String? sku,
    bool clearSku = false,
    String? unit,
    int? announcedQuantity,
    String? note,
    bool clearNote = false,
  }) {
    return DeliveryAdviceItem(
      productId: clearProductId ? null : (productId ?? this.productId),
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      unit: unit ?? this.unit,
      announcedQuantity: announcedQuantity ?? this.announcedQuantity,
      note: clearNote ? null : (note ?? this.note),
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

/// Ein Lieferavis (angekündigte Lieferung) für einen Laden.
///
/// Deckt Fälle ab, die der einfache `PurchaseOrder.expectedAt` (WW-3) nicht
/// abbildet: ein Avis ohne oder über mehrere Bestellungen sowie avisierte
/// Mengen je Position. Eigene Collection `deliveryAdvices` — **kein**
/// Callable-Pfad (direkte Firestore-Writes wie `productBatches`).
///
/// [expectedDate] ist auf lokale Mittagszeit (12:00) normalisiert (wie
/// `ProductBatch.expiryDate`/`WorkEntry.date`) und **load-bearing**: ein
/// fehlendes/kaputtes Datum wirft [FormatException] statt still auf einen
/// Ersatzwert zu fallen (die Lesepfade überspringen solche Datensätze
/// protokolliert). [expectedDay] ist der stabile `YYYY-MM-DD`-Sortier-/
/// Filterschlüssel (speist die „heute erwartet"-Karte aus WW-3).
class DeliveryAdvice {
  const DeliveryAdvice({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    this.supplierId,
    this.supplierName,
    this.purchaseOrderId,
    this.reference,
    this.status = DeliveryAdviceStatus.announced,
    required this.expectedDate,
    this.items = const [],
    this.notes,
    this.receivedAt,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;

  /// Laden, für den die Lieferung erwartet wird (Multi-Tenancy + Kiosk-Scoping).
  final String siteId;

  /// Denormalisierter Ladenname für Anzeige ohne Join.
  final String? siteName;

  /// Lieferant (falls bekannt) — ein Avis kann auch ohne Bestellbezug erfasst
  /// werden.
  final String? supplierId;
  final String? supplierName;

  /// Optional verknüpfte Bestellung. Fehlt bei einem Avis ohne oder über
  /// mehrere Bestellungen.
  final String? purchaseOrderId;

  /// Avis-/Lieferschein-Referenz des Lieferanten (Freitext).
  final String? reference;

  final DeliveryAdviceStatus status;

  /// Erwarteter Liefertermin (auf 12:00 normalisiert, load-bearing).
  final DateTime expectedDate;

  final List<DeliveryAdviceItem> items;
  final String? notes;

  /// Wann das Avis als eingegangen markiert wurde (WW-7).
  final DateTime? receivedAt;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get itemCount => items.length;

  /// Summe der avisierten Mengen über alle Positionen.
  int get totalAnnouncedQuantity =>
      items.fold(0, (total, item) => total + item.announcedQuantity);

  /// Normalisiert ein Datum auf lokale Mittagszeit (12:00) — kappt die Uhrzeit,
  /// vermeidet Off-by-one an DST-Grenzen (wie `ProductBatch.normalizeDay`).
  static DateTime normalizeDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 12);

  /// `YYYY-MM-DD`-String für stabile Sortierung/Query.
  static String dayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get expectedDay => dayKey(expectedDate);

  /// [expectedDate] ist load-bearing (wie `ProductBatch.expiryDate`) — ein
  /// fehlendes/kaputtes Datum fällt NICHT still auf einen Ersatzwert zurück,
  /// sondern wirft [FormatException]. Die Lesepfade (Repo-Stream,
  /// `DatabaseService._loadCollection`) überspringen solche Datensätze
  /// protokolliert.
  static DateTime _requireExpected(DateTime? parsed, String source) {
    if (parsed == null) {
      throw FormatException(
        'DeliveryAdvice ohne lesbares expectedDate ($source)',
      );
    }
    return normalizeDay(parsed);
  }

  factory DeliveryAdvice.fromFirestore(String id, Map<String, dynamic> map) {
    return DeliveryAdvice(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      supplierId: map['supplierId'] as String?,
      supplierName: map['supplierName'] as String?,
      purchaseOrderId: map['purchaseOrderId'] as String?,
      reference: map['reference'] as String?,
      status: DeliveryAdviceStatus.fromValue(map['status'] as String?),
      expectedDate: _requireExpected(
        FirestoreDateParser.readDate(map['expectedDate']),
        'firestore/$id',
      ),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      receivedAt: FirestoreDateParser.readDate(map['receivedAt']),
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory DeliveryAdvice.fromMap(Map<String, dynamic> map) {
    return DeliveryAdvice(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      supplierId: map['supplier_id'] as String?,
      supplierName: map['supplier_name'] as String?,
      purchaseOrderId: map['purchase_order_id'] as String?,
      reference: map['reference'] as String?,
      status: DeliveryAdviceStatus.fromValue(map['status'] as String?),
      expectedDate: _requireExpected(
        FirestoreDateParser.readLocalDate(map['expected_date']),
        'lokal/${map['id'] ?? '?'}',
      ),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      receivedAt: FirestoreDateParser.readLocalDate(map['received_at']),
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'siteName': _trimmedOrNull(siteName),
      'supplierId': _trimmedOrNull(supplierId),
      'supplierName': _trimmedOrNull(supplierName),
      'purchaseOrderId': _trimmedOrNull(purchaseOrderId),
      'reference': _trimmedOrNull(reference),
      'status': status.value,
      'expectedDate': Timestamp.fromDate(normalizeDay(expectedDate)),
      // Stabiler Sortier-/Query-Schlüssel (String), analog `expiryDay`.
      'expectedDay': expectedDay,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
      'notes': _trimmedOrNull(notes),
      'receivedAt': receivedAt == null ? null : Timestamp.fromDate(receivedAt!),
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'site_name': siteName,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_order_id': purchaseOrderId,
      'reference': reference,
      'status': status.value,
      'expected_date': normalizeDay(expectedDate).toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'notes': notes,
      'received_at': receivedAt?.toIso8601String(),
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  DeliveryAdvice copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    bool clearSiteName = false,
    String? supplierId,
    bool clearSupplierId = false,
    String? supplierName,
    bool clearSupplierName = false,
    String? purchaseOrderId,
    bool clearPurchaseOrderId = false,
    String? reference,
    bool clearReference = false,
    DeliveryAdviceStatus? status,
    DateTime? expectedDate,
    List<DeliveryAdviceItem>? items,
    String? notes,
    bool clearNotes = false,
    DateTime? receivedAt,
    bool clearReceivedAt = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeliveryAdvice(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      supplierId: clearSupplierId ? null : (supplierId ?? this.supplierId),
      supplierName:
          clearSupplierName ? null : (supplierName ?? this.supplierName),
      purchaseOrderId: clearPurchaseOrderId
          ? null
          : (purchaseOrderId ?? this.purchaseOrderId),
      reference: clearReference ? null : (reference ?? this.reference),
      status: status ?? this.status,
      expectedDate: expectedDate ?? this.expectedDate,
      items: items ?? this.items,
      notes: clearNotes ? null : (notes ?? this.notes),
      receivedAt: clearReceivedAt ? null : (receivedAt ?? this.receivedAt),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<DeliveryAdviceItem> _itemsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => DeliveryAdviceItem.fromMap(
              item.cast<String, dynamic>(),
            ))
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
