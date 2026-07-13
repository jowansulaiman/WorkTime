import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import 'parcel_customer.dart' show parcelNameLower;

/// Status eines Pakets im Hermes-Paketshop. Serialisiert über [value]
/// (snake_case), Anzeige über [label].
///
/// „Überfällig" ist **kein** Status, sondern ein abgeleiteter Zustand
/// (`arrivedAt` + konfigurierbare Frist), s. [ParcelShipment.isOverdue].
enum ShipmentStatus {
  /// Eingelagert und wartet auf Abholung.
  eingelagert,

  /// An den Empfänger ausgegeben.
  abgeholt,

  /// An den Absender zurückgeschickt (Rücklauf).
  zurueck,
}

extension ShipmentStatusX on ShipmentStatus {
  String get value => switch (this) {
        ShipmentStatus.eingelagert => 'stored',
        ShipmentStatus.abgeholt => 'handed_out',
        ShipmentStatus.zurueck => 'returned',
      };

  String get label => switch (this) {
        ShipmentStatus.eingelagert => 'Eingelagert',
        ShipmentStatus.abgeholt => 'Abgeholt',
        ShipmentStatus.zurueck => 'Zurück (Rücklauf)',
      };

  /// Offen = liegt noch im Laden und wartet auf Abholung.
  bool get isOpen => this == ShipmentStatus.eingelagert;

  /// Abgeschlossen = abgeholt oder zurückgeschickt (nicht mehr im Bestand).
  bool get isClosed => !isOpen;

  static ShipmentStatus fromValue(String? value) => switch (value) {
        'handed_out' => ShipmentStatus.abgeholt,
        'returned' => ShipmentStatus.zurueck,
        _ => ShipmentStatus.eingelagert,
      };
}

