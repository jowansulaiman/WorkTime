import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/shelf_compartment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/screens/fach_verwaltung_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  Future<ParcelProvider> provider() async {
    final p = ParcelProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    await p.updateSession(user, localStorageOnly: true);
    return p;
  }

  Widget host(ParcelProvider p) => ChangeNotifierProvider<ParcelProvider>.value(
        value: p,
        child: const MaterialApp(
          home: FachVerwaltungScreen(siteId: siteId, siteName: 'Tabak Börse'),
        ),
      );

  testWidgets('Fach anlegen (manueller Barcode) erscheint in der Liste',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final p = await provider();
    await tester.pumpWidget(host(p));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fach')); // FAB
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'A2');
    await tester.enterText(find.byType(TextField).at(1), 'BC-A2');
    await tester.tap(find.text('Anlegen'));
    await tester.pumpAndSettle();

    expect(p.compartments, hasLength(1));
    expect(p.compartments.single.label, 'A2');
    expect(find.text('Fach A2'), findsOneWidget);
  });

  testWidgets('belegtes Fach ist nicht löschbar (Snackbar), leeres schon',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final p = await provider();
    final fachId = await p.saveCompartment(
      const ShelfCompartment(
        orgId: 'org-1',
        siteId: siteId,
        label: 'A2',
        barcode: 'BC-A2',
      ),
    );
    await p.saveParcel(
      ParcelShipment(
        orgId: 'org-1',
        siteId: siteId,
        recipientFirstName: 'Max',
        recipientLastName: 'Müller',
        compartmentId: fachId,
        compartmentLabel: 'A2',
        arrivedAt: DateTime(2026, 7, 13),
      ),
    );

    await tester.pumpWidget(host(p));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('belegt'), findsOneWidget); // Snackbar
    expect(p.compartments, hasLength(1)); // nicht gelöscht

    // Nach Ausgabe leer → löschbar.
    await p.handOutParcel(p.parcels.single);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(p.compartments, isEmpty);
  });
}
