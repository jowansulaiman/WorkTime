import '../models/cash_closing.dart';
import '../models/cash_count.dart';
import '../models/contact.dart';
import '../models/contact_activity.dart';
import '../models/contact_details.dart';
import '../models/contact_organization.dart';
import '../models/customer_feedback.dart';
import '../models/customer_order.dart';
import '../models/customer_wish.dart';
import '../models/fridge_refill.dart';
import '../models/order_cart.dart';
import '../models/pos_daily_stat.dart';
import '../models/pos_receipt.dart';
import '../models/price_history_entry.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/purchase_order.dart';
import '../models/scan_event.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../models/third_party_cash.dart';
import 'kasse_report.dart';
import 'local_demo_data.dart';

/// Vollstaendige, reproduzierbare Beispieldaten fuer Warenwirtschaft, CRM und
/// Kassen-Auswertungen.
///
/// Die normalen Warenwirtschafts-/CRM-Modelle koennen vom aufrufenden Provider
/// lokal oder in der Cloud persistiert werden. [posReceiptsForOrg],
/// [posDailyStatsForOrg], [cashCountsForOrg] und [cashClosingsForOrg] liefern
/// dagegen absichtlich nur typisierte In-Memory-Fakten: Diese Collections sind
/// im Produkt cloud-only und duerfen nicht in SharedPreferences gespiegelt
/// werden.
///
/// Alle IDs beginnen mit `demo-` und sind aus Org, Standort und fachlichem
/// Schluessel abgeleitet. Dadurch sind wiederholte Seeds idempotent und alle
/// Fremdschluessel koennen ohne Zufallswerte aufgeloest werden.
class LocalDemoInventoryData {
  LocalDemoInventoryData._();

  static const String tabakSiteName = 'Tabak Börse';
  static const String strichSiteName = 'Strichmännchen GmbH';
  static const String paketSiteName = 'Paketshop REWE Dietrichsdorf';

  static String supplierId(String orgId, String key) =>
      'demo-supplier-$orgId-$key';

  static String productId(String orgId, String siteKey, String key) =>
      'demo-product-$orgId-$siteKey-$key';

  static String contactId(String orgId, String key) =>
      'demo-contact-$orgId-$key';

  static String wishId(
    String orgId,
    CustomerWishCategory category,
    CustomerWishStatus status,
  ) => 'demo-wish-$orgId-${category.value}-${status.value}';

  static String feedbackId(
    String orgId,
    FeedbackType type,
    FeedbackStatus status,
  ) => 'demo-feedback-$orgId-${type.value}-${status.value}';

  static List<String> siteIdsForOrg(String orgId) => [
    LocalDemoData.tabakSiteId(orgId),
    LocalDemoData.strichmaennchenSiteId(orgId),
    LocalDemoData.paketshopSiteId(orgId),
  ];

  static DateTime _day(DateTime? now, [int offset = 0, int hour = 12]) {
    final value = now ?? DateTime.now();
    return DateTime(value.year, value.month, value.day + offset, hour);
  }

