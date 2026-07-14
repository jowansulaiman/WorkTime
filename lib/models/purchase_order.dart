import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Status einer Bestellung.
/// **WW-3:** Tages-Status des erwarteten Liefertermins (für die Badges/Filter
/// in der Warenwirtschaft). [none] = kein offener Termin.
enum ExpectedDeliveryDayState { none, overdue, today, upcoming }

enum PurchaseOrderStatus {
  /// Entwurf, noch nicht beim Lieferanten bestellt.
  draft,

  /// Bestellung wurde abgeschickt.
  ordered,

  /// Teilweise geliefert.
  partiallyReceived,

  /// Vollstaendig geliefert.
  received,

  /// Storniert.
  cancelled,
}

extension PurchaseOrderStatusX on PurchaseOrderStatus {
  String get value => switch (this) {
        PurchaseOrderStatus.draft => 'draft',
        PurchaseOrderStatus.ordered => 'ordered',
        PurchaseOrderStatus.partiallyReceived => 'partially_received',
        PurchaseOrderStatus.received => 'received',
        PurchaseOrderStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        PurchaseOrderStatus.draft => 'Entwurf',
        PurchaseOrderStatus.ordered => 'Bestellt',
        PurchaseOrderStatus.partiallyReceived => 'Teillieferung',
        PurchaseOrderStatus.received => 'Geliefert',
        PurchaseOrderStatus.cancelled => 'Storniert',
      };

  /// Bestellung ist abgeschlossen (geliefert oder storniert).
  bool get isClosed =>
      this == PurchaseOrderStatus.received ||
      this == PurchaseOrderStatus.cancelled;

  /// Wareneingang kann gebucht werden.
  bool get acceptsReceipt =>
      this == PurchaseOrderStatus.ordered ||
      this == PurchaseOrderStatus.partiallyReceived;

  static PurchaseOrderStatus fromValue(String? value) => switch (value) {
        'ordered' => PurchaseOrderStatus.ordered,
        'partially_received' => PurchaseOrderStatus.partiallyReceived,
        'received' => PurchaseOrderStatus.received,
        'cancelled' => PurchaseOrderStatus.cancelled,
        _ => PurchaseOrderStatus.draft,
      };
}

/// **WW-6:** Übergabetyp für den geführten Wareneingang gegen eine Bestellung.
///
/// Reines DTO (NICHT persistiert): trägt pro Bestellposition die zusätzlich
/// gelieferte Menge und – optional – den tatsächlichen Ist-Einkaufspreis, das
/// Mindesthaltbarkeitsdatum und eine Chargen-/Losnummer. Die Buchung
/// (`receivePurchaseOrder` + Chargen-/Preis-Nachlauf) macht der Provider.
class PurchaseReceiptLine {
  const PurchaseReceiptLine({
    required this.quantity,
    this.receivedUnitPriceCents,
    this.expiryDate,
    this.batchNote,
    this.allowOverdelivery = false,
  });

  /// Zusätzlich gelieferte Menge (wird beim Buchen auf den offenen Rest geklemmt
  /// — außer bei [allowOverdelivery]).
  final int quantity;

  /// **WW-7:** erlaubt eine Mehrlieferung über die offene Menge hinaus (nur die
  /// untere Schranke 0 greift). Der geteilte Clamp [effectiveReceiptQuantity]
  /// wertet dieses Flag an BEIDEN Buchungsstellen (Cloud-Repo + lokaler Spiegel)
  /// aus — beendet die frühere Clamp-Divergenz-Gefahr strukturell.
  final bool allowOverdelivery;

  /// Tatsächlicher Einkaufspreis der Lieferung in Cent (Ist-EK). `null` = kein
  /// abweichender Preis erfasst (dann bleibt der bestellte Preis maßgeblich).
  final int? receivedUnitPriceCents;

  /// Mindesthaltbarkeitsdatum der Lieferung (optional — nur Ware mit MHD).
  final DateTime? expiryDate;

  /// Chargen-/Losnummer (optional, landet in `ProductBatch.note`).
  final String? batchNote;

  /// Ob aus dieser Position eine Warencharge angelegt wird (nur mit MHD — eine
  /// Charge ohne MHD ist nicht speicherbar, analog `showGoodsReceiptSheet`).
  bool get hasBatch => expiryDate != null;
}

