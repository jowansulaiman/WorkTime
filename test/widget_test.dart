import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/screens/notification_screen.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  testWidgets(
    'absence request sheet submits without using a disposed context',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      final provider = ScheduleProvider(
        firestoreService: FirestoreService(
          firestore: FakeFirebaseFirestore(),
        ),
        disableAuthentication: true,
      );
      await provider.updateSession(
        const AppUserProfile(
          uid: 'employee-1',
          orgId: 'org-1',
          email: 'employee@example.com',
          role: UserRole.employee,
          isActive: true,
          settings: UserSettings(name: 'Mira'),
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ScheduleProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => showAbsenceRequestSheet(
                      context,
                      defaultType: AbsenceType.vacation,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Antrag senden'));
      await tester.pumpAndSettle();

      expect(find.text('Antrag gespeichert'), findsOneWidget);
      expect(provider.absenceRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
