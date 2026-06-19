import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Artikel im Warenbestand eines Standorts (Laden).
///
/// Jeder Artikel gehoert zu genau einem Standort ([siteId]), damit Bestand und
/// Preise pro Laden gefuehrt werden. Ein Artikel, der in beiden Laeden gefuehrt
/// wird, existiert als zwei Datensaetze.
class Product {
  const Product({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    required this.name,
    this.sku,
    this.barcode,
    this.category,
    this.unit = defaultUnit,
    this.supplierId,
    this.supplierName,
    this.purchasePriceCents,
    this.sellingPriceCents,
    this.currentStock = 0,
    this.minStock = 0,
    this.reorderQuantity,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  static const String defaultUnit = 'Stück';

  final String? id;
  final String orgId;

  /// Laden, zu dem der Artikel gehoert.
  final String siteId;
  final String? siteName;
  final String name;

  /// Interne Artikelnummer.
  final String? sku;

  /// Barcode / EAN.
  final String? barcode;

  /// Warengruppe (z.B. Tabak, Zeitschriften, Getraenke).
  final String? category;

  /// Verkaufseinheit (Stueck, Stange, Packung ...).
  final String unit;

  /// Standard-Lieferant fuer Nachbestellungen.
  final String? supplierId;
  final String? supplierName;

  /// Einkaufspreis in Cent.
  final int? purchasePriceCents;

  /// Verkaufspreis in Cent.
  final int? sellingPriceCents;

  /// Aktueller Bestand.
  final int currentStock;

  /// Meldebestand: bei Erreichen sollte nachbestellt werden.
  final int minStock;

  /// Vorgeschlagene Bestellmenge.
  final int? reorderQuantity;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True, wenn der Bestand den Meldebestand erreicht oder unterschritten hat.
  bool get needsReorder => minStock > 0 && currentStock <= minStock;

  /// Bestand ist 0 oder negativ.
  bool get isOutOfStock => currentStock <= 0;

  /// Vorgeschlagene Nachbestellmenge: explizit gesetzt, sonst Differenz bis
  /// zum doppelten Meldebestand (Mindestmenge 1).
  int get suggestedReorderQuantity {
    if (reorderQuantity != null && reorderQuantity! > 0) {
      return reorderQuantity!;
    }
    if (minStock <= 0) {
      return 1;
    }
    final target = minStock * 2;
    final delta = target - currentStock;
    return delta > 0 ? delta : 1;
  }

  factory Product.fromFirestore(String id, Map<String, dynamic> map) {
    return Product(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      name: (map['name'] ?? '').toString(),
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      category: map['category'] as String?,
      unit: (map['unit'] ?? defaultUnit).toString().trim().isEmpty
          ? defaultUnit
          : (map['unit'] ?? defaultUnit).toString(),
      supplierId: map['supplierId'] as String?,
      supplierName: map['supplierName'] as String?,
      purchasePriceCents: parse.toInt(map['purchasePriceCents']),
      sellingPriceCents: parse.toInt(map['sellingPriceCents']),
      currentStock: parse.toInt(map['currentStock']) ?? 0,
      minStock: parse.toInt(map['minStock']) ?? 0,
      reorderQuantity: parse.toInt(map['reorderQuantity']),
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      name: (map['name'] ?? '').toString(),
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      category: map['category'] as String?,
      unit: (map['unit'] ?? defaultUnit).toString().trim().isEmpty
          ? defaultUnit
          : (map['unit'] ?? defaultUnit).toString(),
      supplierId: map['supplier_id'] as String?,
      supplierName: map['supplier_name'] as String?,
      purchasePriceCents: parse.toInt(map['purchase_price_cents']),
      sellingPriceCents: parse.toInt(map['selling_price_cents']),
      currentStock: parse.toInt(map['current_stock']) ?? 0,
      minStock: parse.toInt(map['min_stock']) ?? 0,
      reorderQuantity: parse.toInt(map['reorder_quantity']),
      isActive: parse.toBool(map['is_active']) ?? true,
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
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'sku': _trimmedOrNull(sku),
      'barcode': _trimmedOrNull(barcode),
      'category': _trimmedOrNull(category),
      'unit': unit.trim().isEmpty ? defaultUnit : unit.trim(),
      'supplierId': _trimmedOrNull(supplierId),
      'supplierName': _trimmedOrNull(supplierName),
      'purchasePriceCents': purchasePriceCents,
      'sellingPriceCents': sellingPriceCents,
      'currentStock': currentStock,
      'minStock': minStock,
      'reorderQuantity': reorderQuantity,
      'isActive': isActive,
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
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'category': category,
      'unit': unit,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_price_cents': purchasePriceCents,
      'selling_price_cents': sellingPriceCents,
      'current_stock': currentStock,
      'min_stock': minStock,
      'reorder_quantity': reorderQuantity,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Product copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    String? name,
    String? sku,
    String? barcode,
    String? category,
    String? unit,
    String? supplierId,
    String? supplierName,
    int? purchasePriceCents,
    int? sellingPriceCents,
    int? currentStock,
    int? minStock,
    int? reorderQuantity,
    bool? isActive,
    bool clearSiteName = false,
    bool clearSku = false,
    bool clearBarcode = false,
    bool clearCategory = false,
    bool clearSupplier = false,
    bool clearPurchasePrice = false,
    bool clearSellingPrice = false,
    bool clearReorderQuantity = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      category: clearCategory ? null : (category ?? this.category),
      unit: unit ?? this.unit,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      purchasePriceCents: clearPurchasePrice
          ? null
          : (purchasePriceCents ?? this.purchasePriceCents),
      sellingPriceCents: clearSellingPrice
          ? null
          : (sellingPriceCents ?? this.sellingPriceCents),
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      reorderQuantity: clearReorderQuantity
          ? null
          : (reorderQuantity ?? this.reorderQuantity),
      isActive: isActive ?? this.isActive,
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
