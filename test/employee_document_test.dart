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

    test('AllTec-Paritäts-Kategorien: value↔fromValue round-trippen + Alias',
        () {
      for (final c in DocumentCategory.values) {
        expect(DocumentCategoryX.fromValue(c.value), c,
            reason: 'Kategorie ${c.name} muss round-trippen');
      }
      // AllTec nennt Schulungen `fortbildung` — Alias mappt aufs WorkTime-Enum.
      expect(DocumentCategoryX.fromValue('fortbildung'),
          DocumentCategory.schulung);
      // Neue Kategorien haben deutsche Labels + Retention-Defaults.
      expect(DocumentCategory.abmahnung.label, 'Abmahnung');
      expect(DocumentCategory.abmahnung.defaultRetentionYears, 3);
      expect(DocumentCategory.kuendigung.defaultRetentionYears, 10);
      expect(DocumentCategory.fuehrungszeugnis.defaultRetentionYears, 3);
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

  group('PERSONAL-4: Workflow-Felder', () {
    test('neue Felder round-trippen in beiden Formaten + clearX', () {
      final full = doc.copyWith(
        requiresAcknowledgement: true,
        visibleSince: DateTime(2026, 7, 1, 9),
        openedAt: DateTime(2026, 7, 2, 10),
        downloadedAt: DateTime(2026, 7, 2, 11),
        declinedAt: DateTime(2026, 7, 3, 12),
        declineComment: 'passt nicht',
      );
      final local = EmployeeDocument.fromMap(full.toMap());
      expect(local.requiresAcknowledgement, isTrue);
      expect(local.visibleSince, DateTime(2026, 7, 1, 9));
      expect(local.openedAt, DateTime(2026, 7, 2, 10));
      expect(local.downloadedAt, DateTime(2026, 7, 2, 11));
      expect(local.declinedAt, DateTime(2026, 7, 3, 12));
      expect(local.declineComment, 'passt nicht');

      final cloud =
          EmployeeDocument.fromFirestore('doc-1', full.toFirestoreMap());
      expect(cloud.requiresAcknowledgement, isTrue);
      expect(cloud.declineComment, 'passt nicht');

      // clearX-Flags.
      final cleared = full.copyWith(
        clearVisibleSince: true,
        clearOpenedAt: true,
        clearDownloadedAt: true,
        clearDeclinedAt: true,
        clearDeclineComment: true,
      );
      expect(cleared.visibleSince, isNull);
      expect(cleared.openedAt, isNull);
      expect(cleared.declinedAt, isNull);
      expect(cleared.declineComment, isNull);
    });

    test('workflowStatus: abgeleitet, Ablehnung schlägt Bestätigung', () {
      // offen: nicht sichtbar, keine Bereitstellung.
      const offen = EmployeeDocument(
        orgId: 'o',
        userId: 'u',
        title: 't',
        storagePath: 'p',
        visibleToEmployee: false,
      );
      expect(offen.workflowStatus, EmployeeDocumentWorkflowStatus.offen);

      // bereitgestellt: sichtbar + visibleSince (bzw. createdAt-Fallback).
      final bereit = doc.copyWith(visibleSince: DateTime(2026, 7, 1));
      expect(bereit.workflowStatus,
          EmployeeDocumentWorkflowStatus.bereitgestellt);

      // geöffnet.
      final geoeffnet = bereit.copyWith(openedAt: DateTime(2026, 7, 2));
      expect(
          geoeffnet.workflowStatus, EmployeeDocumentWorkflowStatus.geoeffnet);

      // bestätigt.
      final bestaetigt = geoeffnet.copyWith(acknowledgedAt: DateTime(2026, 7, 3));
      expect(bestaetigt.workflowStatus,
          EmployeeDocumentWorkflowStatus.bestaetigt);

      // abgelehnt schlägt bestätigt (selbst wenn acknowledgedAt gesetzt wäre).
      final abgelehnt = bestaetigt.copyWith(declinedAt: DateTime(2026, 7, 4));
      expect(
          abgelehnt.workflowStatus, EmployeeDocumentWorkflowStatus.abgelehnt);
    });

    test('effectiveVisibleSince fällt auf createdAt zurück (Q6-Migration)', () {
      final bestand = doc.copyWith(createdAt: DateTime(2026, 1, 1));
      expect(bestand.visibleSince, isNull);
      expect(bestand.effectiveVisibleSince, DateTime(2026, 1, 1));
    });
  });
}
