import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Welcher Preis geaendert wurde.
enum PriceField {
  /// Einkaufspreis (EK).
  purchase,

  /// Verkaufspreis (VK).
  selling,
}

extension PriceFieldX on PriceField {
  String get value => switch (this) {
        PriceField.purchase => 'purchase',
        PriceField.selling => 'selling',
      };

  String get label => switch (this) {
        PriceField.purchase => 'Einkaufspreis',
        PriceField.selling => 'Verkaufspreis',
      };

  static PriceField fromValue(String? value) => switch (value) {
        'purchase' => PriceField.purchase,
        _ => PriceField.selling,
      };
}

/// Unveraenderlicher Audit-Eintrag fuer eine Preisaenderung eines Artikels.
///
/// Liegt als eigene Subcollection unter dem Produkt
/// (`organizations/{orgId}/products/{productId}/priceHistory`) — bewusst NICHT
/// als StockMovement (Bewegung = Menge, nicht Preis). Voll dual serialisiert
/// (camelCase/Timestamp fuer Firestore, snake_case/ISO fuer lokal).
class PriceHistoryEntry {
  const PriceHistoryEntry({
    this.id,
    required this.orgId,
    required this.productId,
    required this.field,
    this.oldCents,
    this.newCents,
    this.changedByUid,
    this.changedAt,
  });

  final String? id;
  final String orgId;
  final String productId;
  final PriceField field;

  /// Alter Preis in Cent (null = vorher kein Preis gesetzt).
  final int? oldCents;

  /// Neuer Preis in Cent (null = Preis entfernt).
  final int? newCents;
  final String? changedByUid;
  final DateTime? changedAt;

  factory PriceHistoryEntry.fromFirestore(String id, Map<String, dynamic> map) {
    return PriceHistoryEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      productId: (map['productId'] ?? '').toString(),
      field: PriceFieldX.fromValue(map['field']?.toString()),
      oldCents: parse.toInt(map['oldCents']),
      newCents: parse.toInt(map['newCents']),
      changedByUid: map['changedByUid'] as String?,
      changedAt: FirestoreDateParser.readDate(map['changedAt']),
    );
  }

  factory PriceHistoryEntry.fromMap(Map<String, dynamic> map) {
    return PriceHistoryEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      productId: (map['product_id'] ?? '').toString(),
      field: PriceFieldX.fromValue(map['field']?.toString()),
      oldCents: parse.toInt(map['old_cents']),
      newCents: parse.toInt(map['new_cents']),
      changedByUid: map['changed_by_uid'] as String?,
      changedAt: FirestoreDateParser.readLocalDate(map['changed_at']),
    );
  }

  /// camelCase + serverTimestamp — fuer direkte Firestore-Writes. Feld-Allowlist
  /// in firestore.rules haengt exakt an diesen Keys.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'productId': productId,
      'field': field.value,
      'oldCents': oldCents,
      'newCents': newCents,
      'changedByUid': changedByUid,
      'changedAt': FieldValue.serverTimestamp(),
    };
  }

  /// snake_case + ISO — fuer SharedPreferences (lokal).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'product_id': productId,
      'field': field.value,
      'old_cents': oldCents,
      'new_cents': newCents,
      'changed_by_uid': changedByUid,
      'changed_at': changedAt?.toIso8601String(),
    };
  }

  PriceHistoryEntry copyWith({
    String? id,
    String? orgId,
    String? productId,
    PriceField? field,
    int? oldCents,
    int? newCents,
    String? changedByUid,
    DateTime? changedAt,
  }) {
    return PriceHistoryEntry(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      productId: productId ?? this.productId,
      field: field ?? this.field,
      oldCents: oldCents ?? this.oldCents,
      newCents: newCents ?? this.newCents,
      changedByUid: changedByUid ?? this.changedByUid,
      changedAt: changedAt ?? this.changedAt,
    );
  }
}
