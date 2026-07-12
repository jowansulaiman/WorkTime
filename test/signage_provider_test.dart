import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/ad_media.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/signage_display.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/signage_provider.dart';
import 'package:worktime_app/repositories/firestore_signage_repository.dart';
import 'package:worktime_app/repositories/signage_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/document_storage.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// In-Memory-Storage-Fake (kein echtes Firebase Storage im Test).
class _FakeStorage implements DocumentStorage {
  final Map<String, Uint8List> objects = {};

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    objects[path] = bytes;
  }

  @override
  Future<Uint8List?> download(String path, {int maxSizeBytes = 15 * 1024 * 1024}) async =>
      objects[path];

  @override
  Future<void> delete(String path) async {
    objects.remove(path);
  }

  @override
  Future<String> getDownloadUrl(String path) async =>
      'https://fake.storage/$path?alt=media&token=t';
}

/// Delegiert an ein echtes Repository, lässt aber saveDisplay fehlschlagen →
/// testet den hybrid-Offline-Fallback des Providers.
class _OfflineSignageRepository implements SignageRepository {
  _OfflineSignageRepository(FakeFirebaseFirestore firestore)
      : _delegate = FirestoreSignageRepository(firestore: firestore);

  final SignageRepository _delegate;

  @override
  Future<void> saveDisplay(SignageDisplay display) async {
    throw Exception('offline');
  }

