import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/employee_document.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/document_storage.dart';
import 'package:worktime_app/services/firestore_service.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@demo.local',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Admin'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

/// In-Memory-Storage-Fake: merkt sich Bytes je Pfad, zählt Deletes.
class _FakeDocumentStorage implements DocumentStorage {
  final Map<String, Uint8List> files = {};
  final List<String> deleted = [];
  bool failNextUpload = false;

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (failNextUpload) {
      failNextUpload = false;
      throw StateError('upload boom');
    }
    onProgress?.call(1.0);
    files[path] = bytes;
  }

  @override
  Future<Uint8List?> download(String path, {int maxSizeBytes = 15 * 1024 * 1024}) async =>
      files[path];

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    files.remove(path);
  }
}

/// FirestoreService, dessen Metadaten-Write fehlschlägt (für Rollback-Test).
class _FailingDocMetaService extends FirestoreService {
  _FailingDocMetaService({required super.firestore});

  @override
  Future<void> saveEmployeeDocument(EmployeeDocument document) async {
    throw StateError('firestore boom');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FirestoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    service = FirestoreService(firestore: firestore);
  });

  Uint8List bytes() => Uint8List.fromList(List<int>.filled(64, 7));

  group('PersonalProvider Dokumente (PA-3)', () {
    test('Admin lädt hoch → Storage + Metadaten + Audit + Provider-Liste',
        () async {
      final storage = _FakeDocumentStorage();
      final logged = <String>[];
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      provider.setDocumentStorage(storage);
      provider.setAuditSink(({
        required action,
        required entityType,
        entityId,
        required summary,
      }) =>
          logged.add(entityType));
      await provider.updateSession(_admin); // Cloud
      await Future<void>.delayed(Duration.zero);

      await provider.uploadDocument(
        userId: 'emp-1',
        category: DocumentCategory.arbeitsvertrag,
        title: 'Vertrag 2026',
        fileName: 'vertrag.pdf',
        contentType: 'application/pdf',
        bytes: bytes(),
      );
      await Future<void>.delayed(Duration.zero);

      // Storage hat genau ein Objekt unter dem erwarteten Pfad-Präfix.
      expect(storage.files.keys.single,
          startsWith('employee-documents/org-1/emp-1/'));
      // Metadaten-Doc ist da und in der Provider-Liste.
      final docs = provider.documentsForUser('emp-1');
      expect(docs, hasLength(1));
      expect(docs.single.title, 'Vertrag 2026');
      expect(docs.single.sizeBytes, 64);
      expect(docs.single.retentionUntil, isNotNull); // Default-Frist gesetzt
      expect(logged, contains('Personaldokument'));
    });

    test('Upload-Rollback: Metadaten-Fehler entfernt das Storage-Objekt',
        () async {
      final storage = _FakeDocumentStorage();
      final provider = PersonalProvider(
          firestoreService: _FailingDocMetaService(firestore: firestore));
      addTearDown(provider.dispose);
      provider.setDocumentStorage(storage);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        provider.uploadDocument(
          userId: 'emp-1',
          category: DocumentCategory.sonstiges,
          title: 'X',
          fileName: 'x.pdf',
          contentType: 'application/pdf',
          bytes: bytes(),
        ),
        throwsA(isA<StateError>()),
      );
      // Kein verwaistes Binary: das hochgeladene Objekt wurde wieder gelöscht.
      expect(storage.files, isEmpty);
      expect(storage.deleted, hasLength(1));
    });

    test('Nicht-Admin darf nicht hochladen', () async {
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      provider.setDocumentStorage(_FakeDocumentStorage());
      await provider.updateSession(_employee);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        provider.uploadDocument(
          userId: 'emp-1',
          category: DocumentCategory.sonstiges,
          title: 'X',
          fileName: 'x.pdf',
          contentType: 'application/pdf',
          bytes: bytes(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Löschen entfernt Metadaten UND Storage-Objekt', () async {
      final storage = _FakeDocumentStorage();
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      provider.setDocumentStorage(storage);
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);

      await provider.uploadDocument(
        userId: 'emp-1',
        category: DocumentCategory.zeugnis,
        title: 'Zeugnis',
        fileName: 'z.pdf',
        contentType: 'application/pdf',
        bytes: bytes(),
      );
      await Future<void>.delayed(Duration.zero);
      final doc = provider.documentsForUser('emp-1').single;

      await provider.deleteDocument(doc);
      await Future<void>.delayed(Duration.zero);

      expect(provider.documentsForUser('emp-1'), isEmpty);
      expect(storage.files, isEmpty);
    });

    test('updateDocumentMeta ändert Titel/Kategorie/Sichtbarkeit + Notiz-Clear '
        '(Datei unangetastet)', () async {
      final storage = _FakeDocumentStorage();
      final logged = <String>[];
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      provider.setDocumentStorage(storage);
      provider.setAuditSink(({
        required action,
        required entityType,
        entityId,
        required summary,
      }) =>
          logged.add('${action.name}:$entityType'));
      await provider.updateSession(_admin);
      await Future<void>.delayed(Duration.zero);

      await provider.uploadDocument(
        userId: 'emp-1',
        category: DocumentCategory.sonstiges,
        title: 'Alt',
        fileName: 'x.pdf',
        contentType: 'application/pdf',
        bytes: bytes(),
        note: 'alte Notiz',
      );
      await Future<void>.delayed(Duration.zero);
      final doc = provider.documentsForUser('emp-1').single;
      final storedBytes = Map.of(storage.files);

      await provider.updateDocumentMeta(
        doc,
        title: 'Abmahnung 07/2026',
        category: DocumentCategory.abmahnung,
        visibleToEmployee: false,
        clearNote: true,
      );
      await Future<void>.delayed(Duration.zero);

      final updated = provider.documentsForUser('emp-1').single;
      expect(updated.title, 'Abmahnung 07/2026');
      expect(updated.category, DocumentCategory.abmahnung);
      expect(updated.visibleToEmployee, isFalse);
      expect(updated.note, isNull);
      // Binärdatei unverändert (kein Re-Upload, kein Delete).
      expect(storage.files, storedBytes);
      expect(logged, contains('updated:Personaldokument'));
    });

    test('Nicht-Admin darf Metadaten nicht bearbeiten', () async {
      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        provider.updateDocumentMeta(
          const EmployeeDocument(
            id: 'd-x',
            orgId: 'org-1',
            userId: 'emp-1',
            title: 'x',
            storagePath: 'p',
          ),
          title: 'Neu',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Mitarbeiter-Self-Stream sieht NUR eigene SICHTBARE Dokumente',
        () async {
      // Zwei Dokumente von emp-1: sichtbar + intern; eins von emp-2.
      await service.saveEmployeeDocument(const EmployeeDocument(
        id: 'd-visible',
        orgId: 'org-1',
        userId: 'emp-1',
        title: 'Sichtbar',
        storagePath: 'employee-documents/org-1/emp-1/d-visible',
        visibleToEmployee: true,
      ));
      await service.saveEmployeeDocument(const EmployeeDocument(
        id: 'd-internal',
        orgId: 'org-1',
        userId: 'emp-1',
        title: 'Intern',
        storagePath: 'employee-documents/org-1/emp-1/d-internal',
        visibleToEmployee: false,
      ));
      await service.saveEmployeeDocument(const EmployeeDocument(
        id: 'd-other',
        orgId: 'org-1',
        userId: 'emp-2',
        title: 'Fremd',
        storagePath: 'employee-documents/org-1/emp-2/d-other',
        visibleToEmployee: true,
      ));

      final provider = PersonalProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee); // Nicht-Admin emp-1
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final titles = provider.documents.map((d) => d.title).toList();
      expect(titles, ['Sichtbar']);
    });
  });
}
