import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Art einer öffentlich abgegebenen Rückmeldung. Bewusst grob gehalten, damit
/// Kunden ohne Vorwissen wählen können: Beschwerde, Verbesserungsvorschlag, Lob.
enum FeedbackType { complaint, suggestion, praise }

extension FeedbackTypeX on FeedbackType {
  /// Serialisierter Wert (snake/english) — MUSS mit der Allowlist in
  /// `firestore.rules` (`match /customerFeedback`) übereinstimmen.
  String get value => switch (this) {
        FeedbackType.complaint => 'complaint',
        FeedbackType.suggestion => 'suggestion',
        FeedbackType.praise => 'praise',
      };

  String get label => switch (this) {
        FeedbackType.complaint => 'Beschwerde',
        FeedbackType.suggestion => 'Verbesserungsvorschlag',
        FeedbackType.praise => 'Lob',
      };

  static FeedbackType fromValue(String? value) => switch (value) {
        'complaint' => FeedbackType.complaint,
        'praise' => FeedbackType.praise,
        _ => FeedbackType.suggestion,
      };
}

/// Bearbeitungsstatus einer Rückmeldung im internen Eingang.
/// Bewusst identisch zu `CustomerWishStatus` (gleiche serialisierten Werte),
/// damit der öffentliche Create-Pfad in `firestore.rules` `'neu'` verlangen kann.
enum FeedbackStatus { pending, seen, done, rejected }

extension FeedbackStatusX on FeedbackStatus {
  /// Serialisierter Wert. `pending` == `'neu'` ist in `firestore.rules` für den
  /// öffentlichen Schreibpfad fest verdrahtet (Kunden dürfen nur `neu` anlegen).
  String get value => switch (this) {
        FeedbackStatus.pending => 'neu',
        FeedbackStatus.seen => 'gesehen',
        FeedbackStatus.done => 'erledigt',
        FeedbackStatus.rejected => 'abgelehnt',
      };

  String get label => switch (this) {
        FeedbackStatus.pending => 'Neu',
        FeedbackStatus.seen => 'Gesehen',
        FeedbackStatus.done => 'Erledigt',
        FeedbackStatus.rejected => 'Abgelehnt',
      };

  bool get isOpen =>
      this == FeedbackStatus.pending || this == FeedbackStatus.seen;

  static FeedbackStatus fromValue(String? value) => switch (value) {
        'gesehen' => FeedbackStatus.seen,
        'erledigt' => FeedbackStatus.done,
        'abgelehnt' => FeedbackStatus.rejected,
        _ => FeedbackStatus.pending,
      };
}

