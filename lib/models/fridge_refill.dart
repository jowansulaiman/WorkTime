import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Eine Position der Kühlschrank-Nachfüllliste (eingebettet, kein eigenes
/// Dokument).
///
/// Spiegelt das Muster von `OrderListItem` (Bestellkorb), ist aber bewusst eine
/// **Checkliste statt einer Bestellung**:
/// - Jede Position trägt eine eigene stabile [id], weil sie auch **freier Text**
///   sein kann ([productId] == null) und dann nicht über die Artikel-Id
///   adressierbar wäre.
/// - [done] markiert „aus dem Lager geholt und in den Kühlschrank nachgefüllt"
///   (abgehakt).
///
/// Felder wie [name]/[unit]/[category] sind beim Hinzufügen aus dem Artikel
/// **denormalisiert**, damit die Liste auch offline lesbar bleibt.
class FridgeRefillItem {
  const FridgeRefillItem({
    required this.id,
    this.productId,
    required this.name,
    this.category,
    this.unit = 'Stück',
    this.quantity = 1,
    this.note,
    this.done = false,
    this.addedByUid,
    this.addedByName,
    this.addedAt,
  });

  /// Stabile Positions-Id (für freitext- wie artikelbasierte Einträge).
  final String id;

  /// Verknüpfter Artikel oder `null` für eine frei eingetippte Position.
  final String? productId;
  final String name;
  final String? category;
  final String unit;
  final int quantity;

  /// Optionale Notiz ("fast leer", "untere Reihe" ...).
  final String? note;

  /// Abgehakt: aus dem Lager geholt und in den Kühlschrank nachgefüllt.
  final bool done;

  /// Mitarbeiter, der die Position auf die Liste gesetzt hat (denormalisiert).
  final String? addedByUid;
  final String? addedByName;
  final DateTime? addedAt;

  bool get isFreeText => productId == null || productId!.trim().isEmpty;

  factory FridgeRefillItem.fromMap(Map<String, dynamic> map) {
    return FridgeRefillItem(
      id: (map['id'] ?? '').toString(),
      productId: (map['productId'] ?? map['product_id']) as String?,
      name: (map['name'] ?? '').toString(),
      category: map['category'] as String?,
      unit: (map['unit'] ?? 'Stück').toString().trim().isEmpty
          ? 'Stück'
          : (map['unit'] ?? 'Stück').toString(),
      quantity: parse.toInt(map['quantity']) ?? 1,
      note: map['note'] as String?,
      done: parse.toBool(map['done']) ?? false,
      addedByUid: (map['addedByUid'] ?? map['added_by_uid']) as String?,
      addedByName: (map['addedByName'] ?? map['added_by_name']) as String?,
      // camelCase (Firestore-Timestamp) zuerst, sonst snake_case (ISO-String).
      addedAt: FirestoreDateParser.readDate(map['addedAt']) ??
          FirestoreDateParser.readLocalDate(map['added_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'productId': _trimmedOrNull(productId),
      'name': name.trim(),
      'category': _trimmedOrNull(category),
      'unit': unit.trim().isEmpty ? 'Stück' : unit.trim(),
      'quantity': quantity,
      'note': _trimmedOrNull(note),
      'done': done,
      'addedByUid': addedByUid,
      'addedByName': _trimmedOrNull(addedByName),
      // In einem Array-Element ist FieldValue.serverTimestamp() unzulässig ->
      // konkreter Timestamp.
      'addedAt': addedAt == null ? null : Timestamp.fromDate(addedAt!),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'name': name,
      'category': category,
      'unit': unit,
      'quantity': quantity,
      'note': note,
      'done': done,
      'added_by_uid': addedByUid,
      'added_by_name': addedByName,
      'added_at': addedAt?.toIso8601String(),
    };
  }

  FridgeRefillItem copyWith({
    String? id,
    String? productId,
    String? name,
    String? category,
    String? unit,
    int? quantity,
    String? note,
    bool? done,
    String? addedByUid,
    String? addedByName,
    DateTime? addedAt,
    bool clearProduct = false,
    bool clearCategory = false,
    bool clearNote = false,
  }) {
    return FridgeRefillItem(
      id: id ?? this.id,
      productId: clearProduct ? null : (productId ?? this.productId),
      name: name ?? this.name,
      category: clearCategory ? null : (category ?? this.category),
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      note: clearNote ? null : (note ?? this.note),
      done: done ?? this.done,
      addedByUid: addedByUid ?? this.addedByUid,
      addedByName: addedByName ?? this.addedByName,
      addedAt: addedAt ?? this.addedAt,
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

/// Die Kühlschrank-Nachfüllliste eines Ladens – **genau ein Dokument pro Laden**
/// (Doc-ID = [siteId], Singleton). Trägt die eingebetteten [items]. Wird in der
/// Collection `fridgeRefillLists` gespeichert. Spiegelt das Muster von
/// `SiteOrderList` (Bestellkorb), ist aber eine reine Nachfüll-Checkliste
/// („was muss ich aus dem Lager in den Kühlschrank holen?").
class FridgeRefillList {
  const FridgeRefillList({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
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
  final List<FridgeRefillItem> items;
  final String? updatedByUid;
  final DateTime? updatedAt;

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.length;

  /// Noch nachzufüllende (nicht abgehakte) Positionen.
  int get openCount => items.where((item) => !item.done).length;
  int get doneCount => items.where((item) => item.done).length;

  FridgeRefillItem? itemById(String id) {
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  /// Offene (nicht abgehakte) Position zu einem Artikel – Grundlage der
  /// Merge-Logik („Sorte steht schon auf der Liste → Menge erhöhen statt
  /// doppeln").
  FridgeRefillItem? openItemForProduct(String? productId) {
    if (productId == null || productId.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (!item.done && item.productId == productId) {
        return item;
      }
    }
    return null;
  }

  factory FridgeRefillList.fromFirestore(String id, Map<String, dynamic> map) {
    return FridgeRefillList(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? id).toString(),
      siteName: map['siteName'] as String?,
      items: _itemsFromList(map['items']),
      updatedByUid: map['updatedByUid'] as String?,
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory FridgeRefillList.fromMap(Map<String, dynamic> map) {
    return FridgeRefillList(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
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
      'items': items.map((item) => item.toMap()).toList(),
      'updated_by_uid': updatedByUid,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  FridgeRefillList copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    List<FridgeRefillItem>? items,
    String? updatedByUid,
    DateTime? updatedAt,
    bool clearSiteName = false,
  }) {
    return FridgeRefillList(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      items: items ?? this.items,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<FridgeRefillItem> _itemsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => FridgeRefillItem.fromMap(item.cast<String, dynamic>()))
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