/// Ein Paket im Hermes-Paketshop — internes Sortier-/Wiederfinde-Register,
/// parallel zum offiziellen Hermes-Gerät (ersetzt es nicht).
///
/// Der Empfängername ist als **Snapshot** am Vorgang gespeichert
/// ([recipientFirstName]/[recipientLastName]); die persistente
/// Wiedererkennung läuft über das getrennte [ParcelCustomer]-Register
/// ([parcelCustomerId]). Die Fach-Belegung wird nicht am Fach, sondern über
/// [compartmentId] der offenen Pakete abgeleitet (Plan §6.1/§6.2).
class ParcelShipment {
  const ParcelShipment({
    this.id,
    required this.orgId,
    required this.siteId,
    this.siteName,
    this.carrier = 'hermes',
    this.trackingCode,
    required this.recipientFirstName,
    required this.recipientLastName,
    this.senderName,
    this.parcelCustomerId,
    this.status = ShipmentStatus.eingelagert,
    this.compartmentId,
    this.compartmentLabel,
    required this.arrivedAt,
    this.handedOutAt,
    this.returnedAt,
    this.createdAt,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String? siteName;

  /// v1 fix `hermes`; als freier String gehalten, damit später Multi-Carrier
  /// additiv möglich ist (Plan §4/§6.1).
  final String carrier;

  /// Roher Scan-String des Paket-Barcodes, ohne Formatvalidierung. `null`,
  /// wenn ohne Barcode erfasst.
  final String? trackingCode;

  final String recipientFirstName;
  final String recipientLastName;

  /// Optionaler Absender/Shop (z. B. „Amazon") — Disambiguator bei
  /// Namensgleichheit.
  final String? senderName;

  /// Verknüpfung mit dem dauerhaften [ParcelCustomer]-Register. Der Namens-
  /// Snapshot bleibt unabhängig davon am Vorgang.
  final String? parcelCustomerId;

  final ShipmentStatus status;

  /// FK auf `ShelfCompartment.id`. Bleibt bei Ausgabe erhalten (Undo/Recovery,
  /// Plan §5b6); die Belegung wird aus offenen Paketen abgeleitet.
  final String? compartmentId;

  /// Anzeige-Cache des Fach-Labels. Im Mutator frisch setzen (Plan §14).
  final String? compartmentLabel;

  /// Einlagerzeitpunkt — Basis der Überfällig-Berechnung.
  final DateTime arrivedAt;

  final DateTime? handedOutAt;
  final DateTime? returnedAt;
  final DateTime? createdAt;

  /// Abgeleiteter Such-/Sortierschlüssel (Nachname Vorname, lowercase). Wird
  /// stets aus Vor-/Nachname berechnet, nie roh übernommen (Plan §14).
  String get recipientNameLower =>
      parcelNameLower(recipientFirstName, recipientLastName);

  /// Anzeigename "Vorname Nachname" (getrimmt).
  String get recipientDisplayName =>
      '${recipientFirstName.trim()} ${recipientLastName.trim()}'.trim();

  bool get isOpen => status.isOpen;

  /// Abgeleiteter Überfällig-Zustand: noch offen und seit mindestens
  /// [fristTage] Kalendertagen im Laden (Vergleich gegen [now]). Rein
  /// beratend — keine Zwangs-Rücksendung (Plan §9/§15).
  bool isOverdue(int fristTage, DateTime now) {
    if (!status.isOpen) {
      return false;
    }
    final schwelle = arrivedAt.add(Duration(days: fristTage));
    return !now.isBefore(schwelle);
  }

  factory ParcelShipment.fromFirestore(String id, Map<String, dynamic> map) {
    return ParcelShipment(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      siteName: map['siteName'] as String?,
      carrier: (map['carrier'] ?? 'hermes').toString(),
      trackingCode: map['trackingCode'] as String?,
      recipientFirstName: (map['recipientFirstName'] ?? '').toString(),
      recipientLastName: (map['recipientLastName'] ?? '').toString(),
      senderName: map['senderName'] as String?,
      parcelCustomerId: map['parcelCustomerId'] as String?,
      status: ShipmentStatusX.fromValue(map['status']?.toString()),
      compartmentId: map['compartmentId'] as String?,
      compartmentLabel: map['compartmentLabel'] as String?,
      arrivedAt: FirestoreDateParser.readDate(map['arrivedAt']) ??
          FirestoreDateParser.readDate(map['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      handedOutAt: FirestoreDateParser.readDate(map['handedOutAt']),
      returnedAt: FirestoreDateParser.readDate(map['returnedAt']),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory ParcelShipment.fromMap(Map<String, dynamic> map) {
    return ParcelShipment(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      siteName: map['site_name'] as String?,
      carrier: (map['carrier'] ?? 'hermes').toString(),
      trackingCode: map['tracking_code'] as String?,
      recipientFirstName: (map['recipient_first_name'] ?? '').toString(),
      recipientLastName: (map['recipient_last_name'] ?? '').toString(),
      senderName: map['sender_name'] as String?,
      parcelCustomerId: map['parcel_customer_id'] as String?,
      status: ShipmentStatusX.fromValue(map['status']?.toString()),
      compartmentId: map['compartment_id'] as String?,
      compartmentLabel: map['compartment_label'] as String?,
      arrivedAt: FirestoreDateParser.readLocalDate(map['arrived_at']) ??
          FirestoreDateParser.readLocalDate(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      handedOutAt: FirestoreDateParser.readLocalDate(map['handed_out_at']),
      returnedAt: FirestoreDateParser.readLocalDate(map['returned_at']),
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  /// camelCase + [Timestamp], **ohne** `id` und **ohne** `createdAt`
  /// (setzt das Repository via `FieldValue.serverTimestamp()` beim Anlegen).
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'siteName': _trimmedOrNull(siteName),
      'carrier': carrier.trim().isEmpty ? 'hermes' : carrier.trim(),
      'trackingCode': _trimmedOrNull(trackingCode),
      'recipientFirstName': recipientFirstName.trim(),
      'recipientLastName': recipientLastName.trim(),
      'recipientNameLower': recipientNameLower,
      'senderName': _trimmedOrNull(senderName),
      'parcelCustomerId': _trimmedOrNull(parcelCustomerId),
      'status': status.value,
      'compartmentId': _trimmedOrNull(compartmentId),
      'compartmentLabel': _trimmedOrNull(compartmentLabel),
      'arrivedAt': Timestamp.fromDate(arrivedAt),
      'handedOutAt': _timestampOrNull(handedOutAt),
      'returnedAt': _timestampOrNull(returnedAt),
    };
  }

  /// snake_case + ISO-8601, **mit** `id`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'site_name': siteName,
      'carrier': carrier,
      'tracking_code': trackingCode,
      'recipient_first_name': recipientFirstName,
      'recipient_last_name': recipientLastName,
      'recipient_name_lower': recipientNameLower,
      'sender_name': senderName,
      'parcel_customer_id': parcelCustomerId,
      'status': status.value,
      'compartment_id': compartmentId,
      'compartment_label': compartmentLabel,
      'arrived_at': arrivedAt.toIso8601String(),
      'handed_out_at': handedOutAt?.toIso8601String(),
      'returned_at': returnedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  ParcelShipment copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? siteName,
    String? carrier,
    String? trackingCode,
    String? recipientFirstName,
    String? recipientLastName,
    String? senderName,
    String? parcelCustomerId,
    ShipmentStatus? status,
    String? compartmentId,
    String? compartmentLabel,
    DateTime? arrivedAt,
    DateTime? handedOutAt,
    DateTime? returnedAt,
    DateTime? createdAt,
    bool clearSiteName = false,
    bool clearTrackingCode = false,
    bool clearSenderName = false,
    bool clearParcelCustomerId = false,
    bool clearCompartmentId = false,
    bool clearCompartmentLabel = false,
    bool clearHandedOutAt = false,
    bool clearReturnedAt = false,
  }) {
    return ParcelShipment(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      carrier: carrier ?? this.carrier,
      trackingCode:
          clearTrackingCode ? null : (trackingCode ?? this.trackingCode),
      recipientFirstName: recipientFirstName ?? this.recipientFirstName,
      recipientLastName: recipientLastName ?? this.recipientLastName,
      senderName: clearSenderName ? null : (senderName ?? this.senderName),
      parcelCustomerId: clearParcelCustomerId
          ? null
          : (parcelCustomerId ?? this.parcelCustomerId),
      status: status ?? this.status,
      compartmentId:
          clearCompartmentId ? null : (compartmentId ?? this.compartmentId),
      compartmentLabel: clearCompartmentLabel
          ? null
          : (compartmentLabel ?? this.compartmentLabel),
      arrivedAt: arrivedAt ?? this.arrivedAt,
      handedOutAt: clearHandedOutAt ? null : (handedOutAt ?? this.handedOutAt),
      returnedAt: clearReturnedAt ? null : (returnedAt ?? this.returnedAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static Timestamp? _timestampOrNull(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
