import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/parcel_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/routing/route_permissions.dart';
import 'package:worktime_app/routing/shell_tab.dart';
import 'package:worktime_app/screens/paketshop_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';
import 'package:worktime_app/theme/app_theme.dart';

void main() {
  const activeUser = AppUserProfile(
    uid: 'owner-1',
    orgId: 'org-1',
    email: 'owner@laden.test',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Inhaber'),
  );
  const inactiveUser = AppUserProfile(
    uid: 'x-1',
    orgId: 'org-1',
    email: 'x@laden.test',
    role: UserRole.employee,
    isActive: false,
    settings: UserSettings(name: 'Gesperrt'),
  );

  group('RoutePermissions /paketshop', () {
    test('aktive Nutzer dürfen, nicht angemeldete/inaktive nicht', () {
      expect(RoutePermissions.isLocationAllowed(AppRoutes.paketshop, activeUser),
          isTrue);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.paketshop, null),
          isFalse);
      expect(
        RoutePermissions.isLocationAllowed(AppRoutes.paketshop, inactiveUser),
        isFalse,
      );
    });
  });

  group('PaketshopHubScreen', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('rendert Hub mit Hinweisbanner und Kennzahlen', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final firestoreService =
          FirestoreService(firestore: FakeFirebaseFirestore());
      final parcel = ParcelProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      final team = TeamProvider(firestoreService: firestoreService);
      await parcel.updateSession(activeUser, localStorageOnly: true);
      await team.updateSession(activeUser);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ParcelProvider>.value(value: parcel),
            ChangeNotifierProvider<TeamProvider>.value(value: team),
          ],
          child: MaterialApp(
            theme: AppTheme.resolveLight(useV2: true),
            home: const PaketshopHubScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Paketshop'), findsOneWidget);
      expect(
        find.textContaining('offizielle Ablauf des Paketdiensts'),
        findsOneWidget,
      );
      expect(find.text('Keine offenen Pakete.'), findsOneWidget);

      addTearDown(() {
        parcel.dispose();
        team.dispose();
      });
    });
  });
}
