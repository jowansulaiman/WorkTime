import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/employee_document.dart';

void main() {
  const doc = EmployeeDocument(
    id: 'doc-1',
    orgId: 'org-1',
    userId: 'emp-1',
    category: DocumentCategory.arbeitsvertrag,
    title: 'Arbeitsvertrag 2026',
    fileName: 'vertrag.pdf',
    contentType: 'application/pdf',
    sizeBytes: 12345,
    storagePath: 'employee-documents/org-1/emp-1/doc-1',
    note: 'unterschrieben',
    visibleToEmployee: true,
  );

  group('EmployeeDocument Serialisierung', () {
    test('toMap → fromMap round-trip (snake_case, ISO)', () {
      final restored = EmployeeDocument.fromMap(doc.toMap());
      expect(restored.id, 'doc-1');
      expect(restored.orgId, 'org-1');
      expect(restored.userId, 'emp-1');
      expect(restored.category, DocumentCategory.arbeitsvertrag);
      expect(restored.title, 'Arbeitsvertrag 2026');
      expect(restored.fileName, 'vertrag.pdf');
      expect(restored.contentType, 'application/pdf');
      expect(restored.sizeBytes, 12345);
      expect(restored.storagePath, 'employee-documents/org-1/emp-1/doc-1');
      expect(restored.note, 'unterschrieben');
      expect(restored.visibleToEmployee, isTrue);
    });

    test('toFirestoreMap → fromFirestore round-trip (camelCase, Timestamp)',
        () async {
      // Über FakeFirebaseFirestore schreiben/lesen, damit serverTimestamp
      // materialisiert wird (wie im echten Pfad).
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('t').doc('doc-1').set(doc.toFirestoreMap());
      final snap = await firestore.collection('t').doc('doc-1').get();
      final restored = EmployeeDocument.fromFirestore('doc-1', snap.data()!);
      expect(restored.category, DocumentCategory.arbeitsvertrag);
      expect(restored.title, 'Arbeitsvertrag 2026');
      expect(restored.sizeBytes, 12345);
      expect(restored.visibleToEmployee, isTrue);
      expect(restored.storagePath, 'employee-documents/org-1/emp-1/doc-1');
      expect(restored.createdAt, isNotNull); // serverTimestamp materialisiert
    });

    test('fromValue-Default sonstiges bei unbekannter Kategorie', () {
      expect(DocumentCategoryX.fromValue('quatsch'), DocumentCategory.sonstiges);
      expect(DocumentCategoryX.fromValue(null), DocumentCategory.sonstiges);
    });

    test('unsichtbares Dokument (visibleToEmployee=false) round-trippt', () {
      final internal = doc.copyWith(visibleToEmployee: false);
      expect(EmployeeDocument.fromMap(internal.toMap()).visibleToEmployee,
          isFalse);
    });

    test('retentionUntil defaults je Kategorie plausibel', () {
      expect(DocumentCategory.lohnabrechnung.defaultRetentionYears, 6);
      expect(DocumentCategory.krankmeldung.defaultRetentionYears, 2);
      expect(DocumentCategory.arbeitsvertrag.defaultRetentionYears, 10);
    });

    test('PA-8.1: retentionExpired', () {
      const ohne = EmployeeDocument(
        orgId: 'org-1', userId: 'emp-1', title: 'x', storagePath: 'p');
      // Keine Frist → nie abgelaufen.
      expect(ohne.retentionExpired(DateTime(2100)), isFalse);
      final mitFrist = doc.copyWith(retentionUntil: DateTime(2026, 7, 1));
      expect(mitFrist.retentionExpired(DateTime(2026, 6, 30)), isFalse);
      expect(mitFrist.retentionExpired(DateTime(2026, 7, 1, 12)), isFalse);
      expect(mitFrist.retentionExpired(DateTime(2026, 7, 2)), isTrue);
    });

    test('copyWith clearAcknowledgedAt entfernt die Lesebestätigung', () {
      final acked =
          doc.copyWith(acknowledgedAt: DateTime(2026, 7, 3));
      expect(acked.acknowledged, isTrue);
      expect(acked.copyWith(clearAcknowledgedAt: true).acknowledged, isFalse);
    });
  });
}