  static String _dayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static List<Supplier> suppliersForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final createdAt = _day(now, -120, 9);
    return [
      Supplier(
        id: supplierId(orgId, 'tabak'),
        orgId: orgId,
        name: 'Nord Tabakwaren GmbH',
        contactPerson: 'Petra Petersen',
        email: 'service@nord-tabak.example',
        phone: '+49 431 555100',
        orderEmail: 'bestellung@nord-tabak.example',
        customerNumber: 'KD-4711',
        leadTimeDays: 2,
        minOrderQuantity: 10,
        packagingUnit: 'Karton/Stange',
        notes: 'Regellieferung Dienstag und Freitag.',
        contactId: contactId(orgId, 'nord-tabak'),
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: _day(now, -7, 10),
      ),
      Supplier(
        id: supplierId(orgId, 'getraenke'),
        orgId: orgId,
        name: 'Förde Getränke Service KG',
        contactPerson: 'Nils Voss',
        email: 'info@foerde-getraenke.example',
        phone: '+49 431 555200',
        orderEmail: 'dispo@foerde-getraenke.example',
        customerNumber: 'FG-208',
        leadTimeDays: 1,
        minOrderQuantity: 24,
        packagingUnit: 'Kiste à 24 Flaschen',
        notes: 'Pfand wird separat abgerechnet.',
        contactId: contactId(orgId, 'foerde-getraenke'),
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: _day(now, -3, 10),
      ),
      Supplier(
        id: supplierId(orgId, 'presse'),
        orgId: orgId,
        name: 'Kieler Pressevertrieb',
        contactPerson: 'Olaf Brandt',
        email: 'service@kieler-presse.example',
        orderEmail: 'remission@kieler-presse.example',
        phone: '+49 431 555300',
        customerNumber: 'PV-9901',
        leadTimeDays: 3,
        minOrderQuantity: 1,
        packagingUnit: 'Exemplar',
        notes: 'Remissionen montags bis 10 Uhr melden.',
        contactId: contactId(orgId, 'pressevertrieb'),
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: _day(now, -14, 10),
      ),
      Supplier(
        id: supplierId(orgId, 'verpackung'),
        orgId: orgId,
        name: 'NordPack Versandbedarf e.K.',
        contactPerson: 'Samira Yilmaz',
        email: 'kontakt@nordpack.example',
        phone: '+49 431 555400',
        customerNumber: 'NP-440',
        leadTimeDays: 5,
        minOrderQuantity: 50,
        packagingUnit: 'Bund à 25 Stück',
        notes: 'Bestellung nur über Portal; keine eigene Bestelladresse.',
        contactId: contactId(orgId, 'nordpack'),
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: _day(now, -30, 10),
      ),
      Supplier(
        id: supplierId(orgId, 'inaktiv'),
        orgId: orgId,
        name: 'Historischer Lieferant (inaktiv)',
        email: 'archiv@lieferant.example',
        notes: 'Nur für Altbelege und Inaktiv-Filter.',
        isActive: false,
        createdByUid: createdByUid,
        createdAt: _day(now, -400, 9),
        updatedAt: _day(now, -200, 9),
      ),
    ];
  }

  static List<Product> productsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final tobacco = supplierId(orgId, 'tabak');
    final drinks = supplierId(orgId, 'getraenke');
    final press = supplierId(orgId, 'presse');
    final packaging = supplierId(orgId, 'verpackung');
    final createdAt = _day(now, -90, 9);

    Product product({
      required String siteKey,
      required String siteId,
      required String siteName,
      required String key,
      required String name,
      required String sku,
      String? barcode,
      String? externalPosId,
      required String category,
      String unit = 'Stück',
      String? supplierId,
      String? supplierName,
      int? purchasePriceCents,
      int? sellingPriceCents,
      int? taxRatePercent = 19,
      int currentStock = 0,
      int minStock = 0,
      int targetStock = 0,
      bool inFridge = false,
      int fridgeTargetStock = 0,
      int fridgeStock = 0,
      int? reorderQuantity,
      bool isActive = true,
    }) => Product(
      id: productId(orgId, siteKey, key),
      orgId: orgId,
      siteId: siteId,
      siteName: siteName,
      name: name,
      sku: sku,
      barcode: barcode,
      externalPosId: externalPosId,
      category: category,
      unit: unit,
      supplierId: supplierId,
      supplierName: supplierName,
      purchasePriceCents: purchasePriceCents,
      sellingPriceCents: sellingPriceCents,
      taxRatePercent: taxRatePercent,
      currentStock: currentStock,
      minStock: minStock,
      targetStock: targetStock,
      inFridge: inFridge,
      fridgeTargetStock: fridgeTargetStock,
      fridgeStock: fridgeStock,
      reorderQuantity: reorderQuantity,
      isActive: isActive,
      createdByUid: createdByUid,
      createdAt: createdAt,
      updatedAt: _day(now, -1, 18),
    );

    return [
      product(
        siteKey: 'tabak',
        siteId: tabak,
        siteName: tabakSiteName,
        key: 'cola',
        name: 'Cola 0,5 l',
        sku: 'GET-COLA-050',
        barcode: '4006381333931',
        externalPosId: 'POS-COLA-050',
        category: 'Getränke',
        unit: 'Flasche',
        supplierId: drinks,
        supplierName: 'Förde Getränke Service KG',
        purchasePriceCents: 72,
        sellingPriceCents: 220,
        currentStock: 8,
        minStock: 12,
        targetStock: 48,
        inFridge: true,
        fridgeTargetStock: 12,
        fridgeStock: 2,
      ),
      product(
        siteKey: 'tabak',
        siteId: tabak,
        siteName: tabakSiteName,
        key: 'marlboro',
        name: 'Marlboro Rot (Packung)',
        sku: 'TAB-MAR-ROT',
        barcode: '4242424242420',
        externalPosId: 'POS-MAR-ROT',
        category: 'Zigaretten',
        supplierId: tobacco,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 850,
        sellingPriceCents: 1010,
        currentStock: 0,
        minStock: 10,
        targetStock: 40,
        reorderQuantity: 40,
      ),
      product(
        siteKey: 'tabak',
        siteId: tabak,
        siteName: tabakSiteName,
        key: 'chips',
        name: 'Kartoffelchips Paprika',
        sku: 'SNK-CHIPS-PAP',
        barcode: '4012345678901',
        externalPosId: 'POS-CHIPS-PAP',
        category: 'Snacks',
        supplierId: drinks,
        supplierName: 'Förde Getränke Service KG',
        purchasePriceCents: 68,
        // Absichtlich 10 Cent ueber dem POS-Preis 179: damit der
        // Preisabgleich einen echten Fall zeigt.
        sellingPriceCents: 189,
        taxRatePercent: 7,
        currentStock: 42,
        minStock: 8,
        targetStock: 32,
      ),
      product(
        siteKey: 'tabak',
        siteId: tabak,
        siteName: tabakSiteName,
        key: 'zigarre-alt',
        name: 'Zigarre Edition 2024',
        sku: 'TAB-ZIG-2024',
        category: 'Zigarren',
        supplierId: tobacco,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 490,
        sellingPriceCents: 790,
        currentStock: 6,
        isActive: false,
      ),
      product(
        siteKey: 'strich',
        siteId: strich,
        siteName: strichSiteName,
        key: 'cola',
        name: 'Cola 0,5 l',
        sku: 'GET-COLA-050',
        barcode: '4006381333931',
        externalPosId: 'POS-COLA-050',
        category: 'Getränke',
        unit: 'Flasche',
        supplierId: drinks,
        supplierName: 'Förde Getränke Service KG',
        purchasePriceCents: 72,
        sellingPriceCents: 220,
        currentStock: 74,
        minStock: 12,
        targetStock: 48,
        inFridge: true,
        fridgeTargetStock: 14,
        fridgeStock: 14,
      ),
      product(
        siteKey: 'strich',
        siteId: strich,
        siteName: strichSiteName,
        key: 'pueblo',
        name: 'Pueblo Tabak 30 g',
        sku: 'TAB-PUE-030',
        barcode: '4023500999991',
        externalPosId: 'POS-PUE-030',
        category: 'Drehtabak',
        unit: 'Beutel',
        supplierId: tobacco,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 520,
        sellingPriceCents: 700,
        currentStock: 5,
        minStock: 6,
        targetStock: 18,
      ),
      product(
        siteKey: 'strich',
        siteId: strich,
        siteName: strichSiteName,
        key: 'spiegel',
        name: 'Der Spiegel',
        sku: 'PRE-SPIEGEL',
        externalPosId: 'POS-SPIEGEL',
        category: 'Presse',
        supplierId: press,
        supplierName: 'Kieler Pressevertrieb',
        purchasePriceCents: 430,
        sellingPriceCents: 620,
        taxRatePercent: 7,
        currentStock: 3,
        minStock: 5,
        targetStock: 8,
      ),
      product(
        siteKey: 'strich',
        siteId: strich,
        siteName: strichSiteName,
        key: 'clipper',
        name: 'Feuerzeug Clipper',
        sku: 'RAU-CLIPPER',
        barcode: '4051234567896',
        category: 'Raucherbedarf',
        supplierId: tobacco,
        supplierName: 'Nord Tabakwaren GmbH',
        purchasePriceCents: 65,
        sellingPriceCents: 150,
        currentStock: 80,
        minStock: 20,
        targetStock: 60,
      ),
      product(
        siteKey: 'paket',
        siteId: paket,
        siteName: paketSiteName,
        key: 'cola',
        name: 'Cola 0,5 l',
        sku: 'GET-COLA-050',
        barcode: '4006381333931',
        externalPosId: 'POS-COLA-050',
        category: 'Getränke',
        unit: 'Flasche',
        supplierId: drinks,
        supplierName: 'Förde Getränke Service KG',
        purchasePriceCents: 72,
        sellingPriceCents: 220,
        currentStock: -2,
        minStock: 12,
        targetStock: 48,
        inFridge: true,
        fridgeTargetStock: 10,
        fridgeStock: -1,
      ),
      product(
        siteKey: 'paket',
        siteId: paket,
        siteName: paketSiteName,
        key: 'wasser',
        name: 'Mineralwasser 0,5 l',
        sku: 'GET-WASSER-050',
        barcode: '4100000000003',
        externalPosId: 'POS-WASSER-050',
        category: 'Getränke',
        unit: 'Flasche',
        supplierId: drinks,
        supplierName: 'Förde Getränke Service KG',
        purchasePriceCents: 36,
        sellingPriceCents: 135,
        currentStock: 28,
        minStock: 12,
        targetStock: 48,
        inFridge: true,
        fridgeTargetStock: 10,
        fridgeStock: 4,
      ),
      product(
        siteKey: 'paket',
        siteId: paket,
        siteName: paketSiteName,
        key: 'karton-s',
        name: 'Versandkarton S',
        sku: 'VER-KARTON-S',
        category: 'Verpackung',
        unit: 'Stück',
        supplierId: packaging,
        supplierName: 'NordPack Versandbedarf e.K.',
        purchasePriceCents: 42,
        sellingPriceCents: 129,
        currentStock: 11,
        minStock: 15,
        targetStock: 75,
      ),
      product(
        siteKey: 'paket',
        siteId: paket,
        siteName: paketSiteName,
        key: 'luftpolster',
        name: 'Luftpolsterumschlag DIN A4',
        sku: 'VER-LUFT-A4',
        category: 'Verpackung',
        supplierId: packaging,
        supplierName: 'NordPack Versandbedarf e.K.',
        purchasePriceCents: 28,
        sellingPriceCents: null,
        taxRatePercent: null,
        currentStock: 50,
        minStock: 10,
        targetStock: 50,
      ),
    ];
  }

  static List<ProductBatch> productBatchesForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final resolvedAt = _day(now, -2, 18);
    return [
      ProductBatch(
        id: 'demo-batch-$orgId-overdue',
        orgId: orgId,
        siteId: tabak,
        productId: productId(orgId, 'tabak', 'chips'),
        productName: 'Kartoffelchips Paprika',
        expiryDate: _day(now, -5),
        quantity: 6,
        note: 'MHD überschritten – vorderes Regal.',
        createdByUid: createdByUid,
        createdAt: _day(now, -60),
        updatedAt: _day(now, -5),
      ),
      ProductBatch(
        id: 'demo-batch-$orgId-today',
        orgId: orgId,
        siteId: paket,
        productId: productId(orgId, 'paket', 'wasser'),
        productName: 'Mineralwasser 0,5 l',
        expiryDate: _day(now),
        quantity: 4,
        note: 'Heute rabattieren.',
        createdByUid: createdByUid,
        createdAt: _day(now, -45),
        updatedAt: _day(now, -1),
      ),
      ProductBatch(
        id: 'demo-batch-$orgId-soon',
        orgId: orgId,
        siteId: strich,
        productId: productId(orgId, 'strich', 'cola'),
        productName: 'Cola 0,5 l',
        expiryDate: _day(now, 4),
        quantity: 12,
        note: 'Palette hinten links.',
        createdByUid: createdByUid,
        createdAt: _day(now, -30),
        updatedAt: _day(now, -1),
      ),
      ProductBatch(
        id: 'demo-batch-$orgId-future',
        orgId: orgId,
        siteId: tabak,
        productId: productId(orgId, 'tabak', 'cola'),
        productName: 'Cola 0,5 l',
        expiryDate: _day(now, 120),
        quantity: 24,
        createdByUid: createdByUid,
        createdAt: _day(now, -2),
        updatedAt: _day(now, -2),
      ),
      ProductBatch(
        id: 'demo-batch-$orgId-sold-out',
        orgId: orgId,
        siteId: strich,
        productId: productId(orgId, 'strich', 'spiegel'),
        productName: 'Der Spiegel',
        expiryDate: _day(now, -14),
        status: BatchStatus.soldOut,
        resolvedByUid: createdByUid,
        resolvedAt: resolvedAt,
        createdByUid: createdByUid,
        createdAt: _day(now, -35),
        updatedAt: resolvedAt,
      ),
      ProductBatch(
        id: 'demo-batch-$orgId-discarded',
        orgId: orgId,
        siteId: paket,
        productId: productId(orgId, 'paket', 'wasser'),
        productName: 'Mineralwasser 0,5 l',
        expiryDate: _day(now, -3),
        quantity: 2,
        note: 'Verpackung beschädigt.',
        status: BatchStatus.discarded,
        resolvedByUid: createdByUid,
        resolvedAt: resolvedAt,
        createdByUid: createdByUid,
        createdAt: _day(now, -40),
        updatedAt: resolvedAt,
      ),
    ];
  }

  static List<PurchaseOrder> purchaseOrdersForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final createdAt = _day(now, -10, 9);

    PurchaseOrderItem item(
      String siteKey,
      String key,
      String name,
      String sku,
      int ordered,
      int received,
      int price,
      int tax,
    ) => PurchaseOrderItem(
      productId: productId(orgId, siteKey, key),
      name: name,
      sku: sku,
      quantityOrdered: ordered,
      quantityReceived: received,
      unitPriceCents: price,
      taxRatePercent: tax,
    );

    return [
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-draft',
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        supplierId: supplierId(orgId, 'tabak'),
        supplierName: 'Nord Tabakwaren GmbH',
        orderNumber: 'DEMO-ENTWURF',
        status: PurchaseOrderStatus.draft,
        items: [
          item(
            'tabak',
            'marlboro',
            'Marlboro Rot (Packung)',
            'TAB-MAR-ROT',
            40,
            0,
            850,
            19,
          ),
        ],
        notes: 'Noch nicht an den Lieferanten gesendet.',
        createdByUid: createdByUid,
        createdAt: createdAt,
        updatedAt: _day(now, -1, 10),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-overdue',
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        supplierId: supplierId(orgId, 'getraenke'),
        supplierName: 'Förde Getränke Service KG',
        orderNumber: 'DEMO-ÜBERFÄLLIG',
        status: PurchaseOrderStatus.ordered,
        items: [
          item('tabak', 'cola', 'Cola 0,5 l', 'GET-COLA-050', 48, 0, 72, 19),
        ],
        notes: 'Lieferant telefonisch erinnern.',
        orderedAt: _day(now, -5, 9),
        expectedAt: _day(now, -2, 12),
        createdByUid: createdByUid,
        createdAt: _day(now, -6, 9),
        updatedAt: _day(now, -5, 9),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-today',
        orgId: orgId,
        siteId: strich,
        siteName: strichSiteName,
        supplierId: supplierId(orgId, 'presse'),
        supplierName: 'Kieler Pressevertrieb',
        orderNumber: 'DEMO-HEUTE',
        status: PurchaseOrderStatus.ordered,
        items: [
          item('strich', 'spiegel', 'Der Spiegel', 'PRE-SPIEGEL', 8, 0, 430, 7),
        ],
        orderedAt: _day(now, -3, 9),
        expectedAt: _day(now),
        createdByUid: createdByUid,
        createdAt: _day(now, -4, 9),
        updatedAt: _day(now, -3, 9),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-upcoming',
        orgId: orgId,
        siteId: paket,
        siteName: paketSiteName,
        supplierId: supplierId(orgId, 'verpackung'),
        supplierName: 'NordPack Versandbedarf e.K.',
        orderNumber: 'DEMO-KOMMEND',
        status: PurchaseOrderStatus.ordered,
        items: [
          item(
            'paket',
            'karton-s',
            'Versandkarton S',
            'VER-KARTON-S',
            75,
            0,
            42,
            19,
          ),
        ],
        orderedAt: _day(now, -1, 9),
        expectedAt: _day(now, 4),
        createdByUid: createdByUid,
        createdAt: _day(now, -2, 9),
        updatedAt: _day(now, -1, 9),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-partial',
        orgId: orgId,
        siteId: strich,
        siteName: strichSiteName,
        supplierId: supplierId(orgId, 'tabak'),
        supplierName: 'Nord Tabakwaren GmbH',
        orderNumber: 'DEMO-TEIL',
        status: PurchaseOrderStatus.partiallyReceived,
        items: [
          item(
            'strich',
            'pueblo',
            'Pueblo Tabak 30 g',
            'TAB-PUE-030',
            18,
            8,
            520,
            19,
          ),
          item(
            'strich',
            'clipper',
            'Feuerzeug Clipper',
            'RAU-CLIPPER',
            60,
            60,
            65,
            19,
          ),
        ],
        notes: 'Pueblo wird nachgeliefert.',
        orderedAt: _day(now, -4, 9),
        expectedAt: _day(now, 1),
        receivedAt: _day(now, -1, 11),
        createdByUid: createdByUid,
        createdAt: _day(now, -5, 9),
        updatedAt: _day(now, -1, 11),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-received',
        orgId: orgId,
        siteId: paket,
        siteName: paketSiteName,
        supplierId: supplierId(orgId, 'getraenke'),
        supplierName: 'Förde Getränke Service KG',
        orderNumber: 'DEMO-GELIEFERT',
        status: PurchaseOrderStatus.received,
        items: [
          item(
            'paket',
            'wasser',
            'Mineralwasser 0,5 l',
            'GET-WASSER-050',
            48,
            48,
            36,
            19,
          ),
        ],
        orderedAt: _day(now, -8, 9),
        expectedAt: _day(now, -6),
        receivedAt: _day(now, -6, 11),
        closedAt: _day(now, -6, 11),
        closedReason: 'Vollständig geliefert',
        createdByUid: createdByUid,
        createdAt: _day(now, -9, 9),
        updatedAt: _day(now, -6, 11),
      ),
      PurchaseOrder(
        id: 'demo-purchase-order-$orgId-cancelled',
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        supplierId: supplierId(orgId, 'inaktiv'),
        supplierName: 'Historischer Lieferant (inaktiv)',
        orderNumber: 'DEMO-STORNIERT',
        status: PurchaseOrderStatus.cancelled,
        items: [
          item(
            'tabak',
            'zigarre-alt',
            'Zigarre Edition 2024',
            'TAB-ZIG-2024',
            12,
            0,
            490,
            19,
          ),
        ],
        notes: 'Artikel nicht mehr lieferbar.',
        orderedAt: _day(now, -20, 9),
        expectedAt: _day(now, -15),
        closedAt: _day(now, -18, 10),
        closedReason: 'Vom Lieferanten storniert',
        createdByUid: createdByUid,
        createdAt: _day(now, -21, 9),
        updatedAt: _day(now, -18, 10),
      ),
    ];
  }

  static List<StockMovement> stockMovementsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      StockMovement(
        id: 'demo-movement-$orgId-receipt',
        orgId: orgId,
        siteId: paket,
        productId: productId(orgId, 'paket', 'wasser'),
        productName: 'Mineralwasser 0,5 l',
        type: StockMovementType.receipt,
        quantityDelta: 48,
        balanceAfter: 52,
        reason: 'Wareneingang vollständig gebucht',
        relatedOrderId: 'demo-purchase-order-$orgId-received',
        source: 'manual',
        createdByUid: createdByUid,
        createdAt: _day(now, -6, 11),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-issue-pos',
        orgId: orgId,
        siteId: tabak,
        productId: productId(orgId, 'tabak', 'cola'),
        productName: 'Cola 0,5 l',
        type: StockMovementType.issue,
        quantityDelta: -2,
        balanceAfter: 8,
        reason: 'Verkauf über OktoPOS',
        source: 'oktopos',
        externalRef: 'DEMO-POS-SALE-1',
        createdAt: _day(now, 0, 10),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-adjustment-plus',
        orgId: orgId,
        siteId: strich,
        productId: productId(orgId, 'strich', 'clipper'),
        productName: 'Feuerzeug Clipper',
        type: StockMovementType.adjustment,
        quantityDelta: 3,
        balanceAfter: 80,
        reason: 'Drei Stück hinter dem Regal gefunden',
        source: 'manual',
        createdByUid: createdByUid,
        createdAt: _day(now, -3, 15),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-adjustment-minus',
        orgId: orgId,
        siteId: paket,
        productId: productId(orgId, 'paket', 'karton-s'),
        productName: 'Versandkarton S',
        type: StockMovementType.adjustment,
        quantityDelta: -2,
        balanceAfter: 11,
        reason: 'Beschädigte Kartons ausgebucht',
        source: 'manual',
        createdByUid: createdByUid,
        createdAt: _day(now, -4, 16),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-stocktake',
        orgId: orgId,
        siteId: tabak,
        productId: productId(orgId, 'tabak', 'chips'),
        productName: 'Kartoffelchips Paprika',
        type: StockMovementType.stocktake,
        quantityDelta: -5,
        balanceAfter: 42,
        reason: 'Inventur – Soll 47, Ist 42',
        source: 'manual',
        createdByUid: createdByUid,
        createdAt: _day(now, -7, 19),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-transfer-out',
        orgId: orgId,
        siteId: strich,
        productId: productId(orgId, 'strich', 'cola'),
        productName: 'Cola 0,5 l',
        type: StockMovementType.transfer,
        quantityDelta: -12,
        balanceAfter: 74,
        reason: 'Umlagerung an Tabak Börse',
        source: 'manual',
        externalRef: 'demo-transfer-$orgId-cola-1',
        createdByUid: createdByUid,
        createdAt: _day(now, -2, 8),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-transfer-in',
        orgId: orgId,
        siteId: tabak,
        productId: productId(orgId, 'tabak', 'cola'),
        productName: 'Cola 0,5 l',
        type: StockMovementType.transfer,
        quantityDelta: 12,
        balanceAfter: 10,
        reason: 'Umlagerung von Strichmännchen',
        source: 'manual',
        externalRef: 'demo-transfer-$orgId-cola-1',
        createdByUid: createdByUid,
        createdAt: _day(now, -2, 8),
      ),
      StockMovement(
        id: 'demo-movement-$orgId-fridge-refill',
        orgId: orgId,
        siteId: paket,
        productId: productId(orgId, 'paket', 'wasser'),
        productName: 'Mineralwasser 0,5 l',
        type: StockMovementType.fridgeRefill,
        quantityDelta: 6,
        balanceAfter: 28,
        reason: 'Verkaufskühlschrank aufgefüllt',
        source: 'manual',
        createdByUid: LocalDemoData.employeeAccount.uid,
        createdAt: _day(now, -1, 7),
      ),
    ];
  }

  static List<PriceHistoryEntry> priceHistoryForOrg({
    required String orgId,
    required String changedByUid,
    DateTime? now,
  }) => [
    PriceHistoryEntry(
      id: 'demo-price-$orgId-cola-ek-initial',
      orgId: orgId,
      productId: productId(orgId, 'tabak', 'cola'),
      field: PriceField.purchase,
      oldCents: null,
      newCents: 68,
      changedByUid: changedByUid,
      changedAt: _day(now, -120, 9),
    ),
    PriceHistoryEntry(
      id: 'demo-price-$orgId-cola-ek-change',
      orgId: orgId,
      productId: productId(orgId, 'tabak', 'cola'),
      field: PriceField.purchase,
      oldCents: 68,
      newCents: 72,
      changedByUid: changedByUid,
      changedAt: _day(now, -30, 9),
    ),
    PriceHistoryEntry(
      id: 'demo-price-$orgId-cola-vk-change',
      orgId: orgId,
      productId: productId(orgId, 'tabak', 'cola'),
      field: PriceField.selling,
      oldCents: 200,
      newCents: 220,
      changedByUid: changedByUid,
      changedAt: _day(now, -14, 9),
    ),
    PriceHistoryEntry(
      id: 'demo-price-$orgId-luftpolster-vk-removed',
      orgId: orgId,
      productId: productId(orgId, 'paket', 'luftpolster'),
      field: PriceField.selling,
      oldCents: 99,
      newCents: null,
      changedByUid: changedByUid,
      changedAt: _day(now, -2, 9),
    ),
  ];

  static List<ScanEvent> scanEventsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      ScanEvent(
        id: 'demo-scan-$orgId-matched-camera',
        orgId: orgId,
        siteId: tabak,
        code: '4006381333931',
        outcome: ScanOutcome.matched,
        mode: 'order',
        source: 'camera',
        timeToHitMs: 420,
        productId: productId(orgId, 'tabak', 'cola'),
        platform: 'android',
        createdByUid: createdByUid,
        createdAt: _day(now, 0, 9),
      ),
      ScanEvent(
        id: 'demo-scan-$orgId-matched-manual',
        orgId: orgId,
        siteId: paket,
        code: '4100000000003',
        outcome: ScanOutcome.matched,
        mode: 'stocktake',
        source: 'manual',
        timeToHitMs: 3200,
        productId: productId(orgId, 'paket', 'wasser'),
        platform: 'web',
        createdByUid: createdByUid,
        createdAt: _day(now, -1, 10),
      ),
      ScanEvent(
        id: 'demo-scan-$orgId-multi',
        orgId: orgId,
        siteId: strich,
        code: '4006381333931',
        outcome: ScanOutcome.multiMatch,
        mode: 'book',
        source: 'camera',
        timeToHitMs: 680,
        platform: 'ios',
        createdByUid: createdByUid,
        createdAt: _day(now, -2, 12),
      ),
      ScanEvent(
        id: 'demo-scan-$orgId-not-found',
        orgId: orgId,
        siteId: paket,
        code: '9999999999994',
        outcome: ScanOutcome.notFound,
        mode: 'order',
        source: 'photo',
        timeToHitMs: 1800,
        platform: 'android',
        createdByUid: createdByUid,
        createdAt: _day(now, -3, 14),
      ),
      ScanEvent(
        id: 'demo-scan-$orgId-invalid',
        orgId: orgId,
        siteId: tabak,
        code: '4006381333932',
        outcome: ScanOutcome.invalidChecksum,
        mode: 'stocktake',
        source: 'camera',
        timeToHitMs: 2400,
        platform: 'android',
        createdByUid: createdByUid,
        createdAt: _day(now, -4, 16),
      ),
    ];
  }

  static List<SiteOrderList> orderCartsForOrg({
    required String orgId,
    required String updatedByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      SiteOrderList(
        id: tabak,
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        items: [
          OrderListItem(
            productId: productId(orgId, 'tabak', 'marlboro'),
            name: 'Marlboro Rot (Packung)',
            sku: 'TAB-MAR-ROT',
            category: 'Zigaretten',
            quantity: 40,
            supplierId: supplierId(orgId, 'tabak'),
            supplierName: 'Nord Tabakwaren GmbH',
            addedByUid: LocalDemoData.employeeAccount.uid,
            note: 'Regal leer',
          ),
          OrderListItem(
            productId: productId(orgId, 'tabak', 'cola'),
            name: 'Cola 0,5 l',
            sku: 'GET-COLA-050',
            category: 'Getränke',
            unit: 'Flasche',
            quantity: 48,
            supplierId: supplierId(orgId, 'getraenke'),
            supplierName: 'Förde Getränke Service KG',
            addedByUid: updatedByUid,
          ),
        ],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, -1, 18),
      ),
      SiteOrderList(
        id: strich,
        orgId: orgId,
        siteId: strich,
        siteName: strichSiteName,
        items: [
          OrderListItem(
            productId: productId(orgId, 'strich', 'spiegel'),
            name: 'Der Spiegel',
            sku: 'PRE-SPIEGEL',
            category: 'Presse',
            quantity: 5,
            supplierId: supplierId(orgId, 'presse'),
            supplierName: 'Kieler Pressevertrieb',
            addedByUid: LocalDemoData.employeeSecondAccount.uid,
            note: 'Wochenend-Ausgabe',
          ),
        ],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, -1, 17),
      ),
      SiteOrderList(
        id: paket,
        orgId: orgId,
        siteId: paket,
        siteName: paketSiteName,
        items: const [],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, -1, 16),
      ),
    ];
  }

  static List<SiteOrderList> weeklyOrderListsForOrg({
    required String orgId,
    required String updatedByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    SiteOrderList list(
      String siteId,
      String siteName,
      List<OrderListItem> items,
    ) => SiteOrderList(
      id: siteId,
      orgId: orgId,
      siteId: siteId,
      siteName: siteName,
      kind: OrderListKind.weeklyTemplate,
      items: items,
      updatedByUid: updatedByUid,
      updatedAt: _day(now, -7, 12),
    );

    return [
      list(tabak, tabakSiteName, [
        OrderListItem(
          productId: productId(orgId, 'tabak', 'cola'),
          name: 'Cola 0,5 l',
          sku: 'GET-COLA-050',
          category: 'Getränke',
          unit: 'Flasche',
          quantity: 24,
          supplierId: supplierId(orgId, 'getraenke'),
          supplierName: 'Förde Getränke Service KG',
          addedByUid: updatedByUid,
        ),
        OrderListItem(
          productId: productId(orgId, 'tabak', 'chips'),
          name: 'Kartoffelchips Paprika',
          sku: 'SNK-CHIPS-PAP',
          category: 'Snacks',
          quantity: 12,
          supplierId: supplierId(orgId, 'getraenke'),
          supplierName: 'Förde Getränke Service KG',
          addedByUid: updatedByUid,
        ),
      ]),
      list(strich, strichSiteName, [
        OrderListItem(
          productId: productId(orgId, 'strich', 'pueblo'),
          name: 'Pueblo Tabak 30 g',
          sku: 'TAB-PUE-030',
          category: 'Drehtabak',
          quantity: 10,
          supplierId: supplierId(orgId, 'tabak'),
          supplierName: 'Nord Tabakwaren GmbH',
          addedByUid: updatedByUid,
        ),
      ]),
      list(paket, paketSiteName, [
        OrderListItem(
          productId: productId(orgId, 'paket', 'karton-s'),
          name: 'Versandkarton S',
          sku: 'VER-KARTON-S',
          category: 'Verpackung',
          quantity: 50,
          supplierId: supplierId(orgId, 'verpackung'),
          supplierName: 'NordPack Versandbedarf e.K.',
          addedByUid: updatedByUid,
        ),
      ]),
    ];
  }

  static List<FridgeRefillList> fridgeRefillListsForOrg({
    required String orgId,
    required String updatedByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      FridgeRefillList(
        id: tabak,
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        items: [
          FridgeRefillItem(
            id: 'demo-fridge-item-$orgId-tabak-cola',
            productId: productId(orgId, 'tabak', 'cola'),
            name: 'Cola 0,5 l',
            category: 'Getränke',
            unit: 'Flasche',
            quantity: 10,
            note: 'Untere Reihe zuerst',
            addedByUid: updatedByUid,
            addedByName: 'Demo Admin',
            addedAt: _day(now, -1, 8),
          ),
          FridgeRefillItem(
            id: 'demo-fridge-item-$orgId-tabak-freetext',
            name: 'Eiswürfel-Beutel',
            category: 'Sonstiges',
            quantity: 2,
            done: true,
            addedByUid: updatedByUid,
            addedByName: 'Demo Admin',
            addedAt: _day(now, -2, 8),
          ),
        ],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, -1, 8),
      ),
      FridgeRefillList(
        id: strich,
        orgId: orgId,
        siteId: strich,
        siteName: strichSiteName,
        items: [
          FridgeRefillItem(
            id: 'demo-fridge-item-$orgId-strich-cola-done',
            productId: productId(orgId, 'strich', 'cola'),
            name: 'Cola 0,5 l',
            category: 'Getränke',
            unit: 'Flasche',
            quantity: 6,
            done: true,
            addedByUid: updatedByUid,
            addedByName: 'Demo Admin',
            addedAt: _day(now, -1, 7),
          ),
        ],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, -1, 8),
      ),
      FridgeRefillList(
        id: paket,
        orgId: orgId,
        siteId: paket,
        siteName: paketSiteName,
        items: [
          FridgeRefillItem(
            id: 'demo-fridge-item-$orgId-paket-wasser',
            productId: productId(orgId, 'paket', 'wasser'),
            name: 'Mineralwasser 0,5 l',
            category: 'Getränke',
            unit: 'Flasche',
            quantity: 6,
            addedByUid: LocalDemoData.employeeAccount.uid,
            addedByName: LocalDemoData.employeeAccount.name,
            addedAt: _day(now, 0, 7),
          ),
        ],
        updatedByUid: updatedByUid,
        updatedAt: _day(now, 0, 7),
      ),
    ];
  }

  static List<Contact> contactsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final hansenId = contactId(orgId, 'joerg-hansen');
    final petersenId = contactId(orgId, 'petra-petersen');
    final nordTabakId = contactId(orgId, 'nord-tabak');
    final baseCreatedAt = _day(now, -300, 9);

    return [
      Contact(
        id: hansenId,
        orgId: orgId,
        name: 'Jörg Hansen',
        type: ContactType.customer,
        kind: ContactKind.person,
        status: ContactStatus.aktiv,
        alias: 'Jörg (Stammkunde)',
        firstName: 'Jörg',
        lastName: 'Hansen',
        title: 'Herr',
        gender: Gender.maennlich,
        birthday: _day(DateTime(1982, 5, 17)),
        mobile: '+49 151 23456789',
        street: 'Holtenauer Straße 101',
        postalCode: '24105',
        city: 'Kiel',
        customerNumber: 'K-1007',
        notes: 'Stammkunde; bestellt regelmäßig Zigarren.',
        siteId: tabak,
        siteName: tabakSiteName,
        tags: const ['Stammkunde', 'Sonderbestellung', 'VIP'],
        activities: [
          ContactActivity(
            type: ContactActivityType.call,
            occurredAt: _day(now, -2, 10),
            note: 'Abholung für Freitag bestätigt.',
            createdByUid: createdByUid,
          ),
          ContactActivity(
            type: ContactActivityType.email,
            occurredAt: _day(now, -8, 14),
            note: 'Produktfoto gesendet.',
            createdByUid: createdByUid,
          ),
          ContactActivity(
            type: ContactActivityType.meeting,
            occurredAt: _day(now, -20, 16),
            note: 'Sortimentswunsch im Laden besprochen.',
            createdByUid: createdByUid,
          ),
          ContactActivity(
            type: ContactActivityType.note,
            occurredAt: _day(now, -25, 12),
            note: 'Bevorzugt telefonische Rückmeldung.',
            createdByUid: createdByUid,
          ),
          ContactActivity(
            type: ContactActivityType.task,
            occurredAt: _day(now, -1, 9),
            note: 'Bei Wareneingang anrufen.',
            createdByUid: createdByUid,
          ),
        ],
        addresses: [
          ContactAddress(
            id: 'demo-address-$orgId-hansen-delivery',
            type: AddressType.lieferung,
            label: 'Alternative Lieferung',
            street: 'Feldstraße',
            houseNumber: '20',
            zip: '24105',
            city: 'Kiel',
          ),
        ],
        channels: const [
          CommunicationChannel(
            type: ChannelType.mobile,
            value: '+49 151 23456789',
            context: CommunicationContext.privat,
            label: 'Privat',
            availability: 'Mo–Fr ab 16 Uhr',
            isPrimary: true,
          ),
        ],
        consents: [
          ContactConsent(
            id: 'demo-consent-$orgId-hansen-data',
            consentType: ConsentType.dataProcessing,
            grantedAt: _day(now, -300),
          ),
          ContactConsent(
            id: 'demo-consent-$orgId-hansen-email',
            consentType: ConsentType.emailContact,
            grantedAt: _day(now, -200),
            withdrawnAt: _day(now, -30),
            note: 'Newsletter abbestellt.',
          ),
          ContactConsent(
            id: 'demo-consent-$orgId-hansen-phone',
            consentType: ConsentType.phoneContact,
            grantedAt: _day(now, -250),
          ),
          ContactConsent(
            id: 'demo-consent-$orgId-hansen-sharing',
            consentType: ConsentType.dataSharing,
            grantedAt: _day(now, -100),
            withdrawnAt: _day(now, -10),
          ),
        ],
        customerSince: _day(now, -500),
        isFavorite: true,
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
        updatedAt: _day(now, -1, 9),
      ),
      Contact(
        id: petersenId,
        orgId: orgId,
        name: 'Petra Petersen',
        type: ContactType.other,
        kind: ContactKind.person,
        status: ContactStatus.aktiv,
        firstName: 'Petra',
        lastName: 'Petersen',
        gender: Gender.weiblich,
        position: 'Key Account Managerin',
        department: 'Vertrieb',
        email: 'petra.petersen@nord-tabak.example',
        phone: '+49 431 555101',
        parentContactId: nordTabakId,
        tags: const ['Ansprechpartnerin'],
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
        updatedAt: _day(now, -7),
      ),
      Contact(
        id: nordTabakId,
        orgId: orgId,
        name: 'Nord Tabakwaren GmbH',
        type: ContactType.wholesaler,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        contactPerson: 'Petra Petersen',
        email: 'service@nord-tabak.example',
        phone: '+49 431 555100',
        mobile: '+49 171 5551000',
        website: 'https://nord-tabak.example',
        street: 'Eichhofstraße 12',
        postalCode: '24116',
        city: 'Kiel',
        taxId: 'DE123456789',
        customerNumber: 'KD-4711',
        notes: 'Hauptlieferant für Tabakwaren.',
        tags: const ['Tabak', 'Stammlieferant'],
        addresses: [
          ContactAddress(
            id: 'demo-address-$orgId-nord-main',
            type: AddressType.haupt,
            label: 'Zentrale',
            street: 'Eichhofstraße',
            houseNumber: '12',
            zip: '24116',
            city: 'Kiel',
          ),
          ContactAddress(
            id: 'demo-address-$orgId-nord-invoice',
            type: AddressType.rechnung,
            label: 'Buchhaltung',
            postbox: 'Postfach 2020',
            postboxZip: '24019',
            city: 'Kiel',
          ),
          ContactAddress(
            id: 'demo-address-$orgId-nord-delivery',
            type: AddressType.lieferung,
            label: 'Lager',
            street: 'Industrieweg',
            houseNumber: '7',
            zip: '24145',
            city: 'Kiel',
            addressExtra: 'Tor 3',
          ),
          ContactAddress(
            id: 'demo-address-$orgId-nord-branch',
            type: AddressType.niederlassung,
            label: 'Niederlassung Lübeck',
            street: 'Hafenstraße',
            houseNumber: '4',
            zip: '23568',
            city: 'Lübeck',
          ),
        ],
        channels: const [
          CommunicationChannel(
            type: ChannelType.email,
            value: 'service@nord-tabak.example',
            context: CommunicationContext.firma,
            isPrimary: true,
          ),
          CommunicationChannel(
            type: ChannelType.phone,
            value: '+49 431 555100',
            context: CommunicationContext.firma,
            availability: 'Mo–Fr 08:00–17:00',
          ),
          CommunicationChannel(
            type: ChannelType.mobile,
            value: '+49 171 5551000',
            context: CommunicationContext.dienst,
          ),
          CommunicationChannel(
            type: ChannelType.fax,
            value: '+49 431 555109',
            context: CommunicationContext.firma,
          ),
          CommunicationChannel(
            type: ChannelType.website,
            value: 'https://nord-tabak.example',
            context: CommunicationContext.firma,
          ),
        ],
        contactPersons: [
          ContactPerson(
            id: 'demo-contact-person-$orgId-nord-petersen',
            personContactId: petersenId,
            role: 'Key Account',
            isPrimary: true,
          ),
        ],
        bankAccounts: const [
          BankAccount(
            id: 'demo-bank-nord-tabak',
            iban: 'DE02120300000000202051',
            bic: 'BYLADEM1001',
            bankName: 'Demo Bank Nord',
            accountHolder: 'Nord Tabakwaren GmbH',
          ),
          BankAccount(
            id: 'demo-bank-nord-tabak-old',
            iban: 'DE12500105170648489890',
            bankName: 'Historische Bank',
            deactivated: true,
          ),
        ],
        companyName: 'Nord Tabakwaren GmbH',
        legalName: 'Nord Tabakwaren Handelsgesellschaft mbH',
        registrationNumber: 'HRB 12345 KI',
        companyAnniversary: _day(DateTime(1998, 4, 1)),
        creditorNumber: 'KRED-1000',
        isFavorite: true,
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
        updatedAt: _day(now, -7),
      ),
      Contact(
        id: contactId(orgId, 'pressevertrieb'),
        orgId: orgId,
        name: 'Kieler Pressevertrieb',
        type: ContactType.supplier,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        contactPerson: 'Olaf Brandt',
        email: 'service@kieler-presse.example',
        phone: '+49 431 555300',
        siteId: strich,
        siteName: strichSiteName,
        creditorNumber: 'KRED-1100',
        tags: const ['Presse', 'Remission'],
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'foerde-getraenke'),
        orgId: orgId,
        name: 'Förde Getränke Service KG',
        type: ContactType.serviceProvider,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        contactPerson: 'Nils Voss',
        email: 'info@foerde-getraenke.example',
        phone: '+49 431 555200',
        siteId: paket,
        siteName: paketSiteName,
        notes: 'Lieferung und Kühlschrank-Wartung.',
        creditorNumber: 'KRED-1200',
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'nordpack'),
        orgId: orgId,
        name: 'NordPack Versandbedarf e.K.',
        type: ContactType.company,
        kind: ContactKind.company,
        status: ContactStatus.inaktiv,
        contactPerson: 'Samira Yilmaz',
        email: 'kontakt@nordpack.example',
        website: 'https://nordpack.example',
        notes: 'Rahmenvertrag wird neu verhandelt.',
        creditorNumber: 'KRED-1300',
        isActive: false,
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'hauptzollamt'),
        orgId: orgId,
        name: 'Hauptzollamt Kiel',
        type: ContactType.authority,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        email: 'poststelle@zoll.example',
        phone: '+49 431 200840',
        street: 'Am Sophienhof 11',
        postalCode: '24114',
        city: 'Kiel',
        tags: const ['Tabaksteuer', 'Behörde'],
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'hausverwaltung'),
        orgId: orgId,
        name: 'Hausverwaltung Möller',
        type: ContactType.landlord,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        contactPerson: 'Eva Möller',
        email: 'verwaltung@moeller.example',
        phone: '+49 431 445566',
        siteId: tabak,
        siteName: tabakSiteName,
        notes: 'Mietobjekt Ladenfläche.',
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'bank'),
        orgId: orgId,
        name: 'Demo Fördebank',
        type: ContactType.bankInsurance,
        kind: ContactKind.company,
        status: ContactStatus.gesperrt,
        contactPerson: 'Max Muster',
        email: 'firmenkunden@foerdebank.example',
        phone: '+49 431 111222',
        notes: 'Gesperrter Testkontakt – Ansprechpartner ausgeschieden.',
        blacklisted: true,
        isActive: false,
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'steuerkanzlei'),
        orgId: orgId,
        name: 'Steuerkanzlei Albrecht & Partner',
        type: ContactType.taxAdvisor,
        kind: ContactKind.company,
        status: ContactStatus.aktiv,
        contactPerson: 'Tobias Albrecht',
        email: 'kanzlei@albrecht.example',
        phone: '+49 431 778899',
        debitorNumber: 'DEB-9000',
        isFavorite: true,
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
      Contact(
        id: contactId(orgId, 'alex-divers'),
        orgId: orgId,
        name: 'Alex Sommer',
        type: ContactType.other,
        kind: ContactKind.person,
        status: ContactStatus.aktiv,
        firstName: 'Alex',
        lastName: 'Sommer',
        gender: Gender.divers,
        email: 'alex.sommer@example.invalid',
        notes: 'Testdatensatz für diverse Anrede.',
        createdByUid: createdByUid,
        createdAt: baseCreatedAt,
      ),
    ];
  }

  static List<ContactOrganization> contactOrganizationsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    const names = <OrganizationType, String>{
      OrganizationType.agenturFuerArbeit: 'Agentur für Arbeit Kiel',
      OrganizationType.jobcenter: 'Jobcenter Kiel',
      OrganizationType.praktikumsbetrieb: 'Berufsschule am Ravensberg',
      OrganizationType.kooperationspartner: 'Kieler Innenstadt e.V.',
      OrganizationType.behoerde: 'Landeshauptstadt Kiel – Gewerbeamt',
      OrganizationType.sonstige: 'Ehemaliger Branchenverband',
    };
    return [
      for (final type in OrganizationType.values)
        ContactOrganization(
          id: 'demo-contact-org-$orgId-${type.value}',
          orgId: orgId,
          name: names[type]!,
          type: type,
          city: type == OrganizationType.sonstige ? null : 'Kiel',
          website:
              type == OrganizationType.sonstige
                  ? null
                  : 'https://${type.value.replaceAll('_', '-')}.example',
          isActive: type != OrganizationType.sonstige,
          createdByUid: createdByUid,
          createdAt: _day(now, -180),
          updatedAt: _day(now, -10),
        ),
    ];
  }

  static List<CustomerWish> customerWishesForOrg({
    required String orgId,
    required String handledByUid,
    DateTime? now,
  }) {
    const wishText = <CustomerWishCategory, String>{
      CustomerWishCategory.magazine: 'Geo Epoche – Ausgabe Hanse',
      CustomerWishCategory.cigarettes: 'Eine Stange Marlboro Gold',
      CustomerWishCategory.tobacco: 'Pueblo Tabak 30 g',
      CustomerWishCategory.other: 'Postkarten mit Kiel-Motiv',
    };
    const storeNames = [tabakSiteName, strichSiteName, paketSiteName];
    final result = <CustomerWish>[];
    for (final category in CustomerWishCategory.values) {
      for (final status in CustomerWishStatus.values) {
        final index =
            category.index * CustomerWishStatus.values.length + status.index;
        final handled = status != CustomerWishStatus.pending;
        result.add(
          CustomerWish(
            id: wishId(orgId, category, status),
            orgId: orgId,
            referenceCode:
                'W${category.index + 2}${status.index + 2}-D${index + 10}',
            storeName: storeNames[index % storeNames.length],
            category: category,
            wishText: wishText[category]!,
            quantity: category == CustomerWishCategory.cigarettes ? 10 : 1,
            desiredDate: _day(now, status.index - 1),
            customerName: index.isEven ? 'Jörg Hansen' : null,
            customerContact: index.isEven ? '+49 151 23456789' : null,
            contactId: index.isEven ? contactId(orgId, 'joerg-hansen') : null,
            status: status,
            notes:
                status == CustomerWishStatus.rejected
                    ? 'Nicht über den Lieferanten verfügbar.'
                    : status == CustomerWishStatus.done
                    ? 'In Kundenbestellung übernommen.'
                    : null,
            handledByUid: handled ? handledByUid : null,
            handledAt: handled ? _day(now, -status.index, 15) : null,
            createdAt: _day(now, -20 + index, 11),
            updatedAt: handled ? _day(now, -status.index, 15) : null,
          ),
        );
      }
    }
    return result;
  }

  static List<CustomerFeedback> customerFeedbackForOrg({
    required String orgId,
    required String handledByUid,
    DateTime? now,
  }) {
    const messages = <FeedbackType, String>{
      FeedbackType.complaint:
          'Die Warteschlange am Paketshop war heute sehr lang.',
      FeedbackType.suggestion:
          'Bitte eine klarere Beschilderung für Retouren aufstellen.',
      FeedbackType.praise:
          'Sehr freundliche Hilfe bei meiner Sonderbestellung.',
    };
    const storeNames = [tabakSiteName, strichSiteName, paketSiteName];
    final result = <CustomerFeedback>[];
    for (final type in FeedbackType.values) {
      for (final status in FeedbackStatus.values) {
        final index = type.index * FeedbackStatus.values.length + status.index;
        final handled = status != FeedbackStatus.pending;
        result.add(
          CustomerFeedback(
            id: feedbackId(orgId, type, status),
            orgId: orgId,
            referenceCode:
                'F${type.index + 3}${status.index + 3}-D${index + 20}',
            type: type,
            message: messages[type]!,
            storeName: storeNames[index % storeNames.length],
            rating:
                status == FeedbackStatus.rejected
                    ? null
                    : switch (type) {
                      FeedbackType.complaint => 1,
                      FeedbackType.suggestion => 3,
                      FeedbackType.praise => 5,
                    },
            incidentDate: _day(now, -index - 1, 17),
            customerName: index.isEven ? 'Jörg Hansen' : null,
            customerContact: index.isEven ? 'hansen@example.invalid' : null,
            contactId: index.isEven ? contactId(orgId, 'joerg-hansen') : null,
            status: status,
            notes:
                status == FeedbackStatus.done
                    ? 'Rückmeldung persönlich beantwortet.'
                    : status == FeedbackStatus.rejected
                    ? 'Test-/Spam-Eintrag geschlossen.'
                    : null,
            handledByUid: handled ? handledByUid : null,
            handledAt: handled ? _day(now, -status.index, 16) : null,
            createdAt: _day(now, -30 + index, 18),
            updatedAt: handled ? _day(now, -status.index, 16) : null,
          ),
        );
      }
    }
    return result;
  }

  static List<CustomerOrder> customerOrdersForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final hansen = contactId(orgId, 'joerg-hansen');
    return [
      CustomerOrder(
        id: 'demo-customer-order-$orgId-open-overdue',
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        customerName: 'Jörg Hansen',
        customerContact: '+49 151 23456789',
        contactId: hansen,
        orderNumber: 'DEMO-KB-OFFEN',
        status: CustomerOrderStatus.open,
        recurrence: CustomerOrderRecurrence.weekly,
        items: [
          CustomerOrderItem(
            productId: productId(orgId, 'tabak', 'marlboro'),
            name: 'Marlboro Rot (Packung)',
            sku: 'TAB-MAR-ROT',
            category: 'Zigaretten',
            quantity: 10,
            unitPriceCents: 1010,
          ),
        ],
        notes: 'Überfällig und noch nicht vorbereitet.',
        pickupDate: _day(now, -1),
        sourceWishId: wishId(
          orgId,
          CustomerWishCategory.cigarettes,
          CustomerWishStatus.done,
        ),
        createdByUid: createdByUid,
        createdAt: _day(now, -7, 10),
        updatedAt: _day(now, -2, 10),
      ),
      CustomerOrder(
        id: 'demo-customer-order-$orgId-prepared',
        orgId: orgId,
        siteId: strich,
        siteName: strichSiteName,
        customerName: 'Mira König',
        customerContact: 'mira.koenig@example.invalid',
        orderNumber: 'DEMO-KB-BEREIT',
        status: CustomerOrderStatus.prepared,
        recurrence: CustomerOrderRecurrence.monthly,
        items: [
          CustomerOrderItem(
            productId: productId(orgId, 'strich', 'spiegel'),
            name: 'Der Spiegel',
            sku: 'PRE-SPIEGEL',
            category: 'Presse',
            quantity: 1,
            unitPriceCents: 620,
          ),
        ],
        pickupDate: _day(now, 1),
        preparedAt: _day(now, 0, 8),
        sourceWishId: wishId(
          orgId,
          CustomerWishCategory.magazine,
          CustomerWishStatus.done,
        ),
        createdByUid: createdByUid,
        createdAt: _day(now, -5, 10),
        updatedAt: _day(now, 0, 8),
      ),
      CustomerOrder(
        id: 'demo-customer-order-$orgId-picked-up',
        orgId: orgId,
        siteId: paket,
        siteName: paketSiteName,
        customerName: 'Café Fördeblick',
        customerContact: '+49 431 998877',
        orderNumber: 'DEMO-KB-ABGEHOLT',
        status: CustomerOrderStatus.pickedUp,
        recurrence: CustomerOrderRecurrence.none,
        items: [
          CustomerOrderItem(
            productId: productId(orgId, 'paket', 'wasser'),
            name: 'Mineralwasser 0,5 l',
            sku: 'GET-WASSER-050',
            category: 'Getränke',
            unit: 'Flasche',
            quantity: 12,
            unitPriceCents: 130,
          ),
        ],
        pickupDate: _day(now, -4),
        preparedAt: _day(now, -5, 17),
        createdByUid: createdByUid,
        createdAt: _day(now, -10, 10),
        updatedAt: _day(now, -4, 14),
      ),
      CustomerOrder(
        id: 'demo-customer-order-$orgId-cancelled',
        orgId: orgId,
        siteId: tabak,
        siteName: tabakSiteName,
        customerName: 'Laufkundschaft Demo',
        orderNumber: 'DEMO-KB-STORNIERT',
        status: CustomerOrderStatus.cancelled,
        recurrence: CustomerOrderRecurrence.none,
        items: const [
          CustomerOrderItem(
            name: 'Nicht geführte Zigarrenkiste',
            category: 'Zigarren',
            quantity: 1,
          ),
        ],
        notes: 'Kunde hat die Bestellung telefonisch storniert.',
        pickupDate: _day(now, 3),
        createdByUid: createdByUid,
        createdAt: _day(now, -3, 10),
        updatedAt: _day(now, -1, 15),
      ),
    ];
  }

  /// Cloud-only Verkaufsfakten fuer Auswertungen. Der Aufrufer darf diese
  /// Liste anzeigen/berechnen, aber nicht in den lokalen Cache schreiben.
  static List<PosReceipt> posReceiptsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final day = _dayKey(_day(now));
    final oldDay = _dayKey(_day(now, -40));
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final receipts = <PosReceipt>[
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-sale-tabak',
        orgId: orgId,
        siteId: tabak,
        cashRegisterId: 1,
        referenceNumber: 'DEMO-POS-SALE-1',
        type: 'sales',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 10),
        grossCents: 1808,
        taxes: const [
          ReceiptTax(
            ratePercent: 7,
            netCents: 335,
            taxCents: 23,
            grossCents: 358,
          ),
          ReceiptTax(
            ratePercent: 19,
            netCents: 1218,
            taxCents: 232,
            grossCents: 1450,
          ),
        ],
        payments: const [
          PaymentLine(method: 'cash', amountCents: 858),
          PaymentLine(method: 'card', amountCents: 950, subType: 'girocard'),
        ],
        lines: [
          PosReceiptLine(
            productId: productId(orgId, 'tabak', 'chips'),
            name: 'Kartoffelchips Paprika',
            externalReference: 'POS-CHIPS-PAP',
            scannedBarcode: '4012345678901',
            category: 'Snacks',
            quantity: 2,
            unitPriceCents: 179,
          ),
          PosReceiptLine(
            productId: productId(orgId, 'tabak', 'cola'),
            name: 'Cola 0,5 l',
            externalReference: 'POS-COLA-050',
            scannedBarcode: '4006381333931',
            category: 'Getränke',
            quantity: 2,
            unitPriceCents: 220,
          ),
          PosReceiptLine(
            productId: productId(orgId, 'tabak', 'marlboro'),
            name: 'Marlboro Rot (Packung)',
            externalReference: 'POS-MAR-ROT',
            scannedBarcode: '4242424242420',
            category: 'Zigaretten',
            quantity: 1,
            unitPriceCents: 1010,
          ),
        ],
        cashierId: LocalDemoData.employeeAccount.uid,
        customerId: contactId(orgId, 'joerg-hansen'),
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-refund-negative',
        orgId: orgId,
        siteId: tabak,
        cashRegisterId: 1,
        referenceNumber: 'DEMO-POS-REFUND-NEG',
        type: 'refund',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 12),
        grossCents: -220,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: -185,
            taxCents: -35,
            grossCents: -220,
          ),
        ],
        payments: const [PaymentLine(method: 'cash', amountCents: -220)],
        lines: [
          PosReceiptLine(
            productId: productId(orgId, 'tabak', 'cola'),
            name: 'Cola 0,5 l',
            externalReference: 'POS-COLA-050',
            scannedBarcode: '4006381333931',
            category: 'Getränke',
            quantity: -1,
            unitPriceCents: 220,
          ),
        ],
        cashierId: LocalDemoData.employeeAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-cash-movement',
        orgId: orgId,
        siteId: tabak,
        cashRegisterId: 1,
        referenceNumber: 'DEMO-POS-CASH-1',
        type: 'cash',
        businessDay: day,
        transactionDate: _day(now, 0, 8),
        grossCents: 10000,
        payments: const [
          PaymentLine(method: 'cash', amountCents: 10000, subType: 'deposit'),
        ],
        cashierId: LocalDemoData.adminAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-sale-strich',
        orgId: orgId,
        siteId: strich,
        cashRegisterId: 2,
        referenceNumber: 'DEMO-POS-SALE-STRICH',
        type: 'sales',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 11),
        grossCents: 690,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 580,
            taxCents: 110,
            grossCents: 690,
          ),
        ],
        payments: const [
          PaymentLine(method: 'card', amountCents: 690, subType: 'visa'),
        ],
        lines: [
          PosReceiptLine(
            productId: productId(orgId, 'strich', 'pueblo'),
            name: 'Pueblo Tabak 30 g',
            externalReference: 'POS-PUE-030',
            scannedBarcode: '4023500999991',
            category: 'Drehtabak',
            quantity: 1,
            unitPriceCents: 690,
          ),
        ],
        cashierId: LocalDemoData.employeeSecondAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-refund-positive',
        orgId: orgId,
        siteId: strich,
        cashRegisterId: 2,
        referenceNumber: 'DEMO-POS-REFUND-POS',
        type: 'refund',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 13),
        grossCents: 300,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 252,
            taxCents: 48,
            grossCents: 300,
          ),
        ],
        payments: const [PaymentLine(method: 'card', amountCents: 300)],
        lines: const [
          PosReceiptLine(
            name: 'Unzugeordnete Retoure',
            category: 'Sonstiges',
            quantity: 1,
            unitPriceCents: 300,
          ),
        ],
        cashierId: LocalDemoData.employeeSecondAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-sale-paket',
        orgId: orgId,
        siteId: paket,
        cashRegisterId: 3,
        referenceNumber: 'DEMO-POS-SALE-PAKET',
        type: 'sales',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 9),
        grossCents: 389,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 327,
            taxCents: 62,
            grossCents: 389,
          ),
        ],
        payments: const [PaymentLine(method: 'cash', amountCents: 389)],
        lines: [
          PosReceiptLine(
            productId: productId(orgId, 'paket', 'wasser'),
            name: 'Mineralwasser 0,5 l',
            externalReference: 'POS-WASSER-050',
            scannedBarcode: '4100000000003',
            category: 'Getränke',
            quantity: 2,
            unitPriceCents: 130,
          ),
          PosReceiptLine(
            productId: productId(orgId, 'paket', 'karton-s'),
            name: 'Versandkarton S',
            category: 'Verpackung',
            quantity: 1,
            unitPriceCents: 129,
          ),
        ],
        cashierId: LocalDemoData.teamLeadAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-uncovered',
        orgId: orgId,
        siteId: paket,
        cashRegisterId: 3,
        referenceNumber: 'DEMO-POS-UNCOVERED',
        type: 'sales',
        isRevenue: true,
        businessDay: day,
        transactionDate: _day(now, 0, 15),
        grossCents: 500,
        payments: const [PaymentLine(method: 'unknown', amountCents: 500)],
        lines: const [
          PosReceiptLine(
            name: 'Nicht zugeordneter Kassenartikel',
            category: 'Sonstiges',
            quantity: 1,
            unitPriceCents: 500,
          ),
        ],
        cashierId: LocalDemoData.teamLeadAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-training',
        orgId: orgId,
        siteId: paket,
        cashRegisterId: 3,
        referenceNumber: 'DEMO-POS-TRAINING',
        type: 'sales',
        training: true,
        businessDay: day,
        transactionDate: _day(now, 0, 16),
        grossCents: 999,
        payments: const [PaymentLine(method: 'cash', amountCents: 999)],
        lines: const [
          PosReceiptLine(
            name: 'Schulungsartikel',
            quantity: 1,
            unitPriceCents: 999,
          ),
        ],
        cashierId: LocalDemoData.employeeAccount.uid,
      ),
      PosReceipt(
        id: 'demo-pos-receipt-$orgId-old-sale',
        orgId: orgId,
        siteId: strich,
        cashRegisterId: 2,
        referenceNumber: 'DEMO-POS-OLD-SALE',
        type: 'sales',
        isRevenue: true,
        businessDay: oldDay,
        transactionDate: _day(now, -40, 11),
        grossCents: 300,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 252,
            taxCents: 48,
            grossCents: 300,
          ),
        ],
        payments: const [PaymentLine(method: 'cash', amountCents: 300)],
        lines: [
          PosReceiptLine(
            productId: productId(orgId, 'strich', 'clipper'),
            name: 'Feuerzeug Clipper',
            scannedBarcode: '4051234567896',
            category: 'Raucherbedarf',
            quantity: 2,
            unitPriceCents: 150,
          ),
        ],
      ),
    ];

    // Belastbare 28-Tage-Historie fuer die Default-Auswertungen. Je Standort
    // haben sechs Kassierer exakt 30 Vorgaenge; der sechste weist eine deutlich
    // hoehere Refund-Quote auf. Damit bleiben die produktiven Schwellenwerte
    // (minTransactions=30, zThreshold=2) auch in der Demo unveraendert und die
    // Ansicht zeigt trotzdem einen pruefbaren Verdachtshinweis.
    const cashierIds = <String>[
      'local-demo-admin',
      'local-test-peter',
      'local-test-maria',
      'local-test-lea',
      'local-demo-jowan',
      'local-demo-majd',
    ];
    final siteFixtures = <
      ({
        String siteKey,
        String siteId,
        int register,
        String primaryKey,
        String primaryName,
        String primaryCategory,
        int primaryPrice,
        String secondaryKey,
        String secondaryName,
        String secondaryCategory,
        int secondaryPrice,
      })
    >[
      (
        siteKey: 'tabak',
        siteId: tabak,
        register: 1,
        primaryKey: 'chips',
        primaryName: 'Kartoffelchips Paprika',
        primaryCategory: 'Snacks',
        primaryPrice: 179,
        secondaryKey: 'cola',
        secondaryName: 'Cola 0,5 l',
        secondaryCategory: 'Getraenke',
        secondaryPrice: 220,
      ),
      (
        siteKey: 'strich',
        siteId: strich,
        register: 2,
        primaryKey: 'pueblo',
        primaryName: 'Pueblo Tabak 30 g',
        primaryCategory: 'Drehtabak',
        primaryPrice: 690,
        secondaryKey: 'clipper',
        secondaryName: 'Feuerzeug Clipper',
        secondaryCategory: 'Raucherbedarf',
        secondaryPrice: 150,
      ),
      (
        siteKey: 'paket',
        siteId: paket,
        register: 3,
        primaryKey: 'wasser',
        primaryName: 'Mineralwasser 0,5 l',
        primaryCategory: 'Getraenke',
        primaryPrice: 130,
        secondaryKey: 'karton-s',
        secondaryName: 'Versandkarton S',
        secondaryCategory: 'Verpackung',
        secondaryPrice: 129,
      ),
    ];

    for (final site in siteFixtures) {
      for (var index = 0; index < cashierIds.length * 30; index++) {
        final cashierIndex = index ~/ 30;
        final transactionForCashier = index % 30;
        final isRefund =
            cashierIndex == cashierIds.length - 1
                ? transactionForCashier < 10
                : transactionForCashier == 0;
        final dayOffset = (index % 27) + 1;
        final transactionDate = _day(
          now,
          -dayOffset,
          8 + (index % 11),
        ).add(Duration(minutes: (index * 7) % 60));
        final grossCents =
            isRefund
                ? -site.primaryPrice
                : site.primaryPrice + site.secondaryPrice;
        final netCents = (grossCents * 100 / 119).round();
        final serial = index.toString().padLeft(3, '0');
        receipts.add(
          PosReceipt(
            id: 'demo-pos-receipt-$orgId-history-${site.siteKey}-$serial',
            orgId: orgId,
            siteId: site.siteId,
            cashRegisterId: site.register,
            referenceNumber: 'DEMO-HIST-${site.siteKey.toUpperCase()}-$serial',
            type: isRefund ? 'refund' : 'sales',
            isRevenue: true,
            businessDay: _dayKey(transactionDate),
            transactionDate: transactionDate,
            grossCents: grossCents,
            taxes: [
              ReceiptTax(
                ratePercent: 19,
                netCents: netCents,
                taxCents: grossCents - netCents,
                grossCents: grossCents,
              ),
            ],
            payments: [
              PaymentLine(
                method: index.isEven ? 'cash' : 'card',
                amountCents: grossCents,
              ),
            ],
            lines: [
              PosReceiptLine(
                productId: productId(orgId, site.siteKey, site.primaryKey),
                name: site.primaryName,
                category: site.primaryCategory,
                quantity: isRefund ? -1 : 1,
                unitPriceCents: site.primaryPrice,
              ),
              if (!isRefund)
                PosReceiptLine(
                  productId: productId(orgId, site.siteKey, site.secondaryKey),
                  name: site.secondaryName,
                  category: site.secondaryCategory,
                  quantity: 1,
                  unitPriceCents: site.secondaryPrice,
                ),
            ],
            cashierId: cashierIds[cashierIndex],
            customerId:
                !isRefund && index % 5 == 0
                    ? contactId(orgId, 'joerg-hansen')
                    : null,
          ),
        );
      }
    }
    return receipts;
  }

  /// Cloud-only Tagesaggregate passend zu [posReceiptsForOrg].
  static List<PosDailyStat> posDailyStatsForOrg({
    required String orgId,
    DateTime? now,
  }) {
    final date = _day(now);
    final day = _dayKey(date);
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    final stats = <PosDailyStat>[
      PosDailyStat(
        id: 'demo-pos-daily-stat-$orgId-tabak-$day',
        orgId: orgId,
        siteId: tabak,
        businessDay: day,
        salesCount: 1,
        refundCount: 1,
        revenueGrossCents: 1588,
        revenueNetCents: 1368,
        taxes: const [
          ReceiptTax(
            ratePercent: 7,
            netCents: 335,
            taxCents: 23,
            grossCents: 358,
          ),
          ReceiptTax(
            ratePercent: 19,
            netCents: 1033,
            taxCents: 197,
            grossCents: 1230,
          ),
        ],
        paymentsByMethod: const {'cash': 638, 'card': 950},
        cashMovementCents: 10000,
        cogsCents: 1058,
        cogsCoveredGrossCents: 1588,
        updatedAt: _day(now, 0, 23),
      ),
      PosDailyStat(
        id: 'demo-pos-daily-stat-$orgId-strich-$day',
        orgId: orgId,
        siteId: strich,
        businessDay: day,
        salesCount: 1,
        refundCount: 1,
        positiveRefundCount: 1,
        revenueGrossCents: 990,
        revenueNetCents: 832,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 832,
            taxCents: 158,
            grossCents: 990,
          ),
        ],
        paymentsByMethod: const {'card': 990},
        cogsCents: 520,
        cogsCoveredGrossCents: 690,
        updatedAt: _day(now, 0, 23),
      ),
      PosDailyStat(
        id: 'demo-pos-daily-stat-$orgId-paket-$day',
        orgId: orgId,
        siteId: paket,
        businessDay: day,
        salesCount: 2,
        revenueGrossCents: 889,
        revenueNetCents: 327,
        netUncoveredGrossCents: 500,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 327,
            taxCents: 62,
            grossCents: 389,
          ),
        ],
        paymentsByMethod: const {'cash': 389, 'unknown': 500},
        cogsCents: 114,
        cogsCoveredGrossCents: 389,
        updatedAt: _day(now, 0, 23),
      ),
    ];
    final historical = dailyStatsFromReceipts(
      posReceiptsForOrg(orgId: orgId, now: now),
      productsForOrg(
        orgId: orgId,
        createdByUid: LocalDemoData.adminAccount.uid,
        now: now,
      ),
      purchasePricesIncludeVat: false,
    );
    for (final stat in historical.where((item) => item.businessDay != day)) {
      stats.add(
        PosDailyStat(
          id: 'demo-pos-daily-stat-$orgId-${stat.siteId}-${stat.businessDay}',
          orgId: stat.orgId,
          siteId: stat.siteId,
          businessDay: stat.businessDay,
          salesCount: stat.salesCount,
          refundCount: stat.refundCount,
          positiveRefundCount: stat.positiveRefundCount,
          revenueGrossCents: stat.revenueGrossCents,
          revenueNetCents: stat.revenueNetCents,
          netUncoveredGrossCents: stat.netUncoveredGrossCents,
          taxes: stat.taxes,
          paymentsByMethod: stat.paymentsByMethod,
          cashMovementCents: stat.cashMovementCents,
          cogsCents: stat.cogsCents,
          cogsCoveredGrossCents: stat.cogsCoveredGrossCents,
          updatedAt: _day(now, 0, 23),
        ),
      );
    }
    return stats;
  }

  /// Cloud-only, unveraenderliche Zaehldaten fuer Kassenansichten.
  static List<CashCount> cashCountsForOrg({
    required String orgId,
    required String createdByUid,
    DateTime? now,
  }) {
    final day = _dayKey(_day(now));
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      CashCount(
        id: 'demo-cash-count-$orgId-tabak-exact',
        orgId: orgId,
        siteId: tabak,
        cashRegisterId: 1,
        businessDay: day,
        countedAt: _day(now, 0, 19),
        countedCents: 50638,
        expectedCents: 50638,
        differenceCents: 0,
        denominations: const {
          '50.00': 6,
          '20.00': 8,
          '10.00': 3,
          '5.00': 1,
          '2.00': 2,
          '1.00': 1,
          '0.50': 4,
          '0.20': 4,
          '0.10': 3,
          '0.05': 1,
        },
        note: 'Kasse stimmt centgenau.',
        countedByLabel: 'Demo Admin',
        countedByUserId: createdByUid,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'lotto',
            typeName: 'Lotto',
            amountCents: 12500,
            expectedCents: 12000,
            note: 'Separat gezählt',
          ),
        ],
        createdByUid: createdByUid,
        createdAt: _day(now, 0, 19),
      ),
      CashCount(
        id: 'demo-cash-count-$orgId-strich-over',
        orgId: orgId,
        siteId: strich,
        cashRegisterId: 2,
        businessDay: day,
        countedAt: _day(now, 0, 19),
        countedCents: 31490,
        expectedCents: 30990,
        differenceCents: 500,
        note: 'Überbestand; Wechselgeld vom Vortag prüfen.',
        countedByLabel: LocalDemoData.employeeSecondAccount.name,
        countedByUserId: LocalDemoData.employeeSecondAccount.uid,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'lotto',
            typeName: 'Lotto',
            amountCents: 8000,
          ),
          ThirdPartyAmount(
            typeId: 'post',
            typeName: 'Deutsche Post',
            amountCents: 4200,
          ),
        ],
        createdByUid: createdByUid,
        createdAt: _day(now, 0, 19),
      ),
      CashCount(
        id: 'demo-cash-count-$orgId-paket-under',
        orgId: orgId,
        siteId: paket,
        cashRegisterId: 3,
        businessDay: day,
        countedAt: _day(now, 0, 19),
        countedCents: 25650,
        expectedCents: 26000,
        differenceCents: -350,
        note: 'Fehlbetrag zur Klärung.',
        countedByLabel: 'Demo Teamleitung',
        countedByUserId: LocalDemoData.teamLeadAccount.uid,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'post',
            typeName: 'Deutsche Post',
            amountCents: 15000,
          ),
          ThirdPartyAmount(
            typeId: 'kvg',
            typeName: 'KVG-Tickets',
            amountCents: 3200,
            expectedCents: 3200,
          ),
        ],
        createdByUid: createdByUid,
        createdAt: _day(now, 0, 19),
      ),
      CashCount(
        id: 'demo-cash-count-$orgId-paket-kiosk-blind',
        orgId: orgId,
        siteId: paket,
        cashRegisterId: 3,
        businessDay: day,
        countedAt: _day(now, 0, 18),
        countedCents: 25000,
        source: CashCount.sourceKiosk,
        countedByLabel: LocalDemoData.employeeAccount.name,
        countedByUserId: LocalDemoData.employeeAccount.uid,
        kioskSessionId: 'demo-kiosk-session-$orgId-paket',
        createdByUid: 'demo-kiosk-device-$orgId-paket',
        createdAt: _day(now, 0, 18),
      ),
    ];
  }

  /// Cloud-only, festgeschriebene Tagesabschluesse passend zu den Zaehldaten.
  static List<CashClosing> cashClosingsForOrg({
    required String orgId,
    required String closedByUid,
    DateTime? now,
  }) {
    final day = _dayKey(_day(now));
    final previousDay = _dayKey(_day(now, -1));
    final tabak = LocalDemoData.tabakSiteId(orgId);
    final strich = LocalDemoData.strichmaennchenSiteId(orgId);
    final paket = LocalDemoData.paketshopSiteId(orgId);
    return [
      CashClosing(
        id: 'demo-cash-closing-$orgId-tabak-$day',
        orgId: orgId,
        siteId: tabak,
        businessDay: day,
        salesCount: 1,
        refundCount: 1,
        revenueGrossCents: 1588,
        taxes: const [
          ReceiptTax(
            ratePercent: 7,
            netCents: 335,
            taxCents: 23,
            grossCents: 358,
          ),
          ReceiptTax(
            ratePercent: 19,
            netCents: 1033,
            taxCents: 197,
            grossCents: 1230,
          ),
        ],
        paymentsByMethod: const {'cash': 638, 'card': 950},
        cashMovementCents: 10000,
        cashExpectedCents: 50638,
        cashCountedCents: 50638,
        cashCountId: 'demo-cash-count-$orgId-tabak-exact',
        cashDifferenceCents: 0,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'lotto',
            typeName: 'Lotto',
            amountCents: 12500,
            expectedCents: 12000,
          ),
        ],
        closedByUid: closedByUid,
        closedAt: _day(now, 0, 20),
        note: 'Regulärer, noch nicht gebuchter Abschluss.',
      ),
      CashClosing(
        id: 'demo-cash-closing-$orgId-strich-$day',
        orgId: orgId,
        siteId: strich,
        businessDay: day,
        salesCount: 1,
        refundCount: 1,
        revenueGrossCents: 990,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 832,
            taxCents: 158,
            grossCents: 990,
          ),
        ],
        paymentsByMethod: const {'card': 990},
        cashExpectedCents: 30990,
        cashCountedCents: 31490,
        cashCountId: 'demo-cash-count-$orgId-strich-over',
        cashDifferenceCents: 500,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'lotto',
            typeName: 'Lotto',
            amountCents: 8000,
          ),
          ThirdPartyAmount(
            typeId: 'post',
            typeName: 'Deutsche Post',
            amountCents: 4200,
          ),
        ],
        bookedToFinance: true,
        closedByUid: closedByUid,
        closedAt: _day(now, 0, 20),
        note: 'Kassendifferenz bereits in Finanzen gebucht.',
      ),
      CashClosing(
        id: 'demo-cash-closing-$orgId-paket-$day',
        orgId: orgId,
        siteId: paket,
        businessDay: day,
        salesCount: 2,
        revenueGrossCents: 889,
        taxes: const [
          ReceiptTax(
            ratePercent: 19,
            netCents: 327,
            taxCents: 62,
            grossCents: 389,
          ),
        ],
        paymentsByMethod: const {'cash': 389, 'unknown': 500},
        cashExpectedCents: 26000,
        cashCountedCents: 25650,
        cashCountId: 'demo-cash-count-$orgId-paket-under',
        cashDifferenceCents: -350,
        thirdParty: const [
          ThirdPartyAmount(
            typeId: 'post',
            typeName: 'Deutsche Post',
            amountCents: 15000,
          ),
          ThirdPartyAmount(
            typeId: 'kvg',
            typeName: 'KVG-Tickets',
            amountCents: 3200,
            expectedCents: 3200,
          ),
        ],
        closedByUid: closedByUid,
        closedAt: _day(now, 0, 20),
        note: 'Fehlbetrag offen.',
      ),
      CashClosing(
        id: 'demo-cash-closing-$orgId-paket-$previousDay',
        orgId: orgId,
        siteId: paket,
        businessDay: previousDay,
        salesCount: 0,
        revenueGrossCents: 0,
        closedByUid: closedByUid,
        closedAt: _day(now, -1, 20),
        note: 'Abschluss ohne Zählung/Soll-Verankerung.',
      ),
    ];
  }

  /// Komfort-Bundle fuer Aufrufer, die alle Bereiche in einem Durchlauf
  /// benoetigen. Cloud-only Listen sind als solche benannt und bleiben reine
  /// In-Memory-Werte.
  static LocalDemoInventoryBundle allForOrg({
    required String orgId,
    required String actorUid,
    DateTime? now,
  }) => LocalDemoInventoryBundle(
    suppliers: suppliersForOrg(orgId: orgId, createdByUid: actorUid, now: now),
    products: productsForOrg(orgId: orgId, createdByUid: actorUid, now: now),
    productBatches: productBatchesForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    purchaseOrders: purchaseOrdersForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    stockMovements: stockMovementsForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    priceHistory: priceHistoryForOrg(
      orgId: orgId,
      changedByUid: actorUid,
      now: now,
    ),
    scanEvents: scanEventsForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    orderCarts: orderCartsForOrg(
      orgId: orgId,
      updatedByUid: actorUid,
      now: now,
    ),
    weeklyOrderLists: weeklyOrderListsForOrg(
      orgId: orgId,
      updatedByUid: actorUid,
      now: now,
    ),
    fridgeRefillLists: fridgeRefillListsForOrg(
      orgId: orgId,
      updatedByUid: actorUid,
      now: now,
    ),
    customerOrders: customerOrdersForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    contacts: contactsForOrg(orgId: orgId, createdByUid: actorUid, now: now),
    contactOrganizations: contactOrganizationsForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    customerWishes: customerWishesForOrg(
      orgId: orgId,
      handledByUid: actorUid,
      now: now,
    ),
    customerFeedback: customerFeedbackForOrg(
      orgId: orgId,
      handledByUid: actorUid,
      now: now,
    ),
    cloudPosReceipts: posReceiptsForOrg(orgId: orgId, now: now),
    cloudPosDailyStats: posDailyStatsForOrg(orgId: orgId, now: now),
    cloudCashCounts: cashCountsForOrg(
      orgId: orgId,
      createdByUid: actorUid,
      now: now,
    ),
    cloudCashClosings: cashClosingsForOrg(
      orgId: orgId,
      closedByUid: actorUid,
      now: now,
    ),
  );
}

