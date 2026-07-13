import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/parcel_customer.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/shelf_compartment.dart';

void main() {
  group('ParcelShipment', () {
    ParcelShipment sample() => ParcelShipment(
          id: 'p-1',
          orgId: 'org-1',
          siteId: 'site-tb',
          siteName: 'Tabak Börse',
          trackingCode: 'H0001234567890',
          recipientFirstName: 'Max',
          recipientLastName: 'Müller',
          senderName: 'Amazon',
          parcelCustomerId: 'cust-9',
          compartmentId: 'fach-a2',
          compartmentLabel: 'A2',
          arrivedAt: DateTime(2026, 7, 13, 10, 30),
        );

    test('round-trips through the local map (snake_case)', () {
      final restored = ParcelShipment.fromMap(sample().toMap());

      expect(restored.id, 'p-1');
      expect(restored.orgId, 'org-1');
      expect(restored.siteId, 'site-tb');
      expect(restored.siteName, 'Tabak Börse');
      expect(restored.carrier, 'hermes');
      expect(restored.trackingCode, 'H0001234567890');
      expect(restored.recipientFirstName, 'Max');
      expect(restored.recipientLastName, 'Müller');
      expect(restored.senderName, 'Amazon');
      expect(restored.parcelCustomerId, 'cust-9');
      expect(restored.compartmentId, 'fach-a2');
      expect(restored.compartmentLabel, 'A2');
      expect(restored.status, ShipmentStatus.eingelagert);
      expect(restored.arrivedAt, DateTime(2026, 7, 13, 10, 30));
    });

    test('round-trips through the firestore map (camelCase/Timestamp)', () {
      final restored =
          ParcelShipment.fromFirestore('p-1', sample().toFirestoreMap());

      expect(restored.recipientFirstName, 'Max');
      expect(restored.recipientLastName, 'Müller');
      expect(restored.senderName, 'Amazon');
      expect(restored.parcelCustomerId, 'cust-9');
      expect(restored.compartmentId, 'fach-a2');
      expect(restored.arrivedAt, DateTime(2026, 7, 13, 10, 30));
    });

    test('toFirestoreMap omits id and createdAt (repo-managed)', () {
      final map = sample().toFirestoreMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
    });

    test('recipientNameLower is derived (Nachname Vorname), never raw', () {
      expect(sample().recipientNameLower, 'müller max');
      // Persisted in both maps for orderBy, always recomputed from the names.
      expect(sample().toFirestoreMap()['recipientNameLower'], 'müller max');
      expect(sample().toMap()['recipient_name_lower'], 'müller max');
      // Even if a stale value sneaks into the map, the model recomputes it.
      final map = sample().toMap()..['recipient_name_lower'] = 'STALE';
      expect(ParcelShipment.fromMap(map).recipientNameLower, 'müller max');
    });

    test('ShipmentStatus.fromValue maps values and defaults to eingelagert',
        () {
      expect(ShipmentStatusX.fromValue('handed_out'), ShipmentStatus.abgeholt);
      expect(ShipmentStatusX.fromValue('returned'), ShipmentStatus.zurueck);
      expect(ShipmentStatusX.fromValue('stored'), ShipmentStatus.eingelagert);
      expect(ShipmentStatusX.fromValue('quatsch'), ShipmentStatus.eingelagert);
      expect(ShipmentStatusX.fromValue(null), ShipmentStatus.eingelagert);
      expect(ShipmentStatus.eingelagert.isOpen, isTrue);
      expect(ShipmentStatus.abgeholt.isClosed, isTrue);
      expect(ShipmentStatus.zurueck.isClosed, isTrue);
    });

    test('status value survives the firestore round-trip', () {
      final abgeholt = sample().copyWith(
        status: ShipmentStatus.abgeholt,
        handedOutAt: DateTime(2026, 7, 14, 9),
      );
      final restored =
          ParcelShipment.fromFirestore('p-1', abgeholt.toFirestoreMap());
      expect(restored.status, ShipmentStatus.abgeholt);
      expect(restored.handedOutAt, DateTime(2026, 7, 14, 9));
    });

    test('copyWith clear flags empty nullable fields', () {
      final s = sample();
      expect(s.copyWith(clearSenderName: true).senderName, isNull);
      expect(s.copyWith(clearTrackingCode: true).trackingCode, isNull);
      expect(
        s.copyWith(clearParcelCustomerId: true).parcelCustomerId,
        isNull,
      );
      expect(s.copyWith(clearCompartmentId: true).compartmentId, isNull);
      expect(s.copyWith(clearCompartmentLabel: true).compartmentLabel, isNull);
      // Undo: clearing handedOutAt + back to eingelagert keeps the compartment.
      final handedOut = s.copyWith(
        status: ShipmentStatus.abgeholt,
        handedOutAt: DateTime(2026, 7, 14),
      );
      final undone = handedOut.copyWith(
        status: ShipmentStatus.eingelagert,
        clearHandedOutAt: true,
      );
      expect(undone.handedOutAt, isNull);
      expect(undone.status, ShipmentStatus.eingelagert);
      expect(undone.compartmentId, 'fach-a2');
      // Without a clear flag the value is preserved.
      expect(s.copyWith().senderName, 'Amazon');
    });

    test('isOverdue only for open parcels at/after the threshold', () {
      final s = sample(); // arrivedAt 2026-07-13 10:30
      expect(s.isOverdue(6, DateTime(2026, 7, 18)), isFalse); // day 5
      expect(s.isOverdue(6, DateTime(2026, 7, 19, 10, 30)), isTrue); // day 6
      expect(s.isOverdue(6, DateTime(2026, 7, 25)), isTrue);
      // A handed-out parcel is never overdue.
      expect(
        s.copyWith(status: ShipmentStatus.abgeholt).isOverdue(
              6,
              DateTime(2026, 8, 1),
            ),
        isFalse,
      );
    });
  });

  group('ShelfCompartment', () {
    const sample = ShelfCompartment(
      id: 'fach-a2',
      orgId: 'org-1',
      siteId: 'site-tb',
      siteName: 'Tabak Börse',
      label: 'A2',
      barcode: 'FACH-A2-XYZ',
    );

    test('round-trips through both serializations', () {
      final local = ShelfCompartment.fromMap(sample.toMap());
      expect(local.label, 'A2');
      expect(local.barcode, 'FACH-A2-XYZ');
      expect(local.active, isTrue);
      expect(local.siteName, 'Tabak Börse');

      final cloud =
          ShelfCompartment.fromFirestore('fach-a2', sample.toFirestoreMap());
      expect(cloud.label, 'A2');
      expect(cloud.barcode, 'FACH-A2-XYZ');
      expect(cloud.active, isTrue);
    });

    test('labelLower is derived', () {
      const c = ShelfCompartment(
        orgId: 'o',
        siteId: 's',
        label: '  B-12  ',
        barcode: 'x',
      );
      expect(c.labelLower, 'b-12');
      expect(c.toFirestoreMap()['labelLower'], 'b-12');
    });

    test('active survives round-trip and clearSiteName works', () {
      final inactive = sample.copyWith(active: false);
      expect(
        ShelfCompartment.fromMap(inactive.toMap()).active,
        isFalse,
      );
      expect(sample.copyWith(clearSiteName: true).siteName, isNull);
      expect(sample.copyWith().siteName, 'Tabak Börse');
    });

    test('toFirestoreMap omits id and createdAt', () {
      final map = sample.toFirestoreMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
    });
  });

  group('ParcelCustomer', () {
    ParcelCustomer sample() => ParcelCustomer(
          id: 'cust-9',
          orgId: 'org-1',
          siteId: 'site-tb',
          firstName: 'Max',
          lastName: 'Müller',
          firstSeenAt: DateTime(2026, 7, 1, 8),
          lastSeenAt: DateTime(2026, 7, 13, 10, 30),
        );

    test('round-trips through both serializations', () {
      final local = ParcelCustomer.fromMap(sample().toMap());
      expect(local.id, 'cust-9');
      expect(local.firstName, 'Max');
      expect(local.lastName, 'Müller');
      expect(local.firstSeenAt, DateTime(2026, 7, 1, 8));
      expect(local.lastSeenAt, DateTime(2026, 7, 13, 10, 30));

      final cloud =
          ParcelCustomer.fromFirestore('cust-9', sample().toFirestoreMap());
      expect(cloud.firstName, 'Max');
      expect(cloud.lastName, 'Müller');
      expect(cloud.lastSeenAt, DateTime(2026, 7, 13, 10, 30));
    });

    test('nameLower matches the shipment key (shared helper)', () {
      expect(sample().nameLower, 'müller max');
      expect(sample().nameLower, parcelNameLower('Max', 'Müller'));
      expect(sample().displayName, 'Max Müller');
    });

    test('clearLastSeenAt empties the timestamp via copyWith', () {
      expect(sample().copyWith(clearLastSeenAt: true).lastSeenAt, isNull);
      expect(sample().copyWith().lastSeenAt, DateTime(2026, 7, 13, 10, 30));
    });

    test('toFirestoreMap omits id but keeps derived nameLower', () {
      final map = sample().toFirestoreMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['nameLower'], 'müller max');
    });
  });
}
