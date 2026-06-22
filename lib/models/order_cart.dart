import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Bestellliste je Laden.
///
/// - [cart]: der geteilte **Bestellkorb**, den jeder aktive Mitarbeiter über die
///   Woche füllt ("Sorte ist leer → mit Menge in den Korb"). Der Admin löst ihn
///   als echte Bestellung(en) je Lieferant aus und leert ihn danach.
/// - [weeklyTemplate]: die **Standard-Wochenliste** (Manager-kuratiert) – die
///   Sachen, die immer bestellt werden. Sie füllt den Korb auf Knopfdruck vor.
enum OrderListKind {
  cart,
  weeklyTemplate,
}

extension OrderListKindX on OrderListKind {
  String get value => switch (this) {
        OrderListKind.cart => 'cart',
        OrderListKind.weeklyTemplate => 'weekly_template',
      };

  String get label => switch (this) {
        OrderListKind.cart => 'Bestellkorb',
        OrderListKind.weeklyTemplate => 'Standard-Wochenliste',
      };

  static OrderListKind fromValue(String? value) => switch (value) {
        'weekly_template' => OrderListKind.weeklyTemplate,
        _ => OrderListKind.cart,
      };
}

/// Eine Position einer Bestellliste (eingebettet, kein eigenes Dokument).
///
/// Spiegelt das Muster von `CustomerOrderItem`. Felder wie [name]/[unit]/
/// [category]/[supplierName] sind beim Hinzufügen aus dem Artikel
/// **denormalisiert**, damit der Korb auch offline lesbar bleibt; der Preis wird
/// bewusst NICHT gespeichert, sondern erst beim Checkout aus dem Live-Artikel
/// (`Product.purchasePriceCents`) gezogen.
class OrderListItem {
  const OrderListItem({
    this.productId,
    required this.name,
    this.sku,
    this.category,
    this.unit = 'Stück',
    required this.quantity,
    this.supplierId,
    this.supplierName,
    this.addedByUid,
    this.note,
  });

  final String? productId;
  final String name;
  final String? sku;
  final String? category;
  final String unit;
  final int quantity;

  /// Standard-Lieferant des Artikels (denormalisiert) – Grundlage der Gruppierung
  /// beim Checkout (eine Bestellung je Lieferant).
  final String? supplierId;
  final String? supplierName;

  /// Mitarbeiter, der die Position zuletzt in die Liste gelegt hat.
  final String? addedByUid;

  /// Optionale Notiz ("fast leer", "andere Marke ok" ...).
  final String? note;

  factory OrderListItem.fromMap(Map<String, dynamic> map) {
    return OrderListItem(
      productId: (map['productId'] ?? map['product_id']) as String?,
      name: (map['name'] ?? '').toString(),
      sku: map['sku'] as String?,
      category: map['category'] as String?,
      unit: (map['unit'] ?? 'Stück').toString().trim().isEmpty
          ? 'Stück'
          : (map['unit'] ?? 'Stück').toString(),
      quantity: parse.toInt(map['quantity']) ?? 0,
      supplierId: (map['supplierId'] ?? map['supplier_id']) as String?,
      supplierName: (map['supplierName'] ?? map['supplier_name']) as String?,
      addedByUid: (map['addedByUid'] ?? map['added_by_uid']) as String?,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'name': name.trim(),
      'sku': _trimmedOrNull(sku),
      'category': _trimmedOrNull(category),
      'unit': unit.trim().isEmpty ? 'Stück' : unit.trim(),
      'quantity': quantity,
      'supplierId': _trimmedOrNull(supplierId),
      'supplierName': _trimmedOrNull(supplierName),
      'addedByUid': addedByUid,
      'note': _trimmedOrNull(note),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'name': name,
      'sku': sku,
      'category': category,
      'unit': unit,
      'quantity': quantity,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'added_by_uid': addedByUid,
      'note': note,
    };
  }

  OrderListItem copyWith({
    String? productId,
    String? name,
    String? sku,
    String? category,
    String? unit,
    int? quantity,
    String? supplierId,
    String? supplierName,
    String? addedByUid,
    String? note,
    bool clearSku = false,
    bool clearCategory = false,
    bool clearSupplier = false,
    bool clearNote = false,
  }) {
    return OrderListItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      category: clearCategory ? null : (category ?? this.category),
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      addedByUid: addedByUid ?? this.addedByUid,
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

/// Eine Bestellliste eines Ladens – **genau ein Dokument pro Laden und [kind]**
/// (Doc-ID = `siteId`). Trägt die eingebetteten [items]. Wird je nach [kind] in
/// der Collection `orderCarts` (Korb) bzw. `weeklyOrderLists` (Standard-Liste)
/// gespeichert.
class SiteOrderList {
  const SiteOrderList({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    this.kind = OrderListKind.cart,
    this.items = const [],
    this.updatedByUid,
    this.updatedAt,
  });

  /// Doc-ID = [siteId] (Singleton je Laden). Bleibt für die lokale Round-Trip-
  /// Persistenz erhalten.
  final String? id;
  final String orgId;
  final String siteId;
  final String? siteName;
  final OrderListKind kind;
  final List<OrderListItem> items;
  final String? updatedByUid;
  final DateTime? updatedAt;

  bool get isEmpty => items.isEmpty;

  int get itemCount => items.length;

  int get totalQuantity =>
      items.fold(0, (total, item) => total + item.quantity);

  /// Position zu einem Artikel (oder `null`), für Merge-/Prefill-Logik.
  OrderListItem? itemForProduct(String? productId) {
    if (productId == null || productId.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.productId == productId) {
        return item;
      }
    }
    return null;
  }

  factory SiteOrderList.fromFirestore(String id, Map<String, dynamic> map) {
    return SiteOrderList(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? id).toString(),
      siteName: map['siteName'] as String?,
      kind: OrderListKindX.fromValue(map['kind']?.toString()),
      items: _itemsFromList(map['items']),
      updatedByUid: map['updatedByUid'] as String?,
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory SiteOrderList.fromMap(Map<String, dynamic> map) {
    return SiteOrderList(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      kind: OrderListKindX.fromValue(map['kind']?.toString()),
      items: _itemsFromList(map['items']),
      updatedByUid: map['updated_by_uid'] as String?,
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'siteName': _trimmedOrNull(siteName),
      'kind': kind.value,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
      'updatedByUid': updatedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'site_name': siteName,
      'kind': kind.value,
      'items': items.map((item) => item.toMap()).toList(),
      'updated_by_uid': updatedByUid,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  SiteOrderList copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    OrderListKind? kind,
    List<OrderListItem>? items,
    String? updatedByUid,
    DateTime? updatedAt,
    bool clearSiteName = false,
  }) {
    return SiteOrderList(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      kind: kind ?? this.kind,
      items: items ?? this.items,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<OrderListItem> _itemsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => OrderListItem.fromMap(item.cast<String, dynamic>()))
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
