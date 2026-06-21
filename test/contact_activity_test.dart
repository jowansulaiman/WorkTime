import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/contact.dart';
import 'package:worktime_app/models/contact_activity.dart';

void main() {
  group('ContactActivity', () {
    test('Enum value/label/fromValue mit Default', () {
      expect(ContactActivityType.call.value, 'call');
      expect(ContactActivityType.meeting.label, 'Treffen');
      expect(ContactActivityTypeX.fromValue('email'), ContactActivityType.email);
      expect(ContactActivityTypeX.fromValue('x'), ContactActivityType.note);
    });

    test('eingebettet im Contact: snake_case Round-Trip', () {
      final contact = Contact(
        id: 'c1',
        orgId: 'o',
        name: 'Nord-Tabak',
        activities: [
          ContactActivity(
            type: ContactActivityType.call,
            occurredAt: DateTime(2026, 6, 21, 9, 30),
            note: 'Nachbestellung besprochen',
          ),
        ],
      );
      final restored = Contact.fromMap(contact.toMap());
      expect(restored.activities, hasLength(1));
      expect(restored.activities.first.type, ContactActivityType.call);
      expect(restored.activities.first.occurredAt, DateTime(2026, 6, 21, 9, 30));
      expect(restored.activities.first.note, 'Nachbestellung besprochen');
    });

    test('eingebettet im Contact: camelCase Round-Trip (Firestore)', () {
      final contact = Contact(
        orgId: 'o',
        name: 'Nord-Tabak',
        activities: [
          ContactActivity(
            type: ContactActivityType.meeting,
            occurredAt: DateTime(2026, 1, 2, 14),
          ),
        ],
      );
      final map = contact.toFirestoreMap()..remove('updatedAt');
      final restored = Contact.fromFirestore('c1', map);
      expect(restored.activities.single.type, ContactActivityType.meeting);
      expect(restored.activities.single.occurredAt, DateTime(2026, 1, 2, 14));
    });
  });
}
