import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Warengruppe eines öffentlich abgegebenen Kundenwunsches. Bewusst grob
/// gehalten (Zeitschrift / Zigaretten / Tabak / Sonstiges), damit Kunden ohne
/// Vorwissen wählen können.
enum CustomerWishCategory { magazine, cigarettes, tobacco, other }

extension CustomerWishCategoryX on CustomerWishCategory {
  /// Serialisierter Wert (snake/english) — MUSS mit der Allowlist in
  /// `firestore.rules` (`match /customerWishes`) übereinstimmen.
  String get value => switch (this) {
        CustomerWishCategory.magazine => 'magazine',
        CustomerWishCategory.cigarettes => 'cigarettes',
        CustomerWishCategory.tobacco => 'tobacco',
        CustomerWishCategory.other => 'other',
      };

  String get label => switch (this) {
        CustomerWishCategory.magazine => 'Zeitschrift',
        CustomerWishCategory.cigarettes => 'Zigaretten',
        CustomerWishCategory.tobacco => 'Tabak',
        CustomerWishCategory.other => 'Sonstiges',
      };

  static CustomerWishCategory fromValue(String? value) => switch (value) {
        'magazine' => CustomerWishCategory.magazine,
        'cigarettes' => CustomerWishCategory.cigarettes,
        'tobacco' => CustomerWishCategory.tobacco,
        _ => CustomerWishCategory.other,
      };
}

/// Bearbeitungsstatus eines Kundenwunsches im internen Eingang.
enum CustomerWishStatus { pending, seen, done, rejected }

extension CustomerWishStatusX on CustomerWishStatus {
  /// Serialisierter Wert. `pending` == `'neu'` ist in `firestore.rules` für den
  /// öffentlichen Schreibpfad fest verdrahtet (Kunden dürfen nur `neu` anlegen).
  String get value => switch (this) {
        CustomerWishStatus.pending => 'neu',
        CustomerWishStatus.seen => 'gesehen',
        CustomerWishStatus.done => 'erledigt',
        CustomerWishStatus.rejected => 'abgelehnt',
      };

  String get label => switch (this) {
        CustomerWishStatus.pending => 'Neu',
        CustomerWishStatus.seen => 'Gesehen',
        CustomerWishStatus.done => 'Erledigt',
        CustomerWishStatus.rejected => 'Abgelehnt',
      };

  bool get isOpen =>
      this == CustomerWishStatus.pending || this == CustomerWishStatus.seen;

  static CustomerWishStatus fromValue(String? value) => switch (value) {
        'gesehen' => CustomerWishStatus.seen,
        'erledigt' => CustomerWishStatus.done,
        'abgelehnt' => CustomerWishStatus.rejected,
        _ => CustomerWishStatus.pending,
      };
}

