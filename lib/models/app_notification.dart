import '../core/firestore_date_parser.dart';

/// **PERSONAL-9/Q4 — In-App-Mitteilung** (Inbox-Doc unter
/// `organizations/{orgId}/notifications/{id}`).
///
/// **Server-owned, read-only** (dokumentierte Ausnahme von der Dual-Regel):
/// die Docs erzeugt ausschließlich `fanOutPush` (Cloud Function, Admin SDK); der
/// Client liest nur die EIGENEN (`recipientUid == uid`) und darf ausschließlich
/// `readAt` setzen (Rules-Allowlist). Deshalb NUR [fromFirestore] — kein
/// `toMap`/`toFirestoreMap`/`copyWith`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientUid,
    required this.category,
    required this.title,
    required this.body,
    this.route,
    this.entityType,
    this.entityId,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String recipientUid;

  /// Push-Kategorie (`customer_wish`, `absence_request`, `delivery`, `document`,
  /// `qualification`, … — deckungsgleich mit dem `type`/`category` der Function).
  final String category;
  final String title;
  final String body;

  /// Ziel-Route für den Tap (vorhandenes `route`-Feld; keine eigenen
  /// Payload-Typen). `null` ⇒ kein Deep-Link.
  final String? route;
  final String? entityType;
  final String? entityId;

  /// Zeitpunkt des Gelesen-Markierens (`null` ⇒ ungelesen).
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromFirestore(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      recipientUid: (map['recipientUid'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      route: map['route'] as String?,
      entityType: map['entityType'] as String?,
      entityId: map['entityId'] as String?,
      readAt: FirestoreDateParser.readDate(map['readAt']),
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }
}
