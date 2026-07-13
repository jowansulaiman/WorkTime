import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/parcel_customer.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/shelf_compartment.dart';
import 'package:worktime_app/repositories/firestore_parcel_repository.dart';
import 'package:worktime_app/services/database_service.dart';

void main() {
  const orgId = 'org-1';
  const siteId = 'site-tb';

  group('FirestoreParcelRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreParcelRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreParcelRepository(firestore: firestore);
    });

    ParcelShipment shipment(String first, String last) => ParcelShipment(
          orgId: orgId,
          siteId: siteId,
          recipientFirstName: first,
          recipientLastName: last,
          arrivedAt: DateTime(2026, 7, 13, 10),
        );

    test('saveParcel returns a doc id and watchParcels streams sorted', () async {
      final idMueller = await repo.saveParcel(shipment('Max', 'Müller'));
      final idAbel = await repo.saveParcel(shipment('Anna', 'Abel'));

      expect(idMueller, isNotEmpty);
      expect(idAbel, isNotEmpty);
      expect(idMueller, isNot(idAbel));

      final parcels = await repo.watchParcels(orgId).first;
      expect(parcels, hasLength(2));
      // sortiert nach recipientNameLower ("abel anna" < "müller max")
      expect(parcels.first.recipientLastName, 'Abel');
      expect(parcels.last.recipientLastName, 'Müller');
      expect(parcels.last.id, idMueller);
      expect(parcels.last.status, ShipmentStatus.eingelagert);
    });

    test('saveParcel with an existing id updates in place (merge)', () async {
      final id = await repo.saveParcel(shipment('Max', 'Müller'));
      final stored = (await repo.watchParcels(orgId).first).single;

      await repo.saveParcel(
        stored.copyWith(
          status: ShipmentStatus.abgeholt,
          handedOutAt: DateTime(2026, 7, 14),
        ),
      );

      final after = await repo.watchParcels(orgId).first;
      expect(after, hasLength(1));
      expect(after.single.id, id);
      expect(after.single.status, ShipmentStatus.abgeholt);
      expect(after.single.handedOutAt, DateTime(2026, 7, 14));
    });

    test('deleteParcel removes the document', () async {
      final id = await repo.saveParcel(shipment('Max', 'Müller'));
      await repo.deleteParcel(orgId: orgId, id: id);
      expect(await repo.watchParcels(orgId).first, isEmpty);
    });

    test('compartments: save returns id, watch sorts by labelLower, delete',
        () async {
      await repo.saveCompartment(
        const ShelfCompartment(
          orgId: orgId,
          siteId: siteId,
          label: 'B1',
          barcode: 'BC-B1',
        ),
      );
      final idA2 = await repo.saveCompartment(
        const ShelfCompartment(
          orgId: orgId,
          siteId: siteId,
          label: 'A2',
          barcode: 'BC-A2',
        ),
      );

      final compartments = await repo.watchCompartments(orgId).first;
      expect(compartments.map((c) => c.label), ['A2', 'B1']);
      expect(compartments.first.barcode, 'BC-A2');

      await repo.deleteCompartment(orgId: orgId, id: idA2);
      final rest = await repo.watchCompartments(orgId).first;
      expect(rest.map((c) => c.label), ['B1']);
    });

    test('customers: save returns id, watch sorts by nameLower, delete',
        () async {
      await repo.saveCustomer(
        const ParcelCustomer(
          orgId: orgId,
          siteId: siteId,
          firstName: 'Max',
          lastName: 'Müller',
        ),
      );
      final idAbel = await repo.saveCustomer(
        const ParcelCustomer(
          orgId: orgId,
          siteId: siteId,
          firstName: 'Anna',
          lastName: 'Abel',
        ),
      );

      final customers = await repo.watchCustomers(orgId).first;
      expect(customers.map((c) => c.lastName), ['Abel', 'Müller']);

      await repo.deleteCustomer(orgId: orgId, id: idAbel);
      expect(
        (await repo.watchCustomers(orgId).first).map((c) => c.lastName),
        ['Müller'],
      );
    });
  });

  group('DatabaseService parcel local round-trip', () {
    const scope = LocalStorageScope(orgId: orgId, userId: 'owner-1');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
    });

    test('parcel shipments round-trip through local storage', () async {
      final shipments = [
        ParcelShipment(
          id: 'p-1',
          orgId: orgId,
          siteId: siteId,
          trackingCode: 'H123',
          recipientFirstName: 'Max',
          recipientLastName: 'Müller',
          senderName: 'Amazon',
          compartmentId: 'fach-a2',
          compartmentLabel: 'A2',
          arrivedAt: DateTime(2026, 7, 13, 10, 30),
        ),
      ];
      await DatabaseService.saveLocalParcelShipments(shipments, scope: scope);

      final loaded =
          await DatabaseService.loadLocalParcelShipments(scope: scope);
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'p-1');
      expect(loaded.single.recipientLastName, 'Müller');
      expect(loaded.single.senderName, 'Amazon');
      expect(loaded.single.compartmentId, 'fach-a2');
      expect(loaded.single.arrivedAt, DateTime(2026, 7, 13, 10, 30));
    });

    test('compartments and customers round-trip through local storage',
        () async {
      await DatabaseService.saveLocalShelfCompartments(
        const [
          ShelfCompartment(
            id: 'fach-a2',
            orgId: orgId,
            siteId: siteId,
            label: 'A2',
            barcode: 'BC-A2',
          ),
        ],
        scope: scope,
      );
      await DatabaseService.saveLocalParcelCustomers(
        const [
          ParcelCustomer(
            id: 'cust-9',
            orgId: orgId,
            siteId: siteId,
            firstName: 'Max',
            lastName: 'Müller',
          ),
        ],
        scope: scope,
      );

      final fach =
          await DatabaseService.loadLocalShelfCompartments(scope: scope);
      expect(fach.single.label, 'A2');
      expect(fach.single.barcode, 'BC-A2');
      expect(fach.single.active, isTrue);

      final customers =
          await DatabaseService.loadLocalParcelCustomers(scope: scope);
      expect(customers.single.displayName, 'Max Müller');
      expect(customers.single.nameLower, 'müller max');
    });
  });
}