  @override
  String newMediaId(String orgId) => _delegate.newMediaId(orgId);
  @override
  Stream<List<AdMedia>> watchMedia(String orgId) => _delegate.watchMedia(orgId);
  @override
  Future<void> saveMedia(AdMedia media) => _delegate.saveMedia(media);
  @override
  Future<void> deleteMedia({required String orgId, required String mediaId}) =>
      _delegate.deleteMedia(orgId: orgId, mediaId: mediaId);
  @override
  Stream<List<SignageDisplay>> watchDisplays(String orgId) =>
      _delegate.watchDisplays(orgId);
  @override
  Future<void> deleteDisplay({required String orgId, required String displayId}) =>
      _delegate.deleteDisplay(orgId: orgId, displayId: displayId);
  @override
  Future<void> publishPublicDisplay(String token, Map<String, dynamic> p) =>
      _delegate.publishPublicDisplay(token, p);
  @override
  Future<void> unpublishPublicDisplay(String token) =>
      _delegate.unpublishPublicDisplay(token);
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  const user = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );

  late FakeFirebaseFirestore firestore;
  late FirestoreService firestoreService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: firestore);
  });

  SignageProvider newLocalProvider() => SignageProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );

  Future<String> seedMedia({
    required String id,
    required String title,
    required String url,
  }) async {
    await firestore
        .collection('organizations')
        .doc('org-1')
        .collection('adMedia')
        .doc(id)
        .set(AdMedia(
          id: id,
          orgId: 'org-1',
          title: title,
          storagePath: 'organizations/org-1/signage/$id.jpg',
          downloadUrl: url,
        ).toFirestoreMap());
    return id;
  }

  group('SignageProvider – lokaler Modus', () {
    test('neues Display bekommt lokale ID + generierten Token, sortiert', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);

      await provider.saveDisplay(
        const SignageDisplay(orgId: 'org-1', name: 'Zeta', pairingToken: ''),
      );
      await provider.saveDisplay(
        const SignageDisplay(orgId: 'org-1', name: 'Alpha', pairingToken: ''),
      );

      expect(provider.displays, hasLength(2));
      expect(provider.displays.first.name, 'Alpha'); // alphabetisch
      expect(provider.displays.every((d) => d.id != null), isTrue);
      expect(
        provider.displays.every((d) => d.pairingToken.length >= 20),
        isTrue,
        reason: 'jedes Display muss einen unratbaren Token bekommen',
      );
    });

    test('persistiert lokal und stellt nach Neustart wieder her', () async {
      final provider = newLocalProvider();
      await provider.updateSession(user);
      await provider.saveDisplay(
        const SignageDisplay(
          orgId: 'org-1',
          name: 'Schaufenster',
          pairingToken: 'TOK',
          slideSeconds: 15,
          mediaIds: ['m1'],
        ),
      );

      final restored = newLocalProvider();
      await restored.updateSession(user);

      expect(restored.displays.single.name, 'Schaufenster');
      expect(restored.displays.single.slideSeconds, 15);
      expect(restored.displays.single.mediaIds, ['m1']);
    });

    test('mediaUploadAvailable ist im lokalen Modus false', () async {
      final provider = newLocalProvider()..setDocumentStorage(_FakeStorage());
      await provider.updateSession(user);
      expect(provider.mediaUploadAvailable, isFalse);
    });

    test('uploadMedia wirft im lokalen Modus (Cloud-only)', () async {
      final provider = newLocalProvider()..setDocumentStorage(_FakeStorage());
      await provider.updateSession(user);
      expect(
        () => provider.uploadMedia(
          title: 'X',
          bytes: Uint8List.fromList([1, 2, 3]),
          fileExtension: 'png',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SignageProvider – Cloud-Modus', () {
    test('lädt Displays + Werbebilder aus Firestore', () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('signageDisplays')
          .doc('d1')
          .set(const SignageDisplay(
            orgId: 'org-1',
            name: 'Eingang',
            pairingToken: 'TOK1',
          ).toFirestoreMap());

      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(user);
      await _pump();

      expect(provider.displays.map((d) => d.name), contains('Eingang'));
      expect(provider.media.map((m) => m.title), contains('Sommer'));
    });

    test('saveDisplay veröffentlicht die Projektion mit aufgelösten Folien',
        () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(user);
      await _pump();

      await provider.saveDisplay(
        const SignageDisplay(
          orgId: 'org-1',
          name: 'Schaufenster',
          pairingToken: 'PUBTOK',
          slideSeconds: 10,
          fit: SignageFit.contain,
          transition: SignageTransition.zoom,
          mediaIds: ['m1'],
        ),
      );
      await _pump();

      final snap =
          await firestore.collection('publicDisplays').doc('PUBTOK').get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['name'], 'Schaufenster');
      expect(data['fit'], 'contain');
      expect(data['transition'], 'zoom');
      expect(data['isActive'], isTrue);
      final slides = (data['slides'] as List).cast<Map<String, dynamic>>();
      expect(slides, hasLength(1));
      expect(slides.first['url'], 'https://x/1.jpg');
      expect(slides.first['seconds'], 10);
      expect(slides.first['title'], 'Sommer');
    });

    test('setDisplayActive(false) behält die Projektion mit isActive:false '
        '(Player zeigt „pausiert", nicht „nicht gefunden")', () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(user);
      await _pump();

      const display = SignageDisplay(
        orgId: 'org-1',
        name: 'S',
        pairingToken: 'PUBTOK',
        mediaIds: ['m1'],
      );
      await provider.saveDisplay(display);
      await _pump();

      await provider.setDisplayActive(display, isActive: false);
      await _pump();

      final snap =
          await firestore.collection('publicDisplays').doc('PUBTOK').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['isActive'], isFalse);
    });

    test('deleteDisplay entfernt die öffentliche Projektion', () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(user);
      await _pump();

      await provider.saveDisplay(const SignageDisplay(
        orgId: 'org-1',
        name: 'S',
        pairingToken: 'PUBTOK',
        mediaIds: ['m1'],
      ));
      await _pump();
      final id = provider.displays.single.id!;

      await provider.deleteDisplay(id);
      await _pump();

      expect(provider.displays, isEmpty);
      expect(
        (await firestore.collection('publicDisplays').doc('PUBTOK').get()).exists,
        isFalse,
      );
    });

    test('deleteMedia entfernt das Bild aus der Playlist der Displays', () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(user);
      await _pump();

      await provider.saveDisplay(
        const SignageDisplay(
          orgId: 'org-1',
          name: 'S',
          pairingToken: 'PUBTOK',
          mediaIds: ['m1'],
        ),
      );
      await _pump();

      await provider.deleteMedia('m1');
      await _pump();

      expect(provider.media, isEmpty);
      expect(provider.displays.single.mediaIds, isEmpty);
      // Projektion neu geschrieben ohne Folien.
      final snap =
          await firestore.collection('publicDisplays').doc('PUBTOK').get();
      expect((snap.data()!['slides'] as List), isEmpty);
    });

    test('uploadMedia lädt hoch, legt Metadaten an und protokolliert', () async {
      final logged = <String>[];
      final provider = SignageProvider(firestoreService: firestoreService)
        ..setDocumentStorage(_FakeStorage())
        ..setAuditSink((
            {required AuditAction action,
            required String entityType,
            String? entityId,
            required String summary}) {
          logged.add(summary);
        });
      await provider.updateSession(user);
      await _pump();

      expect(provider.mediaUploadAvailable, isTrue);
      final media = await provider.uploadMedia(
        title: 'Herbst',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        fileExtension: 'PNG',
      );
      await _pump();

      expect(media.downloadUrl, startsWith('https://fake.storage/'));
      expect(media.contentType, 'image/png');
      expect(media.storagePath, contains('organizations/org-1/signage/'));
      expect(provider.media.map((m) => m.title), contains('Herbst'));
      expect(logged.any((s) => s.contains('hochgeladen')), isTrue);
      // createdAt wird beim Anlegen als serverTimestamp gesetzt (Doc-Id vergibt
      // das Repository, daher id:null beim Speichern → createdAt-Zweig greift).
      final stored = provider.media.firstWhere((m) => m.title == 'Herbst');
      expect(stored.id, isNotNull);
      expect(stored.createdAt, isNotNull);
    });
  });

  group('SignageProvider – Zugriff', () {
    test('Nicht-Admin lädt/abonniert nichts (admin-only Bereich)', () async {
      await seedMedia(id: 'm1', title: 'Sommer', url: 'https://x/1.jpg');
      const employee = AppUserProfile(
        uid: 'emp-1',
        orgId: 'org-1',
        email: 'peter@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Peter'),
      );
      final provider = SignageProvider(firestoreService: firestoreService);
      await provider.updateSession(employee);
      await _pump();

      expect(provider.media, isEmpty);
      expect(provider.displays, isEmpty);
    });
  });

  group('SignageProvider – hybrid', () {
    test('hybrid-Offline: fehlgeschlagener Cloud-Write wird lokal persistiert',
        () async {
      final provider = SignageProvider(
        firestoreService: firestoreService,
        signageRepository: _OfflineSignageRepository(firestore),
      );
      await provider.updateSession(user, hybridStorageEnabled: true);

      await provider.saveDisplay(
        const SignageDisplay(
          id: 'd-off',
          orgId: 'org-1',
          name: 'Offline-Display',
          pairingToken: 'T',
        ),
      );

      final persisted = await DatabaseService.loadLocalSignageDisplays(
        scope: LocalStorageScope.fromUser(user),
      );
      expect(persisted.any((d) => d.id == 'd-off'), isTrue);
    });
  });
}
