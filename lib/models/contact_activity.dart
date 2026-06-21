import '../core/firestore_date_parser.dart';

/// Art einer Kontakt-Interaktion (für die Kontakthistorie).
enum ContactActivityType { call, email, meeting, note, task }

extension ContactActivityTypeX on ContactActivityType {
  String get value => switch (this) {
        ContactActivityType.call => 'call',
        ContactActivityType.email => 'email',
        ContactActivityType.meeting => 'meeting',
        ContactActivityType.note => 'note',
        ContactActivityType.task => 'task',
      };

  String get label => switch (this) {
        ContactActivityType.call => 'Anruf',
        ContactActivityType.email => 'E-Mail',
        ContactActivityType.meeting => 'Treffen',
        ContactActivityType.note => 'Notiz',
        ContactActivityType.task => 'Aufgabe',
      };

  static ContactActivityType fromValue(String? value) => switch (value) {
        'call' => ContactActivityType.call,
        'email' => ContactActivityType.email,
        'meeting' => ContactActivityType.meeting,
        'task' => ContactActivityType.task,
        _ => ContactActivityType.note,
      };
}

/// Ein Eintrag in der Kontakthistorie (Anruf, E-Mail, Treffen, Notiz …).
///
/// Adaptiert aus AllTecs `ContactActivity` — bewusst **eingebettet** in den
/// [Contact] (Liste statt Sub-Collection), damit keine zusätzlichen
/// Firestore-Reads je Kontakt anfallen (Spark-Free-Tier). Das Datum wird in
/// beiden Serialisierungen als ISO-8601-String gehalten (einfacher als
/// Timestamps in Arrays).
class ContactActivity {
  const ContactActivity({
    required this.type,
    required this.occurredAt,
    this.note,
    this.createdByUid,
  });

  final ContactActivityType type;
  final DateTime occurredAt;
  final String? note;
  final String? createdByUid;

  factory ContactActivity.fromMap(Map<String, dynamic> map) {
    return ContactActivity(
      type: ContactActivityTypeX.fromValue(map['type']?.toString()),
      occurredAt: FirestoreDateParser.readLocalDate(map['occurred_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      note: map['note'] as String?,
      createdByUid: map['created_by_uid'] as String?,
    );
  }

  factory ContactActivity.fromFirestoreMap(Map<String, dynamic> map) {
    return ContactActivity(
      type: ContactActivityTypeX.fromValue(map['type']?.toString()),
      occurredAt: FirestoreDateParser.readLocalDate(map['occurredAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      note: map['note'] as String?,
      createdByUid: map['createdByUid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.value,
      'occurred_at': occurredAt.toIso8601String(),
      'note': note,
      'created_by_uid': createdByUid,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'type': type.value,
      'occurredAt': occurredAt.toIso8601String(),
      'note': note,
      'createdByUid': createdByUid,
    };
  }
}
