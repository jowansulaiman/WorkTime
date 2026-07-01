import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Eine belegweite USt-Position (OktoPOS liefert den Satz NUR je Beleg, nicht je
/// Zeile). Einheit: ganze Prozent (`ratePercent`), Geld in Cent.
class ReceiptTax {
  const ReceiptTax({
    this.ratePercent,
    this.netCents,
    this.taxCents,
    this.grossCents,
  });

  final int? ratePercent;
  final int? netCents;
  final int? taxCents;
  final int? grossCents;

  factory ReceiptTax.fromFirestore(Map<String, dynamic> map) => ReceiptTax(
        ratePercent: parse.toInt(map['ratePercent']),
        netCents: parse.toInt(map['netCents']),
        taxCents: parse.toInt(map['taxCents']),
        grossCents: parse.toInt(map['grossCents']),
      );

  Map<String, dynamic> toFirestoreMap() => {
        'ratePercent': ratePercent,
        'netCents': netCents,
        'taxCents': taxCents,
        'grossCents': grossCents,
      };
}

/// Eine Zahlart-Position des Belegs (bar/Karte/...). Best-effort aus der Kasse
/// (gegen Swagger verifizieren); `method` ist ein Kleinbuchstaben-Token.
class PaymentLine {
  const PaymentLine({this.method, this.amountCents, this.subType});

  final String? method;
  final int? amountCents;
  final String? subType;

  factory PaymentLine.fromFirestore(Map<String, dynamic> map) => PaymentLine(
        method: map['method'] as String?,
        amountCents: parse.toInt(map['amountCents']),
        subType: map['subType'] as String?,
      );

  Map<String, dynamic> toFirestoreMap() => {
        'method': method,
        'amountCents': amountCents,
        'subType': subType,
      };
}

/// Eine Belegzeile, **denormalisiert zum Verkaufszeitpunkt** (Name/Kategorie/
/// Preis), damit ein später gelöschtes Produkt die Historie nicht verwaist.
class PosReceiptLine {
  const PosReceiptLine({
    this.productId,
    this.name,
    this.externalReference,
    this.scannedBarcode,
    this.category,
    this.quantity = 0,
    this.unitPriceCents,
    this.discountCents,
  });

  /// Gematchtes WorkTime-Produkt (`null` = beim Sync nicht zugeordnet).
  final String? productId;
  final String? name;
  final String? externalReference;
  final String? scannedBarcode;
  final String? category;
  final int quantity;
  final int? unitPriceCents;
  final int? discountCents;

  /// Realisierter Stückpreis (Verkaufspreis − Rabatt) in Cent, `null` falls der
  /// Verkaufspreis nicht aus der Kasse kam.
  int? get realizedUnitPriceCents =>
      unitPriceCents == null ? null : unitPriceCents! - (discountCents ?? 0);

  factory PosReceiptLine.fromFirestore(Map<String, dynamic> map) =>
      PosReceiptLine(
        productId: map['productId'] as String?,
        name: map['name'] as String?,
        externalReference: map['externalReference'] as String?,
        scannedBarcode: map['scannedBarcode'] as String?,
        category: map['category'] as String?,
        quantity: parse.toInt(map['quantity']) ?? 0,
        unitPriceCents: parse.toInt(map['unitPriceCents']),
        discountCents: parse.toInt(map['discountCents']),
      );

  Map<String, dynamic> toFirestoreMap() => {
        'productId': productId,
        'name': name,
        'externalReference': externalReference,
        'scannedBarcode': scannedBarcode,
        'category': category,
        'quantity': quantity,
        'unitPriceCents': unitPriceCents,
        'discountCents': discountCents,
      };
}

/// **Verkaufsfaktum (P0).** Aus der Kasse übernommener Beleg mit eingebetteten
/// Zeilen + belegweiter USt. **Cloud-only** (read-only Stream; serverseitig von
/// der Cloud Function geschrieben, kein lokaler/Hybrid-Cache, keine PII-
/// Spiegelung) — daher nur die Firestore-Serialisierung (camelCase), keine
/// snake_case/`toMap`-Form wie bei lokal persistierten Modellen.
class PosReceipt {
  const PosReceipt({
    this.id,
    required this.orgId,
    required this.siteId,
    this.cashRegisterId,
    required this.referenceNumber,
    this.type,
    this.training = false,
    this.isRevenue = false,
    this.businessDay,
    this.transactionDate,
    this.grossCents,
    this.taxes = const [],
    this.payments = const [],
    this.lines = const [],
    this.cashierId,
    this.customerId,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final int? cashRegisterId;
  final String referenceNumber;

  /// `sales` | `refund` | `cash` | sonstiges (kleingeschrieben).
  final String? type;

  /// Trainings-/Schulungsbeleg — aus allen Umsatz-Aggregaten ausschließen.
  final bool training;

  /// Echter Umsatzbeleg (`sales`/`refund`, kein training) — Aggregate filtern
  /// hierauf (cash/training tragen keinen Umsatz/keine Marge).
  final bool isRevenue;

  final String? businessDay;
  final DateTime? transactionDate;

  /// Bruttobetrag des Belegs (best-effort aus der Kasse; gegen Swagger prüfen).
  final int? grossCents;

  final List<ReceiptTax> taxes;

  /// Zahlart-Aufschlüsselung (bar/Karte/...) — Basis des Zahlart-Splits (P2.0).
  final List<PaymentLine> payments;

  final List<PosReceiptLine> lines;

  final String? cashierId;
  final String? customerId;

  factory PosReceipt.fromFirestore(String id, Map<String, dynamic> map) {
    return PosReceipt(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      cashRegisterId: parse.toInt(map['cashRegisterId']),
      referenceNumber: (map['referenceNumber'] ?? '').toString(),
      type: map['type'] as String?,
      training: parse.toBool(map['training']) ?? false,
      isRevenue: parse.toBool(map['isRevenue']) ?? false,
      businessDay: map['businessDay'] as String?,
      transactionDate: FirestoreDateParser.readDate(map['transactionDate']),
      grossCents: parse.toInt(map['grossCents']),
      taxes: _readList(map['taxes'], ReceiptTax.fromFirestore),
      payments: _readList(map['payments'], PaymentLine.fromFirestore),
      lines: _readList(map['lines'], PosReceiptLine.fromFirestore),
      cashierId: map['cashierId'] as String?,
      customerId: map['customerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'siteId': siteId,
        'cashRegisterId': cashRegisterId,
        'referenceNumber': referenceNumber,
        'type': type,
        'training': training,
        'isRevenue': isRevenue,
        'businessDay': businessDay,
        'transactionDate':
            transactionDate == null ? null : Timestamp.fromDate(transactionDate!),
        'grossCents': grossCents,
        'taxes': taxes.map((t) => t.toFirestoreMap()).toList(),
        'payments': payments.map((p) => p.toFirestoreMap()).toList(),
        'lines': lines.map((l) => l.toFirestoreMap()).toList(),
        'cashierId': cashierId,
        'customerId': customerId,
        'source': 'oktopos',
      };

  static List<T> _readList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
