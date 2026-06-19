import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Lieferant fuer die Warenbestellung.
///
/// Lieferanten sind organisationsweit (nicht standortgebunden), damit ein
/// Lieferant von mehreren Laeden genutzt werden kann.
class Supplier {
  const Supplier({
    this.id,
    required this.orgId,
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.orderEmail,
    this.customerNumber,
    this.leadTimeDays,
    this.notes,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;

  /// E-Mail-Adresse, an die Bestellungen gesendet werden (falls abweichend).
  final String? orderEmail;

  /// Eigene Kundennummer beim Lieferanten.
  final String? customerNumber;

  /// Uebliche Lieferzeit in Tagen.
  final int? leadTimeDays;
  final String? notes;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Bevorzugte Bestelladresse: explizite Bestell-E-Mail, sonst Standard-E-Mail.
  String? get effectiveOrderEmail {
    final order = orderEmail?.trim();
    if (order != null && order.isNotEmpty) {
      return order;
    }
    final fallback = email?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return null;
  }

  factory Supplier.fromFirestore(String id, Map<String, dynamic> map) {
    return Supplier(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      contactPerson: map['contactPerson'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      orderEmail: map['orderEmail'] as String?,
      customerNumber: map['customerNumber'] as String?,
      leadTimeDays: parse.toInt(map['leadTimeDays']),
      notes: map['notes'] as String?,
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      contactPerson: map['contact_person'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      orderEmail: map['order_email'] as String?,
      customerNumber: map['customer_number'] as String?,
      leadTimeDays: parse.toInt(map['lead_time_days']),
      notes: map['notes'] as String?,
      isActive: parse.toBool(map['is_active']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'contactPerson': _trimmedOrNull(contactPerson),
      'email': _trimmedOrNull(email),
      'phone': _trimmedOrNull(phone),
      'orderEmail': _trimmedOrNull(orderEmail),
      'customerNumber': _trimmedOrNull(customerNumber),
      'leadTimeDays': leadTimeDays,
      'notes': _trimmedOrNull(notes),
      'isActive': isActive,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'contact_person': contactPerson,
      'email': email,
      'phone': phone,
      'order_email': orderEmail,
      'customer_number': customerNumber,
      'lead_time_days': leadTimeDays,
      'notes': notes,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Supplier copyWith({
    String? id,
    String? orgId,
    String? name,
    String? contactPerson,
    String? email,
    String? phone,
    String? orderEmail,
    String? customerNumber,
    int? leadTimeDays,
    String? notes,
    bool? isActive,
    bool clearContactPerson = false,
    bool clearEmail = false,
    bool clearPhone = false,
    bool clearOrderEmail = false,
    bool clearCustomerNumber = false,
    bool clearLeadTimeDays = false,
    bool clearNotes = false,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      contactPerson:
          clearContactPerson ? null : (contactPerson ?? this.contactPerson),
      email: clearEmail ? null : (email ?? this.email),
      phone: clearPhone ? null : (phone ?? this.phone),
      orderEmail: clearOrderEmail ? null : (orderEmail ?? this.orderEmail),
      customerNumber:
          clearCustomerNumber ? null : (customerNumber ?? this.customerNumber),
      leadTimeDays:
          clearLeadTimeDays ? null : (leadTimeDays ?? this.leadTimeDays),
      notes: clearNotes ? null : (notes ?? this.notes),
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
