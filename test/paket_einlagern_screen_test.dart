import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/shelf_compartment.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/screens/paket_einlagern_screen.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/barcode_scanner.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/services/scan_feedback.dart';

class _FakeBarcodeScanner implements BarcodeScanner {
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  ScannerTarget _target = ScannerTarget.retail;
  void emit(String code) => controller.add(code);

  @override
  Stream<String> get codes => controller.stream;
  @override
  bool get isAvailable => true;
  @override
  bool get supportsTorch => false;
  @override
  bool get supportsZoom => false;
  @override
  bool get supportsPhotoAnalysis => false;
  @override
  ScannerTarget get target => _target;
  @override
  Future<void> setTarget(ScannerTarget target) async => _target = target;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> setZoom(double scale) async {}
  @override
  Future<List<String>> analyzePhoto(String path) async => const [];
  @override
  Widget buildPreview(BuildContext context) => const SizedBox();
  @override
  Future<void> dispose() async {}
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetCachedPrefs();
  });

  testWidgets('Einlagern: Paket scannen → Fach scannen → neu anlegen → speichern',
      (tester) async {
    // Großer Viewport, damit das lange Formular ohne Scrollen sichtbar ist.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fake = _FakeBarcodeScanner();
    addTearDown(() => fake.controller.close());

    final parcel = ParcelProvider(
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      disableAuthentication: true,
    );
    await parcel.updateSession(user, localStorageOnly: true);
    await parcel.saveCompartment(
      const ShelfCompartment(
        orgId: 'org-1',
        siteId: siteId,
        label: 'A2',
        barcode: 'BC-A2',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ParcelProvider>.value(
        value: parcel,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => PaketEinlagernScreen(
                        siteId: siteId,
                        siteName: 'Tabak Börse',
                        scanner: fake,
                        feedback: const NoopScanFeedback(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 1) Paket scannen
    await tester.tap(find.text('Paket scannen'));
    await tester.pumpAndSettle();
    fake.emit('PKG-1');
    await tester.pumpAndSettle();
    expect(find.text('PKG-1'), findsOneWidget);

    // 2) Fach scannen (existiert → wird aufgelöst)
    await tester.tap(find.text('Fach scannen'));
    await tester.pumpAndSettle();
    fake.emit('BC-A2');
    await tester.pumpAndSettle();
    expect(find.text('Fach A2'), findsOneWidget);

    // 3) Empfänger neu anlegen
    await tester.tap(find.text('Neu anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Max');
    await tester.enterText(find.byType(TextField).at(1), 'Müller');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Max Müller'), findsOneWidget);

    // 4) Einlagern (persistenter Button in der bottomNavigationBar)
    await tester.tap(find.text('Einlagern'));
    await tester.pumpAndSettle();

    expect(parcel.openParcels, hasLength(1));
    final p = parcel.openParcels.single;
    expect(p.recipientLastName, 'Müller');
    expect(p.trackingCode, 'PKG-1');
    expect(p.compartmentLabel, 'A2');
    expect(p.parcelCustomerId, isNotNull);
    // Kunde wurde ins Register aufgenommen.
    expect(parcel.customers.map((c) => c.lastName), contains('Müller'));
  });
}