/// Ein über die öffentliche Webseite abgegebener Kundenwunsch
/// ("Sonderbestellung light"). Kunden brauchen keinen Login: Sie geben den
/// Wunsch ab und nennen im Laden die [referenceCode].
///
/// Vorstufe einer [CustomerOrder]: ein Mitarbeiter sichtet den Eingang und
/// erstellt bei Bedarf eine echte Kundenbestellung.
class CustomerWish {
  const CustomerWish({
    this.id,
    required this.orgId,
    required this.referenceCode,
    required this.storeName,
    required this.category,
    required this.wishText,
    this.quantity = 1,
    this.desiredDate,
    this.customerName,
    this.customerContact,
    this.contactId,
    this.status = CustomerWishStatus.pending,
    this.source = publicWebSource,
    this.notes,
    this.handledByUid,
    this.handledAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Markiert öffentlich (anonym) abgegebene Wünsche. In `firestore.rules` für
  /// den öffentlichen Create-Pfad fest verlangt.
  static const String publicWebSource = 'public_web';

  final String? id;
  final String orgId;

  /// Menschlich nennbare Nummer (z.B. "K7Q-9X2"), die der Kunde im Laden angibt.
  final String referenceCode;

  /// Gewählter Laden (Klartext-Label, da Kunden keine internen siteIds kennen).
  final String storeName;

  final CustomerWishCategory category;

  /// Freitext-Wunsch ("Spiegel Ausgabe 26", "eine Stange Marlboro Gold").
  final String wishText;

  final int quantity;

  /// Optionaler Wunsch-/Abholtermin.
  final DateTime? desiredDate;

  /// Optionaler Name des Kunden.
  final String? customerName;

  /// Optionaler Kontakt (Telefon/E-Mail) für Rückfragen.
  final String? customerContact;

  /// Optionale Verknüpfung zu einem [Contact] aus der zentralen Kontakte-Kartei
  /// (H-D2). Wird ausschließlich INTERN von einem Mitarbeiter beim Bearbeiten
  /// gesetzt — `null` = nicht verknüpft. Bewusst NICHT im
  /// [toPublicSubmissionMap] / der `firestore.rules`-Allowlist des öffentlichen
  /// Create-Pfads (anonyme Kunden kennen keine internen Kontakt-IDs).
  final String? contactId;

  final CustomerWishStatus status;

  /// Herkunft des Wunsches (aktuell nur [publicWebSource]).
  final String source;

  /// Interne Notiz des Mitarbeiters.
  final String? notes;

  /// Mitarbeiter, der den Wunsch zuletzt bearbeitet hat.
  final String? handledByUid;
  final DateTime? handledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasContact =>
      (customerName?.trim().isNotEmpty ?? false) ||
      (customerContact?.trim().isNotEmpty ?? false);

  /// Alphabet ohne leicht verwechselbare Zeichen (kein 0/O/1/I/L), damit der
  /// Code am Telefon/im Laden eindeutig vorlesbar ist.
  static const String _codeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  /// Erzeugt eine kurze, gut nennbare Referenznummer (Format "XXX-XXX").
  /// [random] ist injizierbar für deterministische Tests.
  static String generateReferenceCode([Random? random]) {
    final rng = random ?? Random();
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      if (i == 3) {
        buffer.write('-');
      }
      buffer.write(_codeAlphabet[rng.nextInt(_codeAlphabet.length)]);
    }
    return buffer.toString();
  }

  factory CustomerWish.fromFirestore(String id, Map<String, dynamic> map) {
    return CustomerWish(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      referenceCode: (map['referenceCode'] ?? '').toString(),
      storeName: (map['storeName'] ?? '').toString(),
      category: CustomerWishCategoryX.fromValue(map['category']?.toString()),
      wishText: (map['wishText'] ?? '').toString(),
      quantity: parse.toInt(map['quantity']) ?? 1,
      desiredDate: FirestoreDateParser.readDate(map['desiredDate']),
      customerName: map['customerName'] as String?,
      customerContact: map['customerContact'] as String?,
      contactId: map['contactId'] as String?,
      status: CustomerWishStatusX.fromValue(map['status']?.toString()),
      source: (map['source'] ?? publicWebSource).toString(),
      notes: map['notes'] as String?,
      handledByUid: map['handledByUid'] as String?,
      handledAt: FirestoreDateParser.readDate(map['handledAt']),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory CustomerWish.fromMap(Map<String, dynamic> map) {
    return CustomerWish(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      referenceCode: (map['reference_code'] ?? '').toString(),
      storeName: (map['store_name'] ?? '').toString(),
      category: CustomerWishCategoryX.fromValue(map['category']?.toString()),
      wishText: (map['wish_text'] ?? '').toString(),
      quantity: parse.toInt(map['quantity']) ?? 1,
      desiredDate: FirestoreDateParser.readLocalDate(map['desired_date']),
      customerName: map['customer_name'] as String?,
      customerContact: map['customer_contact'] as String?,
      contactId: map['contact_id'] as String?,
      status: CustomerWishStatusX.fromValue(map['status']?.toString()),
      source: (map['source'] ?? publicWebSource).toString(),
      notes: map['notes'] as String?,
      handledByUid: map['handled_by_uid'] as String?,
      handledAt: FirestoreDateParser.readLocalDate(map['handled_at']),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  /// Minimaler, streng kontrollierter Payload für den ÖFFENTLICHEN
  /// Create-Pfad. Die Schlüsselmenge MUSS exakt der `hasOnly`-Allowlist in
  /// `firestore.rules` (`match /customerWishes`) entsprechen. `createdAt` wird
  /// vom Service als `serverTimestamp` ergänzt (Regel verlangt `== request.time`).
  Map<String, dynamic> toPublicSubmissionMap() {
    return {
      'orgId': orgId,
      'referenceCode': referenceCode,
      'storeName': storeName.trim(),
      'category': category.value,
      'wishText': wishText.trim(),
      'quantity': quantity,
      'desiredDate': _timestampOrNull(desiredDate),
      'customerName': _trimmedOrNull(customerName),
      'customerContact': _trimmedOrNull(customerContact),
      'status': CustomerWishStatus.pending.value,
      'source': publicWebSource,
    };
  }

  /// Vollständiges camelCase-Format (interne Writes/Updates durch Mitarbeiter).
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'referenceCode': referenceCode,
      'storeName': storeName.trim(),
      'category': category.value,
      'wishText': wishText.trim(),
      'quantity': quantity,
      'desiredDate': _timestampOrNull(desiredDate),
      'customerName': _trimmedOrNull(customerName),
      'customerContact': _trimmedOrNull(customerContact),
      'contactId': _trimmedOrNull(contactId),
      'status': status.value,
      'source': source,
      'notes': _trimmedOrNull(notes),
      'handledByUid': handledByUid,
      'handledAt': _timestampOrNull(handledAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'reference_code': referenceCode,
      'store_name': storeName,
      'category': category.value,
      'wish_text': wishText,
      'quantity': quantity,
      'desired_date': desiredDate?.toIso8601String(),
      'customer_name': customerName,
      'customer_contact': customerContact,
      'contact_id': contactId,
      'status': status.value,
      'source': source,
      'notes': notes,
      'handled_by_uid': handledByUid,
      'handled_at': handledAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CustomerWish copyWith({
    String? id,
    String? orgId,
    String? referenceCode,
    String? storeName,
    CustomerWishCategory? category,
    String? wishText,
    int? quantity,
    DateTime? desiredDate,
    String? customerName,
    String? customerContact,
    String? contactId,
    CustomerWishStatus? status,
    String? source,
    String? notes,
    String? handledByUid,
    DateTime? handledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDesiredDate = false,
    bool clearCustomerName = false,
    bool clearCustomerContact = false,
    bool clearContactId = false,
    bool clearNotes = false,
    bool clearHandledBy = false,
  }) {
    return CustomerWish(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      referenceCode: referenceCode ?? this.referenceCode,
      storeName: storeName ?? this.storeName,
      category: category ?? this.category,
      wishText: wishText ?? this.wishText,
      quantity: quantity ?? this.quantity,
      desiredDate: clearDesiredDate ? null : (desiredDate ?? this.desiredDate),
      customerName:
          clearCustomerName ? null : (customerName ?? this.customerName),
      customerContact: clearCustomerContact
          ? null
          : (customerContact ?? this.customerContact),
      contactId: clearContactId ? null : (contactId ?? this.contactId),
      status: status ?? this.status,
      source: source ?? this.source,
      notes: clearNotes ? null : (notes ?? this.notes),
      handledByUid: clearHandledBy ? null : (handledByUid ?? this.handledByUid),
      handledAt: clearHandledBy ? null : (handledAt ?? this.handledAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
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
