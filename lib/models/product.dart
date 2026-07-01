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
    this.externalPosId,
    this.category,
    this.unit = defaultUnit,
    this.supplierId,
    this.supplierName,
    this.purchasePriceCents,
    this.sellingPriceCents,
    this.taxRatePercent,
    this.currentStock = 0,
    this.minStock = 0,
    this.targetStock = 0,
    this.inFridge = false,
    this.fridgeTargetStock = 0,
    this.fridgeStock = 0,
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

  /// Stabiler Fremdschluessel zum Kassensystem (OktoPOS `externalReferenceNumber`
  /// bzw. `Product.externalReference` auf einer Verkaufsbuchung). Dient als
  /// Fallback-Join, wenn ein Verkauf keinen gescannten Barcode trägt. Null,
  /// solange der Artikel nicht mit der Kasse verknüpft ist.
  final String? externalPosId;

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

  /// Umsatzsteuersatz in ganzen Prozent (z.B. 19 oder 7). Für den Artikel-Push
  /// in die Kasse (OktoPOS `ArticlePrice.taxRate`). Null ⇒ beim Push wird der
  /// in den Kassen-Einstellungen hinterlegte Standardsatz verwendet.
  final int? taxRatePercent;

  /// Aktueller Bestand.
  final int currentStock;

  /// Meldebestand: bei Erreichen sollte nachbestellt werden.
  final int minStock;

  /// Zielbestand: gewuenschter Bestand nach einer Nachbestellung (0 = ungesetzt).
  final int targetStock;

  /// True, wenn der Artikel im Verkaufs-Kuehlschrank gefuehrt wird (Soll-Ist-Nachfuellung).
  final bool inFridge;

  /// Soll-Fuellstand des Kuehlschranks fuer diesen Artikel (0 = ungesetzt).
  final int fridgeTargetStock;

  /// Geschaetzter Ist-Bestand im Kuehlschrank, Teilmenge von [currentStock].
  /// Weiche Schaetzung: beim Nachfuellen auf [fridgeTargetStock] zurueckgesetzt,
  /// durch Verkaeufe gemindert. Kann roh negativ werden -> Leseseite klemmt via
  /// [fridgeStockClamped]. NICHT bilanziell (nicht in Warenwert/Schwund nutzen).
  final int fridgeStock;

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

  /// Kuehlschrank-Ist, auf >= 0 geklemmt (der Rohwert kann durch POS-Decrement
  /// negativ werden; nie roh in UI/Auswertung verwenden).
  int get fridgeStockClamped => fridgeStock < 0 ? 0 : fridgeStock;

  /// Abgeleiteter Lagerbestand = Gesamtbestand minus das, was im Kuehlschrank liegt.
  int get warehouseStock {
    final w = currentStock - fridgeStockClamped;
    return w < 0 ? 0 : w;
  }

  /// Fehlmenge bis zum Kuehlschrank-Soll (0, wenn Soll erreicht oder ungesetzt).
  int get fridgeDeficit {
    final d = fridgeTargetStock - fridgeStockClamped;
    return d < 0 ? 0 : d;
  }

  /// True, wenn der Kuehlschrank unter Soll ist UND im Lager Ware zum Nachfuellen
  /// vorhanden ist ("noch im Lager vorhanden, bitte nachfuellen").
  bool get fridgeNeedsRefill =>
      inFridge && fridgeDeficit > 0 && warehouseStock > 0;

  /// Vorgeschlagene Nachbestellmenge: explizit gesetzte [reorderQuantity] hat
  /// Vorrang, sonst die Differenz bis zum [targetStock] (Zielbestand) bzw. – wenn
  /// kein Zielbestand gesetzt ist – bis zum doppelten Meldebestand (Mindestmenge 1).
  int get suggestedReorderQuantity {
    if (reorderQuantity != null && reorderQuantity! > 0) {
      return reorderQuantity!;
    }
    final target = targetStock > 0 ? targetStock : minStock * 2;
    if (target <= 0) {
      return 1;
    }
    final delta = target - currentStock;
    return delta > 0 ? delta : 1;
  }

  /// Spanne (Marge) je Stueck in Cent, falls Ein- und Verkaufspreis gesetzt sind.
  int? get marginCents =>
      (sellingPriceCents != null && purchasePriceCents != null)
          ? sellingPriceCents! - purchasePriceCents!
          : null;

  /// Marge in Prozent des Einkaufspreises, falls berechenbar.
  double? get marginPercent => (purchasePriceCents != null &&
          purchasePriceCents! > 0 &&
          sellingPriceCents != null)
      ? (sellingPriceCents! - purchasePriceCents!) / purchasePriceCents! * 100
      : null;

  /// Warenwert dieses Artikels zum Einkaufspreis (Bestand × EK), 0 ohne Preis
  /// oder bei Negativbestand.
  int get stockValuePurchaseCents =>
      (purchasePriceCents ?? 0) * (currentStock > 0 ? currentStock : 0);

  /// Warenwert dieses Artikels zum Verkaufspreis (Bestand × VK), 0 ohne Preis.
  int get stockValueSellingCents =>
      (sellingPriceCents ?? 0) * (currentStock > 0 ? currentStock : 0);

  factory Product.fromFirestore(String id, Map<String, dynamic> map) {
    return Product(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      name: (map['name'] ?? '').toString(),
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      externalPosId: map['externalPosId'] as String?,
      category: map['category'] as String?,
      unit: (map['unit'] ?? defaultUnit).toString().trim().isEmpty
          ? defaultUnit
          : (map['unit'] ?? defaultUnit).toString(),
      supplierId: map['supplierId'] as String?,
      supplierName: map['supplierName'] as String?,
      purchasePriceCents: parse.toInt(map['purchasePriceCents']),
      sellingPriceCents: parse.toInt(map['sellingPriceCents']),
      taxRatePercent: parse.toInt(map['taxRatePercent']),
      currentStock: parse.toInt(map['currentStock']) ?? 0,
      minStock: parse.toInt(map['minStock']) ?? 0,
      targetStock: parse.toInt(map['targetStock']) ?? 0,
      inFridge: parse.toBool(map['inFridge']) ?? false,
      fridgeTargetStock: parse.toInt(map['fridgeTargetStock']) ?? 0,
      fridgeStock: parse.toInt(map['fridgeStock']) ?? 0,
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
      externalPosId: map['external_pos_id'] as String?,
      category: map['category'] as String?,
      unit: (map['unit'] ?? defaultUnit).toString().trim().isEmpty
          ? defaultUnit
          : (map['unit'] ?? defaultUnit).toString(),
      supplierId: map['supplier_id'] as String?,
      supplierName: map['supplier_name'] as String?,
      purchasePriceCents: parse.toInt(map['purchase_price_cents']),
      sellingPriceCents: parse.toInt(map['selling_price_cents']),
      taxRatePercent: parse.toInt(map['tax_rate_percent']),
      currentStock: parse.toInt(map['current_stock']) ?? 0,
      minStock: parse.toInt(map['min_stock']) ?? 0,
      targetStock: parse.toInt(map['target_stock']) ?? 0,
      inFridge: parse.toBool(map['in_fridge']) ?? false,
      fridgeTargetStock: parse.toInt(map['fridge_target_stock']) ?? 0,
      fridgeStock: parse.toInt(map['fridge_stock']) ?? 0,
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
      'externalPosId': _trimmedOrNull(externalPosId),
      'category': _trimmedOrNull(category),
      'unit': unit.trim().isEmpty ? defaultUnit : unit.trim(),
      'supplierId': _trimmedOrNull(supplierId),
      'supplierName': _trimmedOrNull(supplierName),
      'purchasePriceCents': purchasePriceCents,
      'sellingPriceCents': sellingPriceCents,
      'taxRatePercent': taxRatePercent,
      'currentStock': currentStock,
      'minStock': minStock,
      'targetStock': targetStock,
      'inFridge': inFridge,
      'fridgeTargetStock': fridgeTargetStock,
      'fridgeStock': fridgeStock,
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
      'external_pos_id': externalPosId,
      'category': category,
      'unit': unit,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_price_cents': purchasePriceCents,
      'selling_price_cents': sellingPriceCents,
      'tax_rate_percent': taxRatePercent,
      'current_stock': currentStock,
      'min_stock': minStock,
      'target_stock': targetStock,
      'in_fridge': inFridge,
      'fridge_target_stock': fridgeTargetStock,
      'fridge_stock': fridgeStock,
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
    String? externalPosId,
    String? category,
    String? unit,
    String? supplierId,
    String? supplierName,
    int? purchasePriceCents,
    int? sellingPriceCents,
    int? taxRatePercent,
    int? currentStock,
    int? minStock,
    int? targetStock,
    bool? inFridge,
    int? fridgeTargetStock,
    int? fridgeStock,
    int? reorderQuantity,
    bool? isActive,
    bool clearSiteName = false,
    bool clearSku = false,
    bool clearBarcode = false,
    bool clearExternalPosId = false,
    bool clearCategory = false,
    bool clearSupplier = false,
    bool clearPurchasePrice = false,
    bool clearSellingPrice = false,
    bool clearTaxRatePercent = false,
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
      externalPosId:
          clearExternalPosId ? null : (externalPosId ?? this.externalPosId),
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
      taxRatePercent: clearTaxRatePercent
          ? null
          : (taxRatePercent ?? this.taxRatePercent),
      currentStock: currentStock ?? this.currentStock,
      minStock: minStock ?? this.minStock,
      targetStock: targetStock ?? this.targetStock,
      inFridge: inFridge ?? this.inFridge,
      fridgeTargetStock: fridgeTargetStock ?? this.fridgeTargetStock,
      fridgeStock: fridgeStock ?? this.fridgeStock,
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
