import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer Bestandsbewegung.
enum StockMovementType {
  /// Wareneingang aus einer Bestellung oder manuell.
  receipt,

  /// Abgang (z.B. Verkauf, Schwund).
  issue,

  /// Manuelle Korrektur.
  adjustment,

  /// Inventur / Bestandsaufnahme.
  stocktake,

  /// Umlagerung zwischen zwei Standorten (gepaart: Abgang @A + Eingang @B).
  transfer,

  /// Nachfuellen des Verkaufs-Kuehlschranks aus dem Lager. Rein informativ —
  /// aendert den Gesamtbestand (currentStock) NICHT, nur Product.fridgeStock.
  /// Darf nicht in Schwund/Warenwert/Velocity einfliessen.
  fridgeRefill,
}

extension StockMovementTypeX on StockMovementType {
  String get value => switch (this) {
        StockMovementType.receipt => 'receipt',
        StockMovementType.issue => 'issue',
        StockMovementType.adjustment => 'adjustment',
        StockMovementType.stocktake => 'stocktake',
        StockMovementType.transfer => 'transfer',
        StockMovementType.fridgeRefill => 'fridge_refill',
      };

  String get label => switch (this) {
        StockMovementType.receipt => 'Wareneingang',
        StockMovementType.issue => 'Abgang',
        StockMovementType.adjustment => 'Korrektur',
        StockMovementType.stocktake => 'Inventur',
        StockMovementType.transfer => 'Umlagerung',
        StockMovementType.fridgeRefill => 'Kühlschrank nachgefüllt',
      };

  static StockMovementType fromValue(String? value) => switch (value) {
        'receipt' => StockMovementType.receipt,
        'issue' => StockMovementType.issue,
        'stocktake' => StockMovementType.stocktake,
        'transfer' => StockMovementType.transfer,
        'fridge_refill' => StockMovementType.fridgeRefill,
        _ => StockMovementType.adjustment,
      };
}

/// Eine einzelne Bestandsbewegung eines Artikels.
class StockMovement {
  const StockMovement({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.productId,
    this.productName,
    required this.type,
    required this.quantityDelta,
    this.balanceAfter,
    this.reason,
    this.relatedOrderId,
    this.source,
    this.externalRef,
    this.createdByUid,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String productId;
  final String? productName;
  final StockMovementType type;

  /// Mengenaenderung (positiv = Zugang, negativ = Abgang).
  final int quantityDelta;

  /// Bestand nach der Buchung (Snapshot, optional).
  final int? balanceAfter;
  final String? reason;
  final String? relatedOrderId;

  /// Herkunft der Buchung. `null`/`'manual'` = in der App erzeugt, `'oktopos'` =
  /// aus einer Kassen-Verkaufsbuchung übernommen (serverseitig per Cloud
  /// Function, umgeht die Client-Rules). Client-seitige Writes dürfen `source`
  /// NICHT auf `'oktopos'` setzen (Rules-Constraint, gegen Audit-Spoofing).
  final String? source;

  /// Externe Referenz der Quelle, z.B. die OktoPOS-Belegnummer
  /// (`Transaction.referenceNumber`). Macht eine importierte Bewegung im Beleg
  /// nachvollziehbar; zusammen mit der deterministischen Doc-ID Idempotenz-Anker.
  final String? externalRef;

  final String? createdByUid;
  final DateTime? createdAt;

  /// True, wenn die Bewegung aus dem Kassensystem (OktoPOS) übernommen wurde.
  bool get isFromPos => source == 'oktopos';

  // Tolerante Parser (Repo-Regel „Parser nie hart casten"): Bewegungen sind
  // ein org-weit gestreamtes Audit-Log mit fuer alle Aktiven offenem
  // fridge_refill-Create-Pfad — EIN hart gecastetes Poison-Doc wuerde sonst
  // alle Bewegungs-Reads der Org crashen. String-Felder via ?.toString().
  factory StockMovement.fromFirestore(String id, Map<String, dynamic> map) {
    return StockMovement(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      productId: (map['productId'] ?? '').toString(),
      productName: map['productName']?.toString(),
      type: StockMovementTypeX.fromValue(map['type']?.toString()),
      quantityDelta: parse.toInt(map['quantityDelta']) ?? 0,
      balanceAfter: parse.toInt(map['balanceAfter']),
      reason: map['reason']?.toString(),
      relatedOrderId: map['relatedOrderId']?.toString(),
      source: map['source']?.toString(),
      externalRef: map['externalRef']?.toString(),
      createdByUid: map['createdByUid']?.toString(),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      productId: (map['product_id'] ?? '').toString(),
      productName: map['product_name']?.toString(),
      type: StockMovementTypeX.fromValue(map['type']?.toString()),
      quantityDelta: parse.toInt(map['quantity_delta']) ?? 0,
      balanceAfter: parse.toInt(map['balance_after']),
      reason: map['reason']?.toString(),
      relatedOrderId: map['related_order_id']?.toString(),
      source: map['source']?.toString(),
      externalRef: map['external_ref']?.toString(),
      createdByUid: map['created_by_uid']?.toString(),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'productId': productId,
      'productName': _trimmedOrNull(productName),
      'type': type.value,
      'quantityDelta': quantityDelta,
      'balanceAfter': balanceAfter,
      'reason': _trimmedOrNull(reason),
      'relatedOrderId': _trimmedOrNull(relatedOrderId),
      'source': _trimmedOrNull(source),
      'externalRef': _trimmedOrNull(externalRef),
      'createdByUid': createdByUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'product_id': productId,
      'product_name': productName,
      'type': type.value,
      'quantity_delta': quantityDelta,
      'balance_after': balanceAfter,
      'reason': reason,
      'related_order_id': relatedOrderId,
      'source': source,
      'external_ref': externalRef,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  StockMovement copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? productId,
    String? productName,
    StockMovementType? type,
    int? quantityDelta,
    int? balanceAfter,
    String? reason,
    String? relatedOrderId,
    String? source,
    String? externalRef,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return StockMovement(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      quantityDelta: quantityDelta ?? this.quantityDelta,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      reason: reason ?? this.reason,
      relatedOrderId: relatedOrderId ?? this.relatedOrderId,
      source: source ?? this.source,
      externalRef: externalRef ?? this.externalRef,
      createdByUid: createdByUid ?? this.createdByUid,
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
