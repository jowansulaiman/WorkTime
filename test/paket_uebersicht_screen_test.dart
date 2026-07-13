import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/parcel_shipment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/screens/paket_uebersicht_screen.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Überfällig-Board: Rücklauf-Sammelaktion markiert alle zurück',
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
    final now = DateTime.now();
    // 2 überfällige (>6 Tage) + 1 frisches Paket.
    await p.saveParcel(_parcel('Max', 'Müller', now.subtract(const Duration(days: 10))));
    await p.saveParcel(_parcel('Anna', 'Abel', now.subtract(const Duration(days: 9))));
    await p.saveParcel(_parcel('Neu', 'Kunde', now.subtract(const Duration(days: 1))));

    await tester.pumpWidget(
      ChangeNotifierProvider<ParcelProvider>.value(
        value: p,
        child: const MaterialApp(home: PaketUebersichtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Max Müller'), findsOneWidget);
    expect(find.text('Anna Abel'), findsOneWidget);
    expect(find.text('Neu Kunde'), findsNothing); // nicht überfällig

    await tester.tap(find.text('Alle 2 als Rücklauf markieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markieren'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Keine überfälligen'), findsOneWidget);
    expect(p.openParcels.map((e) => e.recipientLastName), ['Kunde']);
    expect(
      p.parcels.where((e) => e.status == ShipmentStatus.zurueck).length,
      2,
    );
  });
}

ParcelShipment _parcel(String first, String last, DateTime arrivedAt) =>
    ParcelShipment(
      orgId: 'org-1',
      siteId: 'site-tb',
      recipientFirstName: first,
      recipientLastName: last,
      arrivedAt: arrivedAt,
    );