/// Typisierter Rueckgabewert fuer [LocalDemoInventoryData.allForOrg].
class LocalDemoInventoryBundle {
  const LocalDemoInventoryBundle({
    required this.suppliers,
    required this.products,
    required this.productBatches,
    required this.purchaseOrders,
    required this.stockMovements,
    required this.priceHistory,
    required this.scanEvents,
    required this.orderCarts,
    required this.weeklyOrderLists,
    required this.fridgeRefillLists,
    required this.customerOrders,
    required this.contacts,
    required this.contactOrganizations,
    required this.customerWishes,
    required this.customerFeedback,
    required this.cloudPosReceipts,
    required this.cloudPosDailyStats,
    required this.cloudCashCounts,
    required this.cloudCashClosings,
  });

  final List<Supplier> suppliers;
  final List<Product> products;
  final List<ProductBatch> productBatches;
  final List<PurchaseOrder> purchaseOrders;
  final List<StockMovement> stockMovements;
  final List<PriceHistoryEntry> priceHistory;
  final List<ScanEvent> scanEvents;
  final List<SiteOrderList> orderCarts;
  final List<SiteOrderList> weeklyOrderLists;
  final List<FridgeRefillList> fridgeRefillLists;
  final List<CustomerOrder> customerOrders;
  final List<Contact> contacts;
  final List<ContactOrganization> contactOrganizations;
  final List<CustomerWish> customerWishes;
  final List<CustomerFeedback> customerFeedback;

  /// Nicht lokal persistieren; nur zum Testen von Cloud-Read-Ansichten.
  final List<PosReceipt> cloudPosReceipts;

  /// Nicht lokal persistieren; nur zum Testen von Cloud-Read-Ansichten.
  final List<PosDailyStat> cloudPosDailyStats;

  /// Nicht lokal persistieren; nur zum Testen von Cloud-Read-Ansichten.
  final List<CashCount> cloudCashCounts;

  /// Nicht lokal persistieren; nur zum Testen von Cloud-Read-Ansichten.
  final List<CashClosing> cloudCashClosings;
}