/// **WW-7 — der EINE Clamp für den Wareneingang.** Bestimmt die effektiv zu
/// buchende Eingangsmenge aus [line] gegen die Position [item].
///
/// Früher klemmte JEDE Buchungsstelle (Cloud-Repo + lokaler Spiegel) die Menge
/// selbst per `line.quantity.clamp(0, item.outstandingQuantity)` — zwei Kopien
/// derselben Regel, die auseinanderlaufen konnten. Dieser reine Helfer ist die
/// gemeinsame Quelle für BEIDE Stellen.
///
/// - Ohne [PurchaseReceiptLine.allowOverdelivery]: geklemmt auf `[0, offen]`
///   (Standard — keine Überlieferung, keine Negativmenge).
/// - Mit [PurchaseReceiptLine.allowOverdelivery]: nur untere Schranke 0 — eine
///   bewusst erfasste Mehrlieferung über den offenen Rest hinaus wird gebucht
///   (führt zu `quantityReceived > quantityOrdered`, was das
///   Abweichungsprotokoll ausweist).
int effectiveReceiptQuantity(PurchaseReceiptLine line, PurchaseOrderItem item) {
  if (line.quantity <= 0) return 0;
  if (line.allowOverdelivery) return line.quantity;
  return line.quantity.clamp(0, item.outstandingQuantity);
}

/// Eine Position innerhalb einer Bestellung (eingebettet, kein eigenes Dokument).
class PurchaseOrderItem {
  const PurchaseOrderItem({
    this.productId,
    required this.name,
    this.sku,
    this.unit = 'Stück',
    required this.quantityOrdered,
    this.quantityReceived = 0,
    this.unitPriceCents,
    this.receivedUnitPriceCents,
    this.taxRatePercent,
  });

  final String? productId;
  final String name;
  final String? sku;
  final String unit;
  final int quantityOrdered;
  final int quantityReceived;

  /// Einzelpreis in Cent — als **Netto**-Einkaufspreis interpretiert
  /// (B2B-Konvention: Lieferantenrechnungen weisen netto + USt getrennt aus).
  final int? unitPriceCents;

  /// **WW-6:** Tatsächlich gelieferter Einkaufspreis (Ist-EK) in Cent, beim
  /// Wareneingang erfasst. `null` = kein abweichender Preis erfasst. Der
  /// Wareneinsatz ([deliveredTotalCents]) bevorzugt diesen vor [unitPriceCents].
  final int? receivedUnitPriceCents;

  /// **Kassen-Modul M6 — USt-Satz der Position** in ganzen Prozent (7/19),
  /// `null` = ohne ausgewiesene Steuer (dann netto = brutto). Macht die
  /// Käufe-Auswertung echt netto/brutto statt eines Netto-Richtwerts (§8a).
  final int? taxRatePercent;

  /// Noch offene (nicht gelieferte) Menge.
  int get outstandingQuantity {
    final delta = quantityOrdered - quantityReceived;
    return delta > 0 ? delta : 0;
  }

  bool get isFullyReceived => quantityReceived >= quantityOrdered;

  /// Positionssumme (Netto) in Cent (bestellte Menge * Einzelpreis).
  int get lineTotalCents {
    final price = unitPriceCents;
    if (price == null) {
      return 0;
    }
    return price * quantityOrdered;
  }

  /// Netto-Positionssumme in Cent. [priceIncludesVat] = Org-Schalter §3.4:
  /// ob der erfasste [unitPriceCents] MwSt enthält. `true` → aus dem
  /// Brutto-Preis herausrechnen; `false` (B2B-Default) → der Preis IST netto.
  /// Ohne USt-Satz gleich [lineTotalCents].
  int lineNetCents({required bool priceIncludesVat}) {
    final rate = taxRatePercent;
    if (rate == null || rate <= 0) return lineTotalCents;
    return priceIncludesVat
        ? (lineTotalCents / (1 + rate / 100)).round()
        : lineTotalCents;
  }

