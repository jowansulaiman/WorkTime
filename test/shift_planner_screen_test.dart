import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/auth_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/screens/shift_planner_screen.dart';
import 'package:worktime_app/services/auth_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  testWidgets(
    'admin planner shows pending and approved absences for all employees',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-pending',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'pending',
          ),
          const _SeededAbsence(
            id: 'absence-approved',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-rejected',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'rejected',
          ),
        ],
      );

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Urlaub · Offen'), findsOneWidget);
      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.textContaining('Abgelehnt'), findsNothing);
    },
  );

  testWidgets(
    'admin planner filters absences by selected employee and can reset to all',
    (tester) async {
      final harness = await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-anna',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-ben',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'vacation',
            status: 'approved',
          ),
        ],
      );

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);

      harness.scheduleProvider.setSelectedUserId('employee-anna');
      await _settlePlanner(tester);

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsNothing);

      harness.scheduleProvider.setSelectedUserId(null);
      await _settlePlanner(tester);

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
    },
  );

  testWidgets(
    'admin planner filters calendar absences to vacation entries',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: [
          const _SeededAbsence(
            id: 'absence-vacation',
            userId: 'employee-anna',
            employeeName: 'Anna',
            type: 'vacation',
            status: 'approved',
          ),
          const _SeededAbsence(
            id: 'absence-sickness',
            userId: 'employee-ben',
            employeeName: 'Ben',
            type: 'sickness',
            status: 'approved',
          ),
        ],
      );

      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.text('Krank · Genehmigt'), findsOneWidget);

      await _openFilterMenu(tester, 'Abwesenheiten');
      await tester.tap(find.text('Urlaub anzeigen').last);
      await _settlePlanner(tester);

      expect(find.text('Urlaub · Genehmigt'), findsOneWidget);
      expect(find.text('Krank · Genehmigt'), findsNothing);
    },
  );

  testWidgets(
    'mobile month view exposes employee and location menu',
    (tester) async {
      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-anna',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
        ],
        viewMode: ScheduleViewMode.month,
        physicalSize: const Size(390, 844),
      );

      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.text('Standort'), findsOneWidget);
      expect(find.text('Mitarbeiter'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await _settlePlanner(tester);

      expect(find.text('Kalender-Menue'), findsOneWidget);
      expect(
        find.text(
            'Mitarbeiter und Standorte fuer die Monatsansicht auswaehlen.'),
        findsOneWidget,
      );
      expect(find.text('Anna'), findsWidgets);
      expect(find.text('MITARBEITER'), findsOneWidget);
      expect(find.text('STANDORTE'), findsOneWidget);
    },
  );

  testWidgets(
    'admin planner exports only completed shifts when status filter is completed',
    (tester) async {
      late ShiftPlanExportFormat capturedFormat;
      List<Shift> exportedShifts = const [];

      final harness = await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-completed',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Erledigte Schicht',
            siteName: 'Berlin HQ',
            status: ShiftStatus.completed,
          ),
          _SeededShift(
            id: 'shift-planned',
            userId: 'employee-ben',
            employeeName: 'Ben',
            title: 'Geplante Schicht',
            siteName: 'Hamburg',
            status: ShiftStatus.planned,
          ),
        ],
        onShiftPlanExport: (format, shifts) async {
          capturedFormat = format;
          exportedShifts = shifts;
        },
      );

      harness.scheduleProvider.setStatusFilter(ShiftStatus.completed);
      await _settlePlanner(tester);

      await tester.tap(find.text('AKTIONEN'));
      await _settlePlanner(tester);
      await tester.tap(find.text('Als PDF exportieren').last);
      await _settlePlanner(tester);

      expect(capturedFormat, ShiftPlanExportFormat.pdf);
      expect(exportedShifts, hasLength(1));
      expect(exportedShifts.single.status, ShiftStatus.completed);
      expect(exportedShifts.single.title, 'Erledigte Schicht');
    },
  );

  testWidgets(
    'admin planner exports the currently filtered location selection',
    (tester) async {
      List<Shift> exportedShifts = const [];

      await _pumpAdminPlanner(
        tester,
        absences: const [],
        shifts: const [
          _SeededShift(
            id: 'shift-berlin',
            userId: 'employee-anna',
            employeeName: 'Anna',
            title: 'Fruehschicht',
            siteName: 'Berlin HQ',
          ),
          _SeededShift(
            id: 'shift-hamburg',
            userId: 'employee-ben',
            employeeName: 'Ben',
            title: 'Spaetschicht',
            siteName: 'Hamburg',
          ),
        ],
        onShiftPlanExport: (format, shifts) async {
          exportedShifts = shifts;
        },
      );

      await _openFilterMenu(tester, 'Standort');
      await tester.tap(find.text('Berlin HQ').last);
      await _settlePlanner(tester);

      await tester.tap(find.text('AKTIONEN'));
      await _settlePlanner(tester);
      await tester.tap(find.text('Als PDF exportieren').last);
      await _settlePlanner(tester);

      expect(exportedShifts, hasLength(1));
      expect(exportedShifts.single.effectiveSiteLabel, 'Berlin HQ');
      expect(exportedShifts.single.title, 'Fruehschicht');
    },
  );
}

