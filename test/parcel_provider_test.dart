import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/audit_log_entry.dart';
import 'package:worktime_app/models/paketshop_settings.dart';
import 'package:worktime_app/models/parcel_customer.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/shelf_compartment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/repositories/parcel_repository.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Cloud-Repo, das bei jeder Schreib-/Lese-Operation offline ist (triggert den
/// Hybrid-Fallback). Streams sind leer, damit die Subscriptions nicht in den
/// Fehlerzustand laufen.
class _OfflineParcelRepository implements ParcelRepository {
  @override
  Stream<List<ParcelShipment>> watchParcels(String orgId) =>
      Stream.value(const []);
  @override
  Stream<List<ShelfCompartment>> watchCompartments(String orgId) =>
      Stream.value(const []);
  @override
  Stream<List<ParcelCustomer>> watchCustomers(String orgId) =>
      Stream.value(const []);

  Never _down() => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'offline',
      );

  @override
  Future<String> saveParcel(ParcelShipment shipment) async => _down();
  @override
  Future<void> deleteParcel({required String orgId, required String id}) async =>
      _down();
  @override
  Future<String> saveCompartment(ShelfCompartment compartment) async =>
      _down();
  @override
  Future<void> deleteCompartment({
    required String orgId,
    required String id,
  }) async =>
      _down();
  @override
  Future<String> saveCustomer(ParcelCustomer customer) async => _down();
  @override
  Future<void> deleteCustomer({required String orgId, required String id}) async =>
      _down();
  @override
  Future<PaketshopSettings?> fetchSettings(String orgId) async => _down();
  @override
  Future<void> saveSettings(String orgId, PaketshopSettings settings) async =>
      _down();
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
  const siteId = 'site-tb';

  late FirestoreService firestoreService;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
    firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
  });

  ParcelShipment parcel(
    String first,
    String last, {
    String? trackingCode,
    String? compartmentId,
    String? compartmentLabel,
    DateTime? arrivedAt,
    ShipmentStatus status = ShipmentStatus.eingelagert,
  }) =>
      ParcelShipment(
        orgId: 'org-1',
        siteId: siteId,
        recipientFirstName: first,
        recipientLastName: last,
        trackingCode: trackingCode,
        compartmentId: compartmentId,
        compartmentLabel: compartmentLabel,
        status: status,
        arrivedAt: arrivedAt ?? DateTime(2026, 7, 13, 10),
      );

  ParcelProvider localProvider() =>
      ParcelProvider(firestoreService: firestoreService, disableAuthentication: true);

  group('ParcelProvider – lokal', () {
    test('saveParcel persistiert, reload stellt wieder her, openParcels', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);

      final id = await provider.saveParcel(parcel('Max', 'Müller'));
      expect(id, isNotEmpty);
      expect(provider.parcels, hasLength(1));
      expect(provider.openParcels, hasLength(1));

      final restarted = localProvider();
      await restarted.updateSession(user, localStorageOnly: true);
      expect(restarted.parcels, hasLength(1));
      expect(restarted.parcels.single.recipientLastName, 'Müller');
    });

    test('Fach-Belegung ist abgeleitet; Ausgabe gibt das Fach frei', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);

      final fachId = await provider.saveCompartment(
        const ShelfCompartment(
          orgId: 'org-1',
          siteId: siteId,
          label: 'A2',
          barcode: 'BC-A2',
        ),
      );
      final pid = await provider.saveParcel(
        parcel('Max', 'Müller', compartmentId: fachId, compartmentLabel: 'A2'),
      );

      expect(provider.compartmentOccupancy[fachId], 1);
      expect(provider.freeCompartments, isEmpty);
      expect(provider.parcelsInCompartment(fachId), hasLength(1));

      // Ausgeben: compartmentId bleibt erhalten, Fach wird aber frei.
      final stored = provider.parcels.firstWhere((p) => p.id == pid);
      await provider.saveParcel(
        stored.copyWith(
          status: ShipmentStatus.abgeholt,
          handedOutAt: DateTime(2026, 7, 14),
        ),
      );
      expect(provider.compartmentOccupancy[fachId], isNull);
      expect(provider.freeCompartments.map((f) => f.id), contains(fachId));
      expect(provider.parcels.firstWhere((p) => p.id == pid).compartmentId,
          fachId);
    });

    test('upsertCustomer entdoppelt über nameLower', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);

      final first = await provider.upsertCustomer(
        firstName: 'Max',
        lastName: 'Müller',
        siteId: siteId,
      );
      final again = await provider.upsertCustomer(
        firstName: 'max',
        lastName: 'müller',
        siteId: siteId,
      );
      await provider.upsertCustomer(
        firstName: 'Anna',
        lastName: 'Abel',
        siteId: siteId,
      );

      expect(provider.customers, hasLength(2));
      expect(again.id, first.id); // gleicher Datensatz aktualisiert
      expect(provider.parcelCustomersMatching('müll').single.lastName, 'Müller');
    });

    test('overdueParcels nutzt die konfigurierte Frist', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);
      await provider.saveSettings(
        const PaketshopSettings(overdueFristTage: 6),
      );

      await provider.saveParcel(
        parcel('Alt', 'Fall', arrivedAt: DateTime(2026, 7, 1)),
      );
      await provider.saveParcel(
        parcel('Neu', 'Fall', arrivedAt: DateTime(2026, 7, 12)),
      );

      final overdue = provider.overdueParcels(DateTime(2026, 7, 13, 12));
      expect(overdue, hasLength(1));
      expect(overdue.single.recipientFirstName, 'Alt');
    });

    test('findParcelByCode: exakt + Suffix', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);
      await provider.saveParcel(parcel('Max', 'Müller', trackingCode: 'H0001234567890'));

      expect(provider.findParcelByCode('H0001234567890'), hasLength(1));
      expect(provider.findParcelByCode('4567890'), hasLength(1));
      expect(provider.findParcelByCode('999'), isEmpty);
    });

    test('deleteCustomer entkoppelt referenzierende Pakete', () async {
      final provider = localProvider();
      await provider.updateSession(user, localStorageOnly: true);

      final cust = await provider.upsertCustomer(
        firstName: 'Max',
        lastName: 'Müller',
        siteId: siteId,
      );
      final pid = await provider.saveParcel(
        parcel('Max', 'Müller').copyWith(parcelCustomerId: cust.id),
      );
      expect(provider.parcels.firstWhere((p) => p.id == pid).parcelCustomerId,
          cust.id);

      await provider.deleteCustomer(cust.id!);

      expect(provider.customers, isEmpty);
      expect(provider.parcels.firstWhere((p) => p.id == pid).parcelCustomerId,
          isNull);
    });
  });

  group('ParcelProvider – Audit (nur auf Erfolg, personenfrei)', () {
    test('saveParcel + deleteCustomer loggen personenfrei', () async {
      final events = <Map<String, Object?>>[];
      final provider = localProvider()
        ..setAuditSink(({
          required AuditAction action,
          required String entityType,
          String? entityId,
          required String summary,
        }) {
          events.add({
            'action': action,
            'type': entityType,
            'summary': summary,
          });
        });
      await provider.updateSession(user, localStorageOnly: true);

      await provider.saveParcel(
        parcel('Max', 'Müller', compartmentLabel: 'A2'),
      );

      final created = events.singleWhere((e) => e['type'] == 'Paket');
      expect(created['action'], AuditAction.created);
      expect(created['summary'], 'Paket angenommen (Fach A2)');
      // Personenfrei: kein Empfängername im Protokoll.
      expect((created['summary'] as String).toLowerCase(), isNot(contains('müller')));

      final cust = await provider.upsertCustomer(
        firstName: 'Max',
        lastName: 'Müller',
        siteId: siteId,
      );
      events.clear();
      await provider.deleteCustomer(cust.id!);
      final del = events.firstWhere((e) => e['type'] == 'Paketkunde');
      expect(del['action'], AuditAction.deleted);
      expect((del['summary'] as String).toLowerCase(), isNot(contains('müller')));
    });
  });

  group('ParcelProvider – cloud (FakeFirebaseFirestore)', () {
    test('saveParcel schreibt in Firestore und Stream aktualisiert', () async {
      final provider =
          ParcelProvider(firestoreService: firestoreService, disableAuthentication: false);
      await provider.updateSession(user);
      await Future<void>.delayed(Duration.zero);

      final id = await provider.saveParcel(parcel('Max', 'Müller'));
      expect(id, isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.parcels.map((p) => p.id), contains(id));

      await provider.deleteParcel(id);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(provider.parcels, isEmpty);
    });

    test('Config-Load liest overdueFristTage aus config/paketshopSettings',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake
          .collection('organizations')
          .doc('org-1')
          .collection('config')
          .doc('paketshopSettings')
          .set({'overdueFristTage': 8});

      final provider = ParcelProvider(
        firestoreService: FirestoreService(firestore: fake),
        disableAuthentication: false,
      );
      await provider.updateSession(user);
      await Future<void>.delayed(Duration.zero);

      expect(provider.settings.overdueFristTage, 8);
    });
  });

  group('ParcelProvider – hybrid Offline-Fallback', () {
    test('saveParcel fällt bei Offline lokal zurück (kein rethrow)', () async {
      final provider = ParcelProvider(
        firestoreService: firestoreService,
        parcelRepository: _OfflineParcelRepository(),
        disableAuthentication: false,
      );
      await provider.updateSession(user, hybridStorageEnabled: true);
      await Future<void>.delayed(Duration.zero);

      final id = await provider.saveParcel(parcel('Max', 'Müller'));
      expect(id, startsWith('local-'));
      expect(provider.parcels, hasLength(1));
      // Config-Fetch war offline → Defaults, kein Crash.
      expect(provider.settings.overdueFristTage, 6);
    });
  });
}