  /// Brutto-Positionssumme in Cent (Netto + USt). Ohne USt-Satz gleich
  /// [lineTotalCents]. [priceIncludesVat] wie [lineNetCents].
  int lineGrossCents({required bool priceIncludesVat}) {
    final rate = taxRatePercent;
    if (rate == null || rate <= 0) return lineTotalCents;
    return priceIncludesVat
        ? lineTotalCents
        : (lineTotalCents * (1 + rate / 100)).round();
  }

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      productId: (map['productId'] ?? map['product_id']) as String?,
      name: (map['name'] ?? '').toString(),
      sku: (map['sku']) as String?,
      unit: (map['unit'] ?? 'Stück').toString().trim().isEmpty
          ? 'Stück'
          : (map['unit'] ?? 'Stück').toString(),
      quantityOrdered:
          parse.toInt(map['quantityOrdered'] ?? map['quantity_ordered']) ?? 0,
      quantityReceived:
          parse.toInt(map['quantityReceived'] ?? map['quantity_received']) ?? 0,
      unitPriceCents:
          parse.toInt(map['unitPriceCents'] ?? map['unit_price_cents']),
      receivedUnitPriceCents: parse.toInt(
          map['receivedUnitPriceCents'] ?? map['received_unit_price_cents']),
      taxRatePercent:
          parse.toInt(map['taxRatePercent'] ?? map['tax_rate_percent']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'name': name.trim(),
      'sku': _trimmedOrNull(sku),
      'unit': unit.trim().isEmpty ? 'Stück' : unit.trim(),
      'quantityOrdered': quantityOrdered,
      'quantityReceived': quantityReceived,
      'unitPriceCents': unitPriceCents,
      'receivedUnitPriceCents': receivedUnitPriceCents,
      'taxRatePercent': taxRatePercent,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'name': name,
      'sku': sku,
      'unit': unit,
      'quantity_ordered': quantityOrdered,
      'quantity_received': quantityReceived,
      'unit_price_cents': unitPriceCents,
      'received_unit_price_cents': receivedUnitPriceCents,
      'tax_rate_percent': taxRatePercent,
    };
  }

  PurchaseOrderItem copyWith({
    String? productId,
    String? name,
    String? sku,
    bool clearSku = false,
    String? unit,
    int? quantityOrdered,
    int? quantityReceived,
    int? unitPriceCents,
    bool clearUnitPrice = false,
    int? receivedUnitPriceCents,
    bool clearReceivedUnitPrice = false,
    int? taxRatePercent,
    bool clearTaxRate = false,
  }) {
    return PurchaseOrderItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      // clearSku-Flag analog zu CustomerOrderItem (CLAUDE.md copyWith/clearX-
      // Muster fuer nullable Felder, probleme #45).
      sku: clearSku ? null : (sku ?? this.sku),
      unit: unit ?? this.unit,
      quantityOrdered: quantityOrdered ?? this.quantityOrdered,
      quantityReceived: quantityReceived ?? this.quantityReceived,
      unitPriceCents:
          clearUnitPrice ? null : (unitPriceCents ?? this.unitPriceCents),
      receivedUnitPriceCents: clearReceivedUnitPrice
          ? null
          : (receivedUnitPriceCents ?? this.receivedUnitPriceCents),
      taxRatePercent:
          clearTaxRate ? null : (taxRatePercent ?? this.taxRatePercent),
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

/// Eine Bestellung an einen Lieferanten fuer einen Laden.
class PurchaseOrder {
  const PurchaseOrder({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    required this.supplierId,
    this.supplierName,
    this.orderNumber,
    this.status = PurchaseOrderStatus.draft,
    this.items = const [],
    this.notes,
    this.deliveryNoteNumber,
    this.orderedAt,
    this.expectedAt,
    this.receivedAt,
    this.closedAt,
    this.closedReason,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String? siteName;
  final String supplierId;
  final String? supplierName;

  /// Menschlich lesbare Bestellnummer (z.B. "BST-2026-0007").
  final String? orderNumber;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderItem> items;
  final String? notes;

  /// **WW-6:** Lieferschein-Nummer der zuletzt gebuchten Lieferung (optional,
  /// vom geführten Wareneingang erfasst).
  final String? deliveryNoteNumber;
  final DateTime? orderedAt;
  final DateTime? expectedAt;
  final DateTime? receivedAt;
  final DateTime? closedAt;
  final String? closedReason;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get itemCount => items.length;

  int get totalQuantityOrdered =>
      items.fold(0, (total, item) => total + item.quantityOrdered);

  int get totalQuantityReceived =>
      items.fold(0, (total, item) => total + item.quantityReceived);

  int get totalCents =>
      items.fold(0, (total, item) => total + item.lineTotalCents);

  /// Wert der tatsaechlich gelieferten Menge in Cent.
  ///
  /// **WW-6:** Bevorzugt den beim Wareneingang erfassten Ist-EK
  /// ([PurchaseOrderItem.receivedUnitPriceCents]), fällt sonst auf den
  /// bestellten [PurchaseOrderItem.unitPriceCents] zurück. Wie [totalCents]
  /// verwendet der Getter den Einzelpreis direkt; eine gegebenenfalls
  /// enthaltene USt wird hier nicht umgerechnet.
  int get deliveredTotalCents => items.fold(
        0,
        (total, item) =>
            total +
            (item.quantityReceived *
                (item.receivedUnitPriceCents ?? item.unitPriceCents ?? 0)),
      );

  /// Netto-Gesamtsumme in Cent. [priceIncludesVat] = Org-Schalter §3.4.
  int totalNetCents({required bool priceIncludesVat}) => items.fold(
      0, (total, item) => total + item.lineNetCents(priceIncludesVat: priceIncludesVat));

  /// Brutto-Gesamtsumme in Cent (netto + USt je Position).
  int totalGrossCents({required bool priceIncludesVat}) => items.fold(0,
      (total, item) => total + item.lineGrossCents(priceIncludesVat: priceIncludesVat));

  /// Ob mindestens eine Position einen USt-Satz trägt (dann weichen netto/
  /// brutto voneinander ab; schalter-unabhängig).
  bool get hasTaxRates => items.any((item) => (item.taxRatePercent ?? 0) > 0);

  bool get hasPrices => items.any((item) => item.unitPriceCents != null);

  bool get isFullyReceived =>
      items.isNotEmpty && items.every((item) => item.isFullyReceived);

  bool get hasAnyReceipt => items.any((item) => item.quantityReceived > 0);

  /// Leitet den Status aus den gelieferten Mengen ab (fuer den Wareneingang).
  /// Storno/Entwurf werden nicht automatisch ueberschrieben.
  PurchaseOrderStatus deriveReceiptStatus() {
    if (status == PurchaseOrderStatus.cancelled ||
        status == PurchaseOrderStatus.draft) {
      return status;
    }
    if (isFullyReceived) {
      return PurchaseOrderStatus.received;
    }
    if (hasAnyReceipt) {
      return PurchaseOrderStatus.partiallyReceived;
    }
    return PurchaseOrderStatus.ordered;
  }

  /// **WW-3:** Ob noch eine Lieferung erwartet wird — offener Status
  /// (`ordered`/`partiallyReceived`), nicht geschlossen, mit hinterlegtem
  /// [expectedAt].
  bool get isDeliveryPending =>
      closedAt == null &&
      expectedAt != null &&
      (status == PurchaseOrderStatus.ordered ||
          status == PurchaseOrderStatus.partiallyReceived);

  /// **WW-3:** Tages-Status des erwarteten Liefertermins relativ zu [today]
  /// (Kalendertag). Nur sinnvoll bei [isDeliveryPending]; sonst
  /// [ExpectedDeliveryDayState.none]. Pure — der Aufrufer reicht „heute" durch.
  ExpectedDeliveryDayState expectedDeliveryState(DateTime today) {
    if (!isDeliveryPending) return ExpectedDeliveryDayState.none;
    final due = DateTime(expectedAt!.year, expectedAt!.month, expectedAt!.day);
    final ref = DateTime(today.year, today.month, today.day);
    if (due.isBefore(ref)) return ExpectedDeliveryDayState.overdue;
    if (due.isAtSameMomentAs(ref)) return ExpectedDeliveryDayState.today;
    return ExpectedDeliveryDayState.upcoming;
  }

  factory PurchaseOrder.fromFirestore(String id, Map<String, dynamic> map) {
    return PurchaseOrder(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      supplierId: (map['supplierId'] ?? '').toString(),
      supplierName: map['supplierName'] as String?,
      orderNumber: map['orderNumber'] as String?,
      status: PurchaseOrderStatusX.fromValue(map['status']?.toString()),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      deliveryNoteNumber: map['deliveryNoteNumber'] as String?,
      orderedAt: FirestoreDateParser.readDate(map['orderedAt']),
      expectedAt: FirestoreDateParser.readDate(map['expectedAt']),
      receivedAt: FirestoreDateParser.readDate(map['receivedAt']),
      closedAt: FirestoreDateParser.readDate(map['closedAt']),
      closedReason: map['closedReason'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      supplierId: (map['supplier_id'] ?? '').toString(),
      supplierName: map['supplier_name'] as String?,
      orderNumber: map['order_number'] as String?,
      status: PurchaseOrderStatusX.fromValue(map['status']?.toString()),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      deliveryNoteNumber: map['delivery_note_number'] as String?,
      orderedAt: FirestoreDateParser.readLocalDate(map['ordered_at']),
      expectedAt: FirestoreDateParser.readLocalDate(map['expected_at']),
      receivedAt: FirestoreDateParser.readLocalDate(map['received_at']),
      closedAt: FirestoreDateParser.readLocalDate(map['closed_at']),
      closedReason: map['closed_reason'] as String?,
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
      'supplierId': supplierId,
      'supplierName': _trimmedOrNull(supplierName),
      'orderNumber': _trimmedOrNull(orderNumber),
      'status': status.value,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
      'totalCents': totalCents,
      'notes': _trimmedOrNull(notes),
      'deliveryNoteNumber': _trimmedOrNull(deliveryNoteNumber),
      'orderedAt': _timestampOrNull(orderedAt),
      'expectedAt': _timestampOrNull(expectedAt),
      'receivedAt': _timestampOrNull(receivedAt),
      'closedAt': _timestampOrNull(closedAt),
      'closedReason': _trimmedOrNull(closedReason),
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
      'order_number': orderNumber,
      'status': status.value,
      'items': items.map((item) => item.toMap()).toList(),
      'notes': notes,
      'delivery_note_number': deliveryNoteNumber,
      'ordered_at': orderedAt?.toIso8601String(),
      'expected_at': expectedAt?.toIso8601String(),
      'received_at': receivedAt?.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'closed_reason': closedReason,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PurchaseOrder copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    String? supplierId,
    String? supplierName,
    String? orderNumber,
    PurchaseOrderStatus? status,
    List<PurchaseOrderItem>? items,
    String? notes,
    String? deliveryNoteNumber,
    bool clearDeliveryNoteNumber = false,
    DateTime? orderedAt,
    DateTime? expectedAt,
    DateTime? receivedAt,
    DateTime? closedAt,
    String? closedReason,
    bool clearSiteName = false,
    bool clearOrderNumber = false,
    bool clearNotes = false,
    bool clearOrderedAt = false,
    bool clearExpectedAt = false,
    bool clearReceivedAt = false,
    bool clearClosedAt = false,
    bool clearClosedReason = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      orderNumber: clearOrderNumber ? null : (orderNumber ?? this.orderNumber),
      status: status ?? this.status,
      items: items ?? this.items,
      notes: clearNotes ? null : (notes ?? this.notes),
      deliveryNoteNumber: clearDeliveryNoteNumber
          ? null
          : (deliveryNoteNumber ?? this.deliveryNoteNumber),
      orderedAt: clearOrderedAt ? null : (orderedAt ?? this.orderedAt),
      expectedAt: clearExpectedAt ? null : (expectedAt ?? this.expectedAt),
      receivedAt: clearReceivedAt ? null : (receivedAt ?? this.receivedAt),
      closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
      closedReason:
          clearClosedReason ? null : (closedReason ?? this.closedReason),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<PurchaseOrderItem> _itemsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => PurchaseOrderItem.fromMap(
              item.cast<String, dynamic>(),
            ))
        .toList(growable: false);
  }

  static Timestamp? _timestampOrNull(DateTime? value) {
    if (value == null) {
      return null;
    }
    return Timestamp.fromDate(value);
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