/// Eine über die öffentliche Webseite (/feedback) abgegebene Rückmeldung
/// (Beschwerde, Verbesserungsvorschlag oder Lob). Kunden brauchen keinen Login:
/// Sie geben die Rückmeldung anonym ab und bekommen eine [referenceCode] für
/// eine eventuelle Nachfrage.
///
/// Anders als [CustomerWish] ist der interne Eingang NICHT für alle Mitglieder
/// sichtbar, sondern nur für Manager (Beschwerden können sensibel sein) — siehe
/// `firestore.rules` (`canManageFeedback()`).
class CustomerFeedback {
  const CustomerFeedback({
    this.id,
    required this.orgId,
    required this.referenceCode,
    required this.type,
    required this.message,
    this.storeName = '',
    this.rating,
    this.incidentDate,
    this.customerName,
    this.customerContact,
    this.contactId,
    this.status = FeedbackStatus.pending,
    this.source = publicWebSource,
    this.notes,
    this.handledByUid,
    this.handledAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Markiert öffentlich (anonym) abgegebene Rückmeldungen. In `firestore.rules`
  /// für den öffentlichen Create-Pfad fest verlangt.
  static const String publicWebSource = 'public_web';

  final String? id;
  final String orgId;

  /// Menschlich nennbare Nummer (z.B. "K7Q-9X2") für eine eventuelle Nachfrage.
  final String referenceCode;

  final FeedbackType type;

  /// Freitext der Rückmeldung.
  final String message;

  /// Gewählter Laden (Klartext-Label, da Kunden keine internen siteIds kennen).
  final String storeName;

  /// Optionale Zufriedenheits-Bewertung 1–5 (Sterne).
  final int? rating;

  /// Optionaler Zeitpunkt des Vorfalls/Erlebnisses (kann in der Vergangenheit
  /// liegen).
  final DateTime? incidentDate;

  /// Optionaler Name des Kunden.
  final String? customerName;

  /// Optionaler Kontakt (Telefon/E-Mail) für eine Rückmeldung.
  final String? customerContact;

  /// Optionale Verknüpfung zu einem [Contact] aus der zentralen Kontakte-Kartei
  /// (H-D2). Wird ausschließlich INTERN von einem Manager beim Bearbeiten
  /// gesetzt — `null` = nicht verknüpft. Bewusst NICHT im
  /// [toPublicSubmissionMap] / der `firestore.rules`-Allowlist des öffentlichen
  /// Create-Pfads (anonyme Kunden kennen keine internen Kontakt-IDs).
  final String? contactId;

  final FeedbackStatus status;

  /// Herkunft der Rückmeldung (aktuell nur [publicWebSource]).
  final String source;

  /// Interne Notiz des Mitarbeiters.
  final String? notes;

  /// Mitarbeiter, der die Rückmeldung zuletzt bearbeitet hat.
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

  factory CustomerFeedback.fromFirestore(String id, Map<String, dynamic> map) {
    return CustomerFeedback(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      referenceCode: (map['referenceCode'] ?? '').toString(),
      type: FeedbackTypeX.fromValue(map['type']?.toString()),
      message: (map['message'] ?? '').toString(),
      storeName: (map['storeName'] ?? '').toString(),
      rating: parse.toInt(map['rating']),
      incidentDate: FirestoreDateParser.readDate(map['incidentDate']),
      customerName: map['customerName'] as String?,
      customerContact: map['customerContact'] as String?,
      contactId: map['contactId'] as String?,
      status: FeedbackStatusX.fromValue(map['status']?.toString()),
      source: (map['source'] ?? publicWebSource).toString(),
      notes: map['notes'] as String?,
      handledByUid: map['handledByUid'] as String?,
      handledAt: FirestoreDateParser.readDate(map['handledAt']),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory CustomerFeedback.fromMap(Map<String, dynamic> map) {
    return CustomerFeedback(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      referenceCode: (map['reference_code'] ?? '').toString(),
      type: FeedbackTypeX.fromValue(map['type']?.toString()),
      message: (map['message'] ?? '').toString(),
      storeName: (map['store_name'] ?? '').toString(),
      rating: parse.toInt(map['rating']),
      incidentDate: FirestoreDateParser.readLocalDate(map['incident_date']),
      customerName: map['customer_name'] as String?,
      customerContact: map['customer_contact'] as String?,
      contactId: map['contact_id'] as String?,
      status: FeedbackStatusX.fromValue(map['status']?.toString()),
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
  /// `firestore.rules` (`match /customerFeedback`) entsprechen (ohne `createdAt`,
  /// das der Service als `serverTimestamp` ergänzt — Regel verlangt
  /// `== request.time`).
  Map<String, dynamic> toPublicSubmissionMap() {
    return {
      'orgId': orgId,
      'referenceCode': referenceCode,
      'type': type.value,
      'message': message.trim(),
      'storeName': storeName.trim(),
      'rating': rating,
      'incidentDate': _timestampOrNull(incidentDate),
      'customerName': _trimmedOrNull(customerName),
      'customerContact': _trimmedOrNull(customerContact),
      'status': FeedbackStatus.pending.value,
      'source': publicWebSource,
    };
  }

  /// Vollständiges camelCase-Format (interne Writes/Updates durch Mitarbeiter).
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'referenceCode': referenceCode,
      'type': type.value,
      'message': message.trim(),
      'storeName': storeName.trim(),
      'rating': rating,
      'incidentDate': _timestampOrNull(incidentDate),
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
      'type': type.value,
      'message': message,
      'store_name': storeName,
      'rating': rating,
      'incident_date': incidentDate?.toIso8601String(),
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

  CustomerFeedback copyWith({
    String? id,
    String? orgId,
    String? referenceCode,
    FeedbackType? type,
    String? message,
    String? storeName,
    int? rating,
    DateTime? incidentDate,
    String? customerName,
    String? customerContact,
    String? contactId,
    FeedbackStatus? status,
    String? source,
    String? notes,
    String? handledByUid,
    DateTime? handledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearRating = false,
    bool clearIncidentDate = false,
    bool clearCustomerName = false,
    bool clearCustomerContact = false,
    bool clearContactId = false,
    bool clearNotes = false,
    bool clearHandledBy = false,
  }) {
    return CustomerFeedback(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      referenceCode: referenceCode ?? this.referenceCode,
      type: type ?? this.type,
      message: message ?? this.message,
      storeName: storeName ?? this.storeName,
      rating: clearRating ? null : (rating ?? this.rating),
      incidentDate:
          clearIncidentDate ? null : (incidentDate ?? this.incidentDate),
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
