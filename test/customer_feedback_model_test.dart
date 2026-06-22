import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/app_config.dart';
import 'package:worktime_app/models/customer_feedback.dart';

void main() {
  // Tripwire: der öffentliche Schreibpfad pinnt die orgId in firestore.rules
  // (publicWishOrg() == 'main-org', geteilt mit /wunsch). Der Client schreibt
  // AppConfig.defaultOrganizationId. Weicht der Default ab, ohne dass die Regel
  // nachgezogen wird, bricht /feedback still (permission-denied).
  test('Default-Org passt zum publicWishOrg-Pin in firestore.rules', () {
    expect(AppConfig.defaultOrganizationId, 'main-org');
  });

  group('CustomerFeedback Referenznummer', () {
    test('hat Format XXX-XXX ohne verwechselbare Zeichen', () {
      final code = CustomerFeedback.generateReferenceCode(Random(42));
      expect(code, matches(RegExp(r'^[A-Z2-9]{3}-[A-Z2-9]{3}$')));
      // Keine 0/O/1/I/L (Vorlese-/Verwechslungsgefahr).
      expect(code.contains(RegExp('[01OIL]')), isFalse);
    });

    test('ist deterministisch bei gleichem Seed', () {
      expect(
        CustomerFeedback.generateReferenceCode(Random(7)),
        CustomerFeedback.generateReferenceCode(Random(7)),
      );
    });
  });

  group('CustomerFeedback Enums', () {
    test('Typ fromValue fällt auf suggestion zurück', () {
      expect(FeedbackTypeX.fromValue('complaint'), FeedbackType.complaint);
      expect(FeedbackTypeX.fromValue('praise'), FeedbackType.praise);
      expect(FeedbackTypeX.fromValue('quatsch'), FeedbackType.suggestion);
      expect(FeedbackTypeX.fromValue(null), FeedbackType.suggestion);
    });

    test('Typ-Werte entsprechen der Allowlist in firestore.rules', () {
      expect(FeedbackType.complaint.value, 'complaint');
      expect(FeedbackType.suggestion.value, 'suggestion');
      expect(FeedbackType.praise.value, 'praise');
    });

    test('Status fromValue fällt auf pending (neu) zurück', () {
      expect(FeedbackStatusX.fromValue('erledigt'), FeedbackStatus.done);
      expect(FeedbackStatusX.fromValue(null), FeedbackStatus.pending);
      expect(FeedbackStatus.pending.value, 'neu');
    });
  });

  group('CustomerFeedback öffentlicher Submission-Payload', () {
    test('enthält exakt die in firestore.rules erlaubten Felder', () {
      const feedback = CustomerFeedback(
        orgId: 'main-org',
        referenceCode: 'ABC-DEF',
        type: FeedbackType.complaint,
        message: 'Die Schlange an der Kasse war zu lang.',
        storeName: 'Tabak Börse',
        rating: 2,
        // Status absichtlich abweichend -> Payload muss trotzdem 'neu' sein.
        status: FeedbackStatus.done,
      );

      final map = feedback.toPublicSubmissionMap();

      expect(
        map.keys.toSet(),
        {
          'orgId',
          'referenceCode',
          'type',
          'message',
          'storeName',
          'rating',
          'incidentDate',
          'customerName',
          'customerContact',
          'status',
          'source',
        },
      );
      // Invarianten, die die Rule serverseitig erzwingt:
      expect(map['status'], 'neu');
      expect(map['source'], CustomerFeedback.publicWebSource);
      expect(map['type'], 'complaint');
      expect(map['rating'], 2);
    });

    test('lässt optionale Felder als null im Payload', () {
      const feedback = CustomerFeedback(
        orgId: 'main-org',
        referenceCode: 'ABC-DEF',
        type: FeedbackType.suggestion,
        message: 'Bitte mehr Bio-Produkte.',
      );

      final map = feedback.toPublicSubmissionMap();
      expect(map['rating'], isNull);
      expect(map['incidentDate'], isNull);
      expect(map['customerName'], isNull);
      expect(map['customerContact'], isNull);
    });
  });

  group('CustomerFeedback Serialisierung (Zwei-Formate)', () {
    test('toMap/fromMap (snake_case) trippt rund', () {
      final feedback = CustomerFeedback(
        id: 'f1',
        orgId: 'main-org',
        referenceCode: 'K7Q-9X2',
        type: FeedbackType.praise,
        message: 'Super freundliches Personal!',
        storeName: 'Strichmännchen',
        rating: 5,
        incidentDate: DateTime(2026, 6, 1, 12),
        customerName: 'Max Muster',
        customerContact: 'max@example.com',
        status: FeedbackStatus.seen,
        notes: 'ans Team weitergegeben',
      );

      final restored = CustomerFeedback.fromMap(feedback.toMap());

      expect(restored.referenceCode, 'K7Q-9X2');
      expect(restored.type, FeedbackType.praise);
      expect(restored.message, 'Super freundliches Personal!');
      expect(restored.storeName, 'Strichmännchen');
      expect(restored.rating, 5);
      expect(restored.incidentDate, DateTime(2026, 6, 1, 12));
      expect(restored.customerName, 'Max Muster');
      expect(restored.customerContact, 'max@example.com');
      expect(restored.status, FeedbackStatus.seen);
      expect(restored.notes, 'ans Team weitergegeben');
    });
  });
}
