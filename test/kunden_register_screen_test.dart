import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/screens/kunden_register_screen.dart';
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

  testWidgets('Kunde löschen entfernt Eintrag und entkoppelt offenes Paket',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final p = ParcelProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    await p.updateSession(user, localStorageOnly: true);
    final cust = await p.upsertCustomer(
      firstName: 'Max',
      lastName: 'Müller',
      siteId: siteId,
    );
    await p.upsertCustomer(firstName: 'Anna', lastName: 'Abel', siteId: siteId);
    final pid = await p.saveParcel(
      ParcelShipment(
        orgId: 'org-1',
        siteId: siteId,
        recipientFirstName: 'Max',
        recipientLastName: 'Müller',
        parcelCustomerId: cust.id,
        arrivedAt: DateTime(2026, 7, 13),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ParcelProvider>.value(
        value: p,
        child: const MaterialApp(home: KundenRegisterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Max Müller'), findsOneWidget);
    expect(find.text('Anna Abel'), findsOneWidget);

    // Gezielt Max Müller löschen (Liste ist nach Name sortiert).
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Max Müller'),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(p.customers.map((c) => c.lastName), ['Abel']);
    // Paket bleibt, ist aber entkoppelt.
    final parcel = p.parcels.firstWhere((e) => e.id == pid);
    expect(parcel.parcelCustomerId, isNull);
  });
}
