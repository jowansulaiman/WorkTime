import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';

/// Normalisierter Namensschlüssel für Suche/Sortierung/Dublettenprüfung im
/// Paketshop. Reihenfolge "<Nachname> <Vorname>", lowercase, getrimmt.
///
/// Wird NIE roh aus einer Map übernommen, sondern IMMER frisch aus Vor-/
/// Nachname berechnet (Plan §14, Cache-Recompute-Footgun) — geteilt von
/// [ParcelCustomer] und `ParcelShipment`.
String parcelNameLower(String firstName, String lastName) {
  final first = firstName.trim().toLowerCase();
  final last = lastName.trim().toLowerCase();
  return '$last $first'.trim();
}

/// Dauerhaftes, **name-only** Kunden-Namensregister des Paketshops
/// (Betreiber-Entscheidung §0). Speist den Namens-Typeahead über Besuche
/// hinweg. Enthält bewusst KEINE Adresse/Telefon/E-Mail und keinen
/// Abholverlauf (Datenminimierung, Plan §6.3/§13). Löschung nur manuell auf
/// Wunsch (Art. 17/21).
class ParcelCustomer {
  const ParcelCustomer({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.firstName,
    required this.lastName,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String? id;
  final String orgId;
  final String siteId;
  final String firstName;
  final String lastName;

  /// Zeitpunkt der Anlage (Register-Ersteintrag).
  final DateTime? firstSeenAt;

  /// Zuletzt gesehen (bei jedem neuen Paket aktualisiert) — Aufräum-Heuristik.
  final DateTime? lastSeenAt;

  /// Abgeleiteter Such-/Sortier-/Dublettenschlüssel. Nicht gespeichert
  /// übernommen, sondern stets aus [firstName]/[lastName] berechnet.
  String get nameLower => parcelNameLower(firstName, lastName);

  /// Anzeigename "Vorname Nachname" (getrimmt).
  String get displayName => '${firstName.trim()} ${lastName.trim()}'.trim();

  factory ParcelCustomer.fromFirestore(String id, Map<String, dynamic> map) {
    return ParcelCustomer(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      firstName: (map['firstName'] ?? '').toString(),
      lastName: (map['lastName'] ?? '').toString(),
      firstSeenAt: FirestoreDateParser.readDate(map['firstSeenAt']),
      lastSeenAt: FirestoreDateParser.readDate(map['lastSeenAt']),
    );
  }

  factory ParcelCustomer.fromMap(Map<String, dynamic> map) {
    return ParcelCustomer(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      siteId: (map['site_id'] ?? '').toString(),
      firstName: (map['first_name'] ?? '').toString(),
      lastName: (map['last_name'] ?? '').toString(),
      firstSeenAt: FirestoreDateParser.readLocalDate(map['first_seen_at']),
      lastSeenAt: FirestoreDateParser.readLocalDate(map['last_seen_at']),
    );
  }

  /// camelCase + [Timestamp], **ohne** `id`. `nameLower` wird abgeleitet
  /// mitgeschrieben (für `orderBy('nameLower')`).
  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'siteId': siteId,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'nameLower': nameLower,
      'firstSeenAt': _timestampOrNull(firstSeenAt),
      'lastSeenAt': _timestampOrNull(lastSeenAt),
    };
  }

  /// snake_case + ISO-8601, **mit** `id`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'site_id': siteId,
      'first_name': firstName,
      'last_name': lastName,
      'name_lower': nameLower,
      'first_seen_at': firstSeenAt?.toIso8601String(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
    };
  }

  ParcelCustomer copyWith({
    String? id,
    String? orgId,
    String? siteId,
    String? firstName,
    String? lastName,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    bool clearFirstSeenAt = false,
    bool clearLastSeenAt = false,
  }) {
    return ParcelCustomer(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      siteId: siteId ?? this.siteId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      firstSeenAt: clearFirstSeenAt ? null : (firstSeenAt ?? this.firstSeenAt),
      lastSeenAt: clearLastSeenAt ? null : (lastSeenAt ?? this.lastSeenAt),
    );
  }

  static Timestamp? _timestampOrNull(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);
}
