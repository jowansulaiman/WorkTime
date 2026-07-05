import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// PA-4.1: `{userId}-open`-Doppel-Stempel-Guard — Transaktions-Semantik im
/// FirestoreService + Provider-Verhalten (copy+delete beim clockOut,
/// Legacy-Buchungen in place). Kiosk-Spiegel (`kioskClockPunch` mit `create()`)
/// ist Server-seitig — Emulator-Verifikation in PA-9.

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

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

  ClockEntry openEntry({String? id}) => ClockEntry(
        id: id ?? FirestoreService.openClockDocId('emp-1'),
        orgId: 'org-1',
        userId: 'emp-1',
        kommen: DateTime(2026, 7, 5, 9),
        status: ClockStatus.ongoing,
      );

  group('FirestoreService.clockInOpen (harter Guard)', () {
    test('erster clockIn legt {userId}-open an, zweiter wirft StateError',
        () async {
      await service.clockInOpen(openEntry());
      final doc = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('clockEntries')
          .doc('emp-1-open')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['status'], 'ongoing');

      await expectLater(
        service.clockInOpen(openEntry()),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('Bereits eingestempelt'))),
      );
    });

    test('closeOpenClockEntry kopiert unter endgültige ID und löscht open',
        () async {
      await service.clockInOpen(openEntry());
      final closed = openEntry(id: 'clock-final-1').copyWith(
        gehen: DateTime(2026, 7, 5, 13),
        status: ClockStatus.completed,
        nettoMinutes: 240,
      );
      await service.closeOpenClockEntry(
        orgId: 'org-1',
        userId: 'emp-1',
        closed: closed,
      );
      final col = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('clockEntries');
      expect((await col.doc('emp-1-open').get()).exists, isFalse,
          reason: 'open-Doc muss frei sein für den nächsten clockIn');
      final closedDoc = await col.doc('clock-final-1').get();
      expect(closedDoc.exists, isTrue);
      expect(closedDoc.data()!['status'], 'completed');
      // Danach ist erneutes Einstempeln möglich (ID wieder frei).
      await service.clockInOpen(openEntry());
    });
  });

  group('ZeitwirtschaftProvider (cloud) — open-Doc-Lebenszyklus', () {
    test('clockIn→clockOut: open weg, endgültige Buchung da, WorkEntry '
        'referenziert die ENDGÜLTIGE ID', () async {
      final provider = ZeitwirtschaftProvider(firestoreService: service);
      addTearDown(provider.dispose);
      WorkEntry? posted;
      provider.setWorkEntryPoster((entry) async => posted = entry);
      await provider.updateSession(_employee);
      await Future<void>.delayed(Duration.zero);

      await provider.clockIn(siteId: 'site-1', siteName: 'Kiel');
      final col = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('clockEntries');
      expect((await col.doc('emp-1-open').get()).exists, isTrue);

      await provider.clockOut(pauseMinuten: 0);
      await Future<void>.delayed(Duration.zero);

      expect((await col.doc('emp-1-open').get()).exists, isFalse);
      final all = await col.get();
      expect(all.docs, hasLength(1));
      final closed = all.docs.single;
      expect(closed.data()['status'], 'completed');
      expect(closed.id, isNot('emp-1-open'));
      expect(posted, isNotNull);
      expect(posted!.sourceClockEntryId, closed.id,
          reason: 'Rückverweis muss auf die endgültige Doc-ID zeigen, nicht '
              'auf die wiederverwendbare open-ID');
    });

    test('Legacy-Buchung (zufällige ID) wird in place geschlossen '
        '(Übergangsphase)', () async {
      // Alt-offene Buchung mit zufälliger ID seeden (Vor-PA-4.1-Bestand).
      await service.saveClockEntry(openEntry(id: 'clock-legacy-42'));

      final provider = ZeitwirtschaftProvider(firestoreService: service);
      addTearDown(provider.dispose);
      await provider.updateSession(_employee);
      // Stream liefert die offene Alt-Buchung.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isClockedIn, isTrue);

      await provider.clockOut(pauseMinuten: 0);
      await Future<void>.delayed(Duration.zero);

      final col = firestore
          .collection('organizations')
          .doc('org-1')
          .collection('clockEntries');
      final legacy = await col.doc('clock-legacy-42').get();
      expect(legacy.exists, isTrue, reason: 'Legacy schließt in place');
      expect(legacy.data()!['status'], 'completed');
      expect((await col.doc('emp-1-open').get()).exists, isFalse);
    });

    test('zweite Provider-Instanz sieht die offene Buchung live '
        '(Cross-Device-Sync) und stempelt nicht doppelt ein', () async {
      final a = ZeitwirtschaftProvider(firestoreService: service);
      final b = ZeitwirtschaftProvider(firestoreService: service);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.updateSession(_employee);
      await b.updateSession(_employee);
      await Future<void>.delayed(Duration.zero);

      await a.clockIn();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(b.isClockedIn, isTrue,
          reason: 'Gerät B sieht die auf A gestartete Buchung via Stream');
      // clockIn auf B ist damit No-Op (Client-Guard) — und selbst bei stale
      // State griffe die clockInOpen-Transaktion (siehe Service-Test oben).
      await b.clockIn();
      final all = await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('clockEntries')
          .get();
      expect(all.docs, hasLength(1), reason: 'genau EINE offene Buchung');
    });
  });
}