Future<_PlannerHarness> _pumpAdminPlanner(
  WidgetTester tester, {
  required List<_SeededAbsence> absences,
  List<_SeededShift> shifts = const [],
  ScheduleViewMode viewMode = ScheduleViewMode.day,
  Size physicalSize = const Size(1600, 1200),
  ShiftPlanExportCallback? onShiftPlanExport,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  const admin = AppUserProfile(
    uid: 'admin-1',
    orgId: 'org-1',
    email: 'admin@example.com',
    role: UserRole.admin,
    isActive: true,
    settings: UserSettings(name: 'Admin'),
  );
  const anna = AppUserProfile(
    uid: 'employee-anna',
    orgId: 'org-1',
    email: 'anna@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Anna'),
  );
  const ben = AppUserProfile(
    uid: 'employee-ben',
    orgId: 'org-1',
    email: 'ben@example.com',
    role: UserRole.employee,
    isActive: true,
    settings: UserSettings(name: 'Ben'),
  );

  final firestore = FakeFirebaseFirestore();
  final firestoreService = FirestoreService(firestore: firestore);

  Future<void> seedUser(AppUserProfile profile) {
    return firestore
        .collection('users')
        .doc(profile.uid)
        .set(profile.toFirestoreMap());
  }

  await seedUser(admin);
  await seedUser(anna);
  await seedUser(ben);

  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day, 12);
  final absenceCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('absenceRequests');
  final shiftCollection = firestore
      .collection('organizations')
      .doc(admin.orgId)
      .collection('shifts');

  for (final absence in absences) {
    await absenceCollection.doc(absence.id).set({
      'orgId': admin.orgId,
      'userId': absence.userId,
      'employeeName': absence.employeeName,
      'startDate': Timestamp.fromDate(day),
      'endDate': Timestamp.fromDate(day),
      'type': absence.type,
      'status': absence.status,
      'createdAt': Timestamp.fromDate(day),
      'updatedAt': Timestamp.fromDate(day),
    });
  }

  for (final shift in shifts) {
    await shiftCollection.doc(shift.id).set({
      'orgId': admin.orgId,
      'userId': shift.userId,
      'employeeName': shift.employeeName,
      'title': shift.title,
      'startTime': Timestamp.fromDate(day),
      'endTime': Timestamp.fromDate(day.add(const Duration(hours: 8))),
      'breakMinutes': 30.0,
      'siteId': 'site-${shift.id}',
      'siteName': shift.siteName,
      'location': shift.siteName,
      'requiredQualificationIds': const <String>[],
      'status': shift.status.value,
      'createdAt': Timestamp.fromDate(day),
      'updatedAt': Timestamp.fromDate(day),
    });
  }

  final authProvider = _TestAuthProvider(
    firestoreService: firestoreService,
    profile: admin,
  );
  final scheduleProvider = ScheduleProvider(
    firestoreService: firestoreService,
  );
  final teamProvider = TeamProvider(
    firestoreService: firestoreService,
  );

  await teamProvider.updateSession(admin);
  await scheduleProvider.updateSession(admin);
  scheduleProvider.setViewMode(viewMode);
  scheduleProvider.setVisibleDate(day);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ScheduleProvider>.value(
          value: scheduleProvider,
        ),
        ChangeNotifierProvider<TeamProvider>.value(value: teamProvider),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.78),
            ),
            child: Scaffold(
              body: ShiftPlannerScreen(
                onShiftPlanExport: onShiftPlanExport,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await _settlePlanner(tester);
  if (shifts.isNotEmpty) {
    for (var i = 0; i < 6 && scheduleProvider.shifts.isEmpty; i++) {
      await _settlePlanner(tester);
    }
  }
  return _PlannerHarness(scheduleProvider: scheduleProvider);
}

Future<void> _settlePlanner(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _openFilterMenu(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

class _SeededAbsence {
  const _SeededAbsence({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.type,
    required this.status,
  });

  final String id;
  final String userId;
  final String employeeName;
  final String type;
  final String status;
}

class _SeededShift {
  const _SeededShift({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.title,
    required this.siteName,
    this.status = ShiftStatus.planned,
  });

  final String id;
  final String userId;
  final String employeeName;
  final String title;
  final String siteName;
  final ShiftStatus status;
}

class _PlannerHarness {
  const _PlannerHarness({
    required this.scheduleProvider,
  });

  final ScheduleProvider scheduleProvider;
}

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider({
    required super.firestoreService,
    AppUserProfile? profile,
  })  : _profile = profile,
        super(authService: AuthService());

  AppUserProfile? _profile;

  @override
  AppUserProfile? get profile => _profile;

  void setProfile(AppUserProfile? value) {
    _profile = value;
    notifyListeners();
  }
}
