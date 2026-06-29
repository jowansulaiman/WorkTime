import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'customer_wish.dart';

/// Status einer Kundenbestellung (Sonderbestellung).
enum CustomerOrderStatus {
  /// Angelegt, aber noch nicht vorbereitet.
  open,

  /// Ware liegt bereit zur Abholung.
  prepared,

  /// Vom Kunden abgeholt (abgeschlossen).
  pickedUp,

  /// Storniert.
  cancelled,
}

extension CustomerOrderStatusX on CustomerOrderStatus {
  String get value => switch (this) {
        CustomerOrderStatus.open => 'open',
        CustomerOrderStatus.prepared => 'prepared',
        CustomerOrderStatus.pickedUp => 'picked_up',
        CustomerOrderStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        CustomerOrderStatus.open => 'Offen',
        CustomerOrderStatus.prepared => 'Vorbereitet',
        CustomerOrderStatus.pickedUp => 'Abgeholt',
        CustomerOrderStatus.cancelled => 'Storniert',
      };

  /// Bestellung ist abgeschlossen (abgeholt oder storniert).
  bool get isClosed =>
      this == CustomerOrderStatus.pickedUp ||
      this == CustomerOrderStatus.cancelled;

  /// Bestellung ist noch offen (nicht abgeschlossen).
  bool get isOpen => !isClosed;

  static CustomerOrderStatus fromValue(String? value) => switch (value) {
        'prepared' => CustomerOrderStatus.prepared,
        'picked_up' => CustomerOrderStatus.pickedUp,
        'cancelled' => CustomerOrderStatus.cancelled,
        _ => CustomerOrderStatus.open,
      };
}

/// Wiederholungsrhythmus einer Kundenbestellung (z.B. Stammkunde, der jede
/// Woche oder jeden Monat bestimmte Ware abholt).
enum CustomerOrderRecurrence {
  /// Einmalige Bestellung.
  none,

  /// Wiederkehrend jede Woche.
  weekly,

  /// Wiederkehrend jeden Monat.
  monthly,
}

extension CustomerOrderRecurrenceX on CustomerOrderRecurrence {
  String get value => switch (this) {
        CustomerOrderRecurrence.none => 'none',
        CustomerOrderRecurrence.weekly => 'weekly',
        CustomerOrderRecurrence.monthly => 'monthly',
      };

  String get label => switch (this) {
        CustomerOrderRecurrence.none => 'Einmalig',
        CustomerOrderRecurrence.weekly => 'Wöchentlich',
        CustomerOrderRecurrence.monthly => 'Monatlich',
      };

  bool get isRecurring => this != CustomerOrderRecurrence.none;

  /// Schiebt [base] um einen Rhythmus nach vorne (für den Auto-Folgetermin).
  /// Bei [none] bleibt das Datum unverändert.
  DateTime advance(DateTime base) => switch (this) {
        CustomerOrderRecurrence.none => base,
        CustomerOrderRecurrence.weekly => base.add(const Duration(days: 7)),
        // Dart normalisiert Monat 13 -> nächstes Jahr; ein Tagesüberlauf
        // (z.B. 31. -> Folgemonat) ist für einen Laden unkritisch. Uhrzeit
        // (z.B. Mittag) bleibt erhalten.
        CustomerOrderRecurrence.monthly => DateTime(
            base.year,
            base.month + 1,
            base.day,
            base.hour,
            base.minute,
            base.second,
            base.millisecond,
            base.microsecond,
          ),
      };

  static CustomerOrderRecurrence fromValue(String? value) => switch (value) {
        'weekly' => CustomerOrderRecurrence.weekly,
        'monthly' => CustomerOrderRecurrence.monthly,
        _ => CustomerOrderRecurrence.none,
      };
}

/// Eine Position innerhalb einer Kundenbestellung (eingebettet, kein eigenes
/// Dokument). Spiegelt das Muster von `PurchaseOrderItem`, ergänzt um eine
/// freie [category] (Warengruppe, z.B. "Tabak", "Zeitschriften").
class CustomerOrderItem {
  const CustomerOrderItem({
    this.productId,
    required this.name,
    this.sku,
    this.category,
    this.unit = 'Stück',
    required this.quantity,
    this.unitPriceCents,
  });

  final String? productId;
  final String name;
  final String? sku;
  final String? category;
  final String unit;
  final int quantity;
  final int? unitPriceCents;

  /// Positionssumme in Cent (Menge * Einzelpreis).
  int get lineTotalCents {
    final price = unitPriceCents;
    if (price == null) {
      return 0;
    }
    return price * quantity;
  }

