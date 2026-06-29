import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/providers/work_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// M2b: Status-Workflow-Mutatoren (submit/approve/reject) auf WorkProvider.
///
/// `provider.entries` ist auf den Session-Nutzer gefiltert (Self-View). Eigene
/// Übergänge werden lokal geprüft; das Genehmigen/Ablehnen FREMDER Einträge
/// (Manager) wird im Cloud-Modus über einen mitschneidenden FirestoreService
/// verifiziert — dort sieht man, dass der Eigentümer NICHT überschrieben wird.
class _CapturingFirestoreService extends FirestoreService {
  _CapturingFirestoreService({required super.firestore});

  WorkEntry? saved;

  @override
  Future<void> saveWorkEntry(WorkEntry entry) async {
    saved = entry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const employee = AppUserProfile(
    uid: 'emp-1',
    orgId: 'org-1',
    email: 'emp@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Mitarbeiter'),
  );
  const admin = AppUserProfile(
    uid: 'adm-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Admin'),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  WorkEntry draftEntry({String userId = 'emp-1'}) => WorkEntry(
        id: 'e1',
        orgId: 'org-1',
        userId: userId,
        date: DateTime(2026, 6, 10),
        startTime: DateTime(2026, 6, 10, 9),
        endTime: DateTime(2026, 6, 10, 13),
        status: WorkEntryStatus.draft,
      );

  group('eigene Einträge (lokal, Self-View)', () {
    test('submitWorkEntry: eigener Entwurf → eingereicht', () async {
      await DatabaseService.saveLocalEntries(
        [draftEntry()],
        scope: LocalStorageScope.fromUser(employee),
      );
      final provider = WorkProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);
      await provider.selectMonth(DateTime(2026, 6, 1));
      expect(provider.entries.single.status, WorkEntryStatus.draft);

      await provider.submitWorkEntry(provider.entries.single);

      expect(provider.entries.single.status, WorkEntryStatus.submitted);
    });

    test('approveWorkEntry ohne Manager-Recht ist ein No-Op', () async {
      await DatabaseService.saveLocalEntries(
        [draftEntry()],
        scope: LocalStorageScope.fromUser(employee),
      );
      final provider = WorkProvider(
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );
      await provider.updateSession(employee, localStorageOnly: true);
      await provider.selectMonth(DateTime(2026, 6, 1));

      await provider.approveWorkEntry(provider.entries.single);

      // Mitarbeiter hat kein canManageShifts → Status unverändert.
      expect(provider.entries.single.status, WorkEntryStatus.draft);
    });
  });

  group('Manager-Übergänge auf fremde Einträge (Cloud, mitgeschnitten)', () {
    test('approveWorkEntry: genehmigt + approvedByUid, Eigentümer bleibt', () async {
      final capture =
          _CapturingFirestoreService(firestore: FakeFirebaseFirestore());
      final provider = WorkProvider(firestoreService: capture);
      await provider.updateSession(admin); // cloud-only

      await provider.approveWorkEntry(draftEntry());

      expect(capture.saved, isNotNull);
      expect(capture.saved!.status, WorkEntryStatus.approved);
      expect(capture.saved!.approvedByUid, 'adm-1');
      expect(capture.saved!.approvedAt, isNotNull);
      expect(capture.saved!.userId, 'emp-1'); // kein userId-Overwrite
    });

    test('rejectWorkEntry: abgelehnt, Grund landet in note', () async {
      final capture =
          _CapturingFirestoreService(firestore: FakeFirebaseFirestore());
      final provider = WorkProvider(firestoreService: capture);
      await provider.updateSession(admin);

      await provider.rejectWorkEntry(draftEntry(), reason: 'Unplausibel');

      expect(capture.saved!.status, WorkEntryStatus.rejected);
      expect(capture.saved!.note, 'Unplausibel');
      expect(capture.saved!.approvedByUid, 'adm-1');
    });

    test('submitWorkEntry auf fremden Eintrag ist ein No-Op', () async {
      final capture =
          _CapturingFirestoreService(firestore: FakeFirebaseFirestore());
      final provider = WorkProvider(firestoreService: capture);
      await provider.updateSession(admin);

      await provider.submitWorkEntry(draftEntry()); // emp-1, nicht admin

      expect(capture.saved, isNull);
    });
  });
}
