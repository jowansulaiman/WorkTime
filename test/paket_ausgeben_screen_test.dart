import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/screens/paket_ausgeben_screen.dart';
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

  Future<ParcelProvider> seededProvider() async {
    final p = ParcelProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    await p.updateSession(user, localStorageOnly: true);
    return p;
  }

  ParcelShipment parcel(String first, String last, {String? fach}) =>
      ParcelShipment(
        orgId: 'org-1',
        siteId: siteId,
        recipientFirstName: first,
        recipientLastName: last,
        compartmentLabel: fach,
        arrivedAt: DateTime(2026, 7, 13, 10),
      );

  Widget host(ParcelProvider p) => ChangeNotifierProvider<ParcelProvider>.value(
        value: p,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PaketAusgebenScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('Namenssuche → Bündel → alle ausgeben', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final p = await seededProvider();
    await p.saveParcel(parcel('Max', 'Müller', fach: 'A2'));
    await p.saveParcel(parcel('Max', 'Müller', fach: 'B1'));
    await p.saveParcel(parcel('Anna', 'Abel', fach: 'C3'));

    await tester.pumpWidget(host(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'müller');
    await tester.pumpAndSettle();
    expect(find.text('Max Müller'), findsOneWidget);

    await tester.tap(find.text('Max Müller'));
    await tester.pumpAndSettle();
    expect(find.text('Alle 2 ausgeben'), findsOneWidget);

    await tester.tap(find.text('Alle 2 ausgeben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle ausgeben')); // Dialog-Bestätigung
    await tester.pumpAndSettle();

    final muellerOpen = p.openParcels
        .where((e) => e.recipientLastName == 'Müller')
        .toList();
    expect(muellerOpen, isEmpty); // beide ausgegeben
    expect(
      p.openParcels.where((e) => e.recipientLastName == 'Abel'),
      hasLength(1),
    ); // anderer Kunde unberührt
  });

  testWidgets('Einzelausgabe + Undo stellt das Paket wieder her',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final p = await seededProvider();
    await p.saveParcel(parcel('Max', 'Müller', fach: 'A2'));

    await tester.pumpWidget(host(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Max Müller'));
    await tester.pumpAndSettle();

    // Einzel-Ausgabe über den OutlinedButton in der Zeile.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ausgegeben'));
    await tester.pumpAndSettle();
    expect(p.openParcels, isEmpty);

    // Undo über die Snackbar.
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(p.openParcels, hasLength(1));
    expect(p.openParcels.single.compartmentLabel, 'A2');
  });
}