  factory CustomerOrderItem.fromMap(Map<String, dynamic> map) {
    return CustomerOrderItem(
      productId: (map['productId'] ?? map['product_id']) as String?,
      name: (map['name'] ?? '').toString(),
      sku: (map['sku']) as String?,
      category: (map['category']) as String?,
      unit: (map['unit'] ?? 'Stück').toString().trim().isEmpty
          ? 'Stück'
          : (map['unit'] ?? 'Stück').toString(),
      quantity: parse.toInt(map['quantity']) ?? 0,
      unitPriceCents:
          parse.toInt(map['unitPriceCents'] ?? map['unit_price_cents']),
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
      'unitPriceCents': unitPriceCents,
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
      'unit_price_cents': unitPriceCents,
    };
  }

  CustomerOrderItem copyWith({
    String? productId,
    String? name,
    String? sku,
    String? category,
    String? unit,
    int? quantity,
    int? unitPriceCents,
    bool clearUnitPrice = false,
    bool clearCategory = false,
    bool clearSku = false,
  }) {
    return CustomerOrderItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      sku: clearSku ? null : (sku ?? this.sku),
      category: clearCategory ? null : (category ?? this.category),
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPriceCents:
          clearUnitPrice ? null : (unitPriceCents ?? this.unitPriceCents),
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

/// Eine Sonderbestellung eines Kunden für einen Laden. Der Kunde holt die Ware
/// zu einem Abholtermin ([pickupDate]) ab; ist die Bestellung bis dahin nicht
/// vorbereitet ([preparedAt] == null), warnt die App den Mitarbeiter.
class CustomerOrder {
  const CustomerOrder({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    required this.customerName,
    this.customerContact,
    this.contactId,
    this.orderNumber,
    this.status = CustomerOrderStatus.open,
    this.recurrence = CustomerOrderRecurrence.none,
    this.items = const [],
    this.notes,
    this.pickupDate,
    this.preparedAt,
    this.sourceWishId,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  /// Erzeugt die Vorlage einer echten Kundenbestellung aus einem öffentlich
  /// abgegebenen [CustomerWish] (H-E1). Der Wunsch trägt nur einen
  /// Klartext-Ladennamen, daher werden der gewählte [siteId]/[siteName] separat
  /// übergeben. Trägt explizit die CRM-Verknüpfung [CustomerWish.contactId]
  /// (H-D2) und [CustomerWish.id] als [sourceWishId] mit — sonst gingen
  /// Kontakt-Zuordnung bzw. Idempotenz-Quelle beim Übergang verloren. Die
  /// Feldzuordnung bewusst an EINER Stelle, damit ein neues Wunsch-Feld nicht
  /// still durchrutscht.
  factory CustomerOrder.fromCustomerWish(
    CustomerWish wish, {
    required String siteId,
    String? siteName,
  }) {
    final customer = wish.customerName?.trim();
    return CustomerOrder(
      orgId: wish.orgId,
      siteId: siteId,
      siteName: siteName,
      customerName: (customer != null && customer.isNotEmpty)
          ? customer
          : 'Kundenwunsch ${wish.referenceCode}',
      customerContact: wish.customerContact,
      contactId: wish.contactId,
      status: CustomerOrderStatus.open,
      items: [
        CustomerOrderItem(name: wish.wishText, quantity: wish.quantity),
      ],
      notes: 'Aus Kundenwunsch ${wish.referenceCode} (${wish.category.label})',
      pickupDate: wish.desiredDate,
      sourceWishId: wish.id,
    );
  }

  final String? id;
  final String orgId;
  final String siteId;
  final String? siteName;

  /// Name des Kunden (denormalisiert, da keine eigene Kundenkartei).
  final String customerName;

  /// Freitext-Kontakt (Telefon/E-Mail), optional.
  final String? customerContact;

  /// Optionale Verknüpfung mit einem echten Kontakt (Kundenkartei). [customerName]
  /// bleibt denormalisiert erhalten (Offline-Anzeige, Lauf-/Stammkunden).
  final String? contactId;

  /// Menschlich lesbare Bestellnummer (z.B. "KB-2026-0007").
  final String? orderNumber;
  final CustomerOrderStatus status;
  final CustomerOrderRecurrence recurrence;
  final List<CustomerOrderItem> items;
  final String? notes;

  /// Abholtermin – steuert die "nicht vorbereitet"-Warnung.
  final DateTime? pickupDate;

  /// Zeitpunkt, zu dem die Ware als vorbereitet markiert wurde.
  final DateTime? preparedAt;

  /// Herkunfts-Kundenwunsch (`CustomerWish.id`), falls diese Bestellung aus
  /// einem öffentlichen Wunsch übernommen wurde (H-E1). `null` = direkt
  /// angelegt. Dient als Idempotenz-/Rückverweis gegen Doppel-Übernahme.
  final String? sourceWishId;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPrepared => preparedAt != null;

  int get itemCount => items.length;

  int get totalQuantity =>
      items.fold(0, (total, item) => total + item.quantity);

  int get totalCents =>
      items.fold(0, (total, item) => total + item.lineTotalCents);

  bool get hasPrices => items.any((item) => item.unitPriceCents != null);

  /// Termin der Folgebestellung bei wiederkehrenden Bestellungen (null, wenn
  /// einmalig oder kein Abholtermin gesetzt ist).
  DateTime? get nextPickupDate {
    final due = pickupDate;
    if (due == null || !recurrence.isRecurring) {
      return null;
    }
    return recurrence.advance(due);
  }

  factory CustomerOrder.fromFirestore(String id, Map<String, dynamic> map) {
    return CustomerOrder(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      customerName: (map['customerName'] ?? '').toString(),
      customerContact: map['customerContact'] as String?,
      contactId: map['contactId'] as String?,
      orderNumber: map['orderNumber'] as String?,
      status: CustomerOrderStatusX.fromValue(map['status']?.toString()),
      recurrence:
          CustomerOrderRecurrenceX.fromValue(map['recurrence']?.toString()),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      pickupDate: FirestoreDateParser.readDate(map['pickupDate']),
      preparedAt: FirestoreDateParser.readDate(map['preparedAt']),
      sourceWishId: map['sourceWishId'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory CustomerOrder.fromMap(Map<String, dynamic> map) {
    return CustomerOrder(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      customerName: (map['customer_name'] ?? '').toString(),
      customerContact: map['customer_contact'] as String?,
      contactId: map['contact_id'] as String?,
      orderNumber: map['order_number'] as String?,
      status: CustomerOrderStatusX.fromValue(map['status']?.toString()),
      recurrence:
          CustomerOrderRecurrenceX.fromValue(map['recurrence']?.toString()),
      items: _itemsFromList(map['items']),
      notes: map['notes'] as String?,
      pickupDate: FirestoreDateParser.readLocalDate(map['pickup_date']),
      preparedAt: FirestoreDateParser.readLocalDate(map['prepared_at']),
      sourceWishId: map['source_wish_id'] as String?,
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
      'customerName': customerName.trim(),
      'customerContact': _trimmedOrNull(customerContact),
      'contactId': _trimmedOrNull(contactId),
      'orderNumber': _trimmedOrNull(orderNumber),
      'status': status.value,
      'recurrence': recurrence.value,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
      'totalCents': totalCents,
      'notes': _trimmedOrNull(notes),
      'pickupDate': _timestampOrNull(pickupDate),
      'preparedAt': _timestampOrNull(preparedAt),
      'sourceWishId': _trimmedOrNull(sourceWishId),
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
      'customer_name': customerName,
      'customer_contact': customerContact,
      'contact_id': contactId,
      'order_number': orderNumber,
      'status': status.value,
      'recurrence': recurrence.value,
      'items': items.map((item) => item.toMap()).toList(),
      'notes': notes,
      'pickup_date': pickupDate?.toIso8601String(),
      'prepared_at': preparedAt?.toIso8601String(),
      'source_wish_id': sourceWishId,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CustomerOrder copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    String? customerName,
    String? customerContact,
    String? contactId,
    String? orderNumber,
    CustomerOrderStatus? status,
    CustomerOrderRecurrence? recurrence,
    List<CustomerOrderItem>? items,
    String? notes,
    DateTime? pickupDate,
    DateTime? preparedAt,
    String? sourceWishId,
    bool clearSiteName = false,
    bool clearCustomerContact = false,
    bool clearContactId = false,
    bool clearOrderNumber = false,
    bool clearNotes = false,
    bool clearPickupDate = false,
    bool clearPreparedAt = false,
    bool clearSourceWishId = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerOrder(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      customerName: customerName ?? this.customerName,
      customerContact: clearCustomerContact
          ? null
          : (customerContact ?? this.customerContact),
      contactId: clearContactId ? null : (contactId ?? this.contactId),
      orderNumber: clearOrderNumber ? null : (orderNumber ?? this.orderNumber),
      status: status ?? this.status,
      recurrence: recurrence ?? this.recurrence,
      items: items ?? this.items,
      notes: clearNotes ? null : (notes ?? this.notes),
      pickupDate: clearPickupDate ? null : (pickupDate ?? this.pickupDate),
      preparedAt: clearPreparedAt ? null : (preparedAt ?? this.preparedAt),
      sourceWishId:
          clearSourceWishId ? null : (sourceWishId ?? this.sourceWishId),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<CustomerOrderItem> _itemsFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => CustomerOrderItem.fromMap(
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
