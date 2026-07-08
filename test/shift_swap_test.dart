import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/compliance_rule_set.dart';
import 'package:worktime_app/models/employee_site_assignment.dart';
import 'package:worktime_app/models/employment_contract.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/shift_swap_request.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/swap_credit.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

/// Test-Komfort: Einzelschicht speichern (wie in schedule_provider_test.dart).
extension _SaveSingleShift on ScheduleProvider {
  Future<void> saveShift(Shift shift) => saveShifts([shift]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShiftSwapRequest Serialisierung', () {
    test('round-trippt beide Formate (snake/ISO + camel/Timestamp)', () {
      final request = ShiftSwapRequest(
        id: 'req-1',
        orgId: 'org-1',
        requesterUid: 'a',
        requesterName: 'Anna',
        requesterShiftId: 'shift-a',
        targetUid: 'b',
        targetName: 'Bert',
        targetShiftId: 'shift-b',
        kind: SwapKind.exchange,
        status: SwapStatus.acceptedByColleague,
        reviewedByUid: 'admin',
        overriddenCompliance: true,
        note: 'Arzttermin',
        requesterShiftStart: DateTime(2026, 6, 22, 8),
        targetShiftStart: DateTime(2026, 6, 23, 9),
        requesterShiftLabel: 'Mo 22.06., 08:00–16:00',
        targetShiftLabel: 'Di 23.06., 09:00–17:00',
      );

      final fromLocal = ShiftSwapRequest.fromMap(request.toMap());
      expect(fromLocal.id, 'req-1');
      expect(fromLocal.requesterUid, 'a');
      expect(fromLocal.targetShiftId, 'shift-b');
      expect(fromLocal.kind, SwapKind.exchange);
      expect(fromLocal.status, SwapStatus.acceptedByColleague);
      expect(fromLocal.overriddenCompliance, true);
      expect(fromLocal.note, 'Arzttermin');
      expect(fromLocal.targetShiftStart, DateTime(2026, 6, 23, 9));

      final fromCloud =
          ShiftSwapRequest.fromFirestore('req-1', request.toFirestoreMap());
      expect(fromCloud.targetUid, 'b');
      expect(fromCloud.status, SwapStatus.acceptedByColleague);
      expect(fromCloud.kind, SwapKind.exchange);
      expect(fromCloud.requesterShiftStart, DateTime(2026, 6, 22, 8));
    });

    test('giveAway ohne Zielschicht round-trippt mit null', () {
      final request = ShiftSwapRequest(
        orgId: 'org-1',
        requesterUid: 'a',
        requesterName: 'Anna',
        requesterShiftId: 'shift-a',
        targetUid: 'b',
        targetName: 'Bert',
        kind: SwapKind.giveAway,
        requesterShiftStart: DateTime(2026, 6, 22, 8),
      );
      final fromLocal = ShiftSwapRequest.fromMap(request.toMap());
      expect(fromLocal.kind, SwapKind.giveAway);
      expect(fromLocal.targetShiftId, isNull);
      expect(fromLocal.targetShiftStart, isNull);
      expect(fromLocal.isGiveAway, true);
    });

    test('SwapStatus.fromValue fällt unbekannt auf pending', () {
      expect(SwapStatusX.fromValue('quatsch'), SwapStatus.pending);
      expect(SwapStatusX.fromValue('confirmed'), SwapStatus.confirmed);
      expect(SwapKindX.fromValue(null), SwapKind.exchange);
    });
  });

  group('SwapCredit Serialisierung', () {
    test('round-trippt beide Formate', () {
      final credit = SwapCredit(
        id: 'credit-1',
        orgId: 'org-1',
        creditorUid: 'b',
        creditorName: 'Bert',
        debtorUid: 'a',
        debtorName: 'Anna',
        originSwapRequestId: 'req-1',
        originShiftStart: DateTime(2026, 6, 22, 8),
        originShiftLabel: 'Mo 22.06.',
        status: SwapCreditStatus.open,
      );
      final fromLocal = SwapCredit.fromMap(credit.toMap());
      expect(fromLocal.creditorUid, 'b');
      expect(fromLocal.debtorUid, 'a');
      expect(fromLocal.status, SwapCreditStatus.open);

      final fromCloud =
          SwapCredit.fromFirestore('credit-1', credit.toFirestoreMap());
      expect(fromCloud.originSwapRequestId, 'req-1');
      expect(fromCloud.isOpen, true);
    });
  });

  group('ScheduleProvider Schichttausch (lokal, org-skopiert)', () {
    late FirestoreService firestoreService;
    late AppUserProfile admin;
    late AppUserProfile empA;
    late AppUserProfile empB;
    late SiteDefinition site;
    late ComplianceRuleSet ruleSet;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(firestore: FakeFirebaseFirestore());
      admin = const AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Chef'),
      );
      empA = const AppUserProfile(
        uid: 'emp-a',
        orgId: 'org-1',
        email: 'anna@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Anna'),
      );
      empB = const AppUserProfile(
        uid: 'emp-b',
        orgId: 'org-1',
        email: 'bert@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Bert'),
      );
      site = const SiteDefinition(id: 'site-1', orgId: 'org-1', name: 'Kiel');
      ruleSet = ComplianceRuleSet.defaultRetail('org-1');
    });

    EmploymentContract contractFor(String userId) => EmploymentContract(
          id: 'contract-$userId',
          orgId: 'org-1',
          userId: userId,
          validFrom: DateTime(2020, 1, 1),
          dailyHours: 8,
          weeklyHours: 40,
        );

    EmployeeSiteAssignment assignmentFor(String userId) =>
        EmployeeSiteAssignment(
          id: 'assignment-$userId',
          orgId: 'org-1',
          userId: userId,
          siteId: site.id!,
          siteName: site.name,
          isPrimary: true,
        );

    void seedReferenceData(ScheduleProvider provider) {
      provider.updateReferenceData(
        members: [admin, empA, empB],
        contracts: [
          contractFor('admin-1'),
          contractFor('emp-a'),
          contractFor('emp-b'),
        ],
        siteAssignments: [
          assignmentFor('admin-1'),
          assignmentFor('emp-a'),
          assignmentFor('emp-b'),
        ],
        sites: [site],
        ruleSets: [ruleSet],
        travelTimeRules: const [],
      );
    }

    DateTime mondayThisWeek(int hour) {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return monday.add(Duration(hours: hour));
    }

    DateTime tuesdayThisWeek(int hour) =>
        mondayThisWeek(hour).add(const Duration(days: 1));

    Shift shiftFor(
      String userId,
      String name,
      DateTime start, {
      Duration duration = const Duration(hours: 8),
    }) =>
        Shift(
          orgId: 'org-1',
          userId: userId,
          employeeName: name,
          title: 'Dienst',
          startTime: start,
          endTime: start.add(duration),
          breakMinutes: 30,
          siteId: site.id,
          siteName: site.name,
          location: site.name,
        );

    Future<ScheduleProvider> bootProvider() async {
      final provider = ScheduleProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      addTearDown(provider.dispose);
      await provider.updateSession(admin);
      seedReferenceData(provider);
      await Future<void>.delayed(Duration.zero);
      return provider;
    }

    test('Tausch: Annahme + Chef-Bestätigung tauscht beide userIds', () async {
      final provider = await bootProvider();

      // Admin legt je eine Schicht für A (Mo) und B (Di) an.
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      await provider.saveShift(shiftFor('emp-b', 'Bert', tuesdayThisWeek(8)));
      final shiftA =
          provider.shifts.firstWhere((shift) => shift.userId == 'emp-a');
      final shiftB =
          provider.shifts.firstWhere((shift) => shift.userId == 'emp-b');

      // A stellt die Tauschanfrage (eigene Schicht ↔ B's Schicht).
      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          targetShiftId: shiftB.id,
          kind: SwapKind.exchange,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;
      expect(provider.swapRequests.single.status, SwapStatus.pending);

      // B nimmt an.
      await provider.updateSession(empB);
      await Future<void>.delayed(Duration.zero);
      await provider.respondToShiftSwapRequest(
        requestId: requestId,
        accept: true,
      );
      expect(
        provider.swapRequests.single.status,
        SwapStatus.acceptedByColleague,
      );

      // Chef bestätigt -> beide Schichten getauscht.
      await provider.updateSession(admin);
      provider.setSelectedUserId(null); // Manager sieht wieder alle Schichten
      await Future<void>.delayed(Duration.zero);
      await provider.confirmShiftSwapRequest(requestId: requestId);
      await Future<void>.delayed(Duration.zero);

      expect(provider.swapRequests.single.status, SwapStatus.confirmed);
      final reassignedA =
          provider.shifts.firstWhere((shift) => shift.id == shiftA.id);
      final reassignedB =
          provider.shifts.firstWhere((shift) => shift.id == shiftB.id);
      expect(reassignedA.userId, 'emp-b');
      expect(reassignedA.employeeName, 'Bert');
      expect(reassignedB.userId, 'emp-a');
      expect(reassignedB.employeeName, 'Anna');
    });

    test('Übernahme (giveAway): nur eine Schicht wandert + Gutschrift entsteht',
        () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      final shiftA = provider.shifts.single;

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;

      await provider.updateSession(empB);
      await Future<void>.delayed(Duration.zero);
      await provider.respondToShiftSwapRequest(
        requestId: requestId,
        accept: true,
      );

      await provider.updateSession(admin);
      provider.setSelectedUserId(null); // Manager sieht wieder alle Schichten
      await Future<void>.delayed(Duration.zero);
      await provider.confirmShiftSwapRequest(requestId: requestId);
      await Future<void>.delayed(Duration.zero);

      final reassigned =
          provider.shifts.firstWhere((shift) => shift.id == shiftA.id);
      expect(reassigned.userId, 'emp-b');
      expect(provider.swapRequests.single.status, SwapStatus.confirmed);

      // Gutschrift: B (übernimmt) ist Gläubiger, A (gibt ab) ist Schuldner.
      final credit = provider.swapCredits.single;
      expect(credit.creditorUid, 'emp-b');
      expect(credit.debtorUid, 'emp-a');
      expect(credit.status, SwapCreditStatus.open);
    });

    test('Ablehnung durch Kollegen lässt Schichten unverändert', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      final shiftA = provider.shifts.single;

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;

      await provider.updateSession(empB);
      await Future<void>.delayed(Duration.zero);
      await provider.respondToShiftSwapRequest(
        requestId: requestId,
        accept: false,
      );
      expect(
        provider.swapRequests.single.status,
        SwapStatus.declinedByColleague,
      );

      await provider.updateSession(admin);
      provider.setSelectedUserId(null); // Manager sieht wieder alle Schichten
      await Future<void>.delayed(Duration.zero);
      final unchanged = provider.shifts.single;
      expect(unchanged.userId, 'emp-a');
      expect(provider.swapCredits, isEmpty);
    });

    test('Antragsteller kann offene Anfrage zurückziehen', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      final shiftA = provider.shifts.single;

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;
      await provider.cancelShiftSwapRequest(requestId);
      expect(provider.swapRequests.single.status, SwapStatus.cancelled);
    });

    test('Kollege kann fremde Anfrage nicht annehmen', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      final shiftA = provider.shifts.single;

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;

      // Falscher Nutzer (Antragsteller selbst) darf nicht als Ziel annehmen.
      expect(
        () => provider.respondToShiftSwapRequest(
          requestId: requestId,
          accept: true,
        ),
        throwsStateError,
      );
    });

    test('Compliance-Konflikt: Bestätigung blockt, Override schreibt direkt',
        () async {
      final provider = await bootProvider();
      // B arbeitet Mo 08–16, A's übergebene Schicht Mo 12–20 überschneidet sich
      // beim Empfänger B -> Konflikt. A's Schicht trägt eine (für ANNA
      // gerechnete) Überstunden-Projektion — skipCompliance persistiert sie
      // unverändert (keine Neu-Projektion beim Seeden).
      await provider.saveShift(shiftFor('emp-b', 'Bert', mondayThisWeek(8)));
      await provider.saveShifts(
        [shiftFor('emp-a', 'Anna', mondayThisWeek(12)).copyWith(overtimeMinutes: 90)],
        skipCompliance: true,
      );
      final shiftA =
          provider.shifts.firstWhere((shift) => shift.userId == 'emp-a');
      expect(shiftA.overtimeMinutes, 90);

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;

      await provider.updateSession(empB);
      await Future<void>.delayed(Duration.zero);
      await provider.respondToShiftSwapRequest(
        requestId: requestId,
        accept: true,
      );

      await provider.updateSession(admin);
      provider.setSelectedUserId(null); // Manager sieht wieder alle Schichten
      await Future<void>.delayed(Duration.zero);

      // Vorschau meldet den Konflikt.
      final issues = await provider.previewSwapCompliance(requestId);
      expect(issues, isNotEmpty);

      // Ohne Override blockt die Bestätigung.
      await expectLater(
        provider.confirmShiftSwapRequest(requestId: requestId),
        throwsA(isA<ShiftConflictException>()),
      );
      expect(
        provider.swapRequests.single.status,
        SwapStatus.acceptedByColleague,
      );

      // Mit Override wird der Tausch dennoch vollzogen.
      await provider.confirmShiftSwapRequest(
        requestId: requestId,
        overrideCompliance: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.swapRequests.single.status, SwapStatus.confirmed);
      final reassigned =
          provider.shifts.firstWhere((shift) => shift.id == shiftA.id);
      expect(reassigned.userId, 'emp-b');
      // Die für Anna gerechneten 90 Überstunden-Minuten dürfen NICHT auf Bert
      // wandern: der Override-Pfad (skipCompliance) projiziert nicht neu —
      // _buildSwappedShifts neutralisiert die Umbuchung daher auf 0.
      expect(reassigned.overtimeMinutes, 0);
    });

    test('Gutschrift einlösen setzt Status auf settled', () async {
      final provider = await bootProvider();
      await provider.saveShift(shiftFor('emp-a', 'Anna', mondayThisWeek(8)));
      final shiftA = provider.shifts.single;

      await provider.updateSession(empA);
      await Future<void>.delayed(Duration.zero);
      await provider.submitShiftSwapRequest(
        ShiftSwapRequest(
          orgId: 'org-1',
          requesterUid: 'emp-a',
          requesterName: 'Anna',
          requesterShiftId: shiftA.id!,
          targetUid: 'emp-b',
          targetName: 'Bert',
          kind: SwapKind.giveAway,
          requesterShiftStart: shiftA.startTime,
        ),
      );
      final requestId = provider.swapRequests.single.id!;

      await provider.updateSession(empB);
      await Future<void>.delayed(Duration.zero);
      await provider.respondToShiftSwapRequest(
        requestId: requestId,
        accept: true,
      );

      await provider.updateSession(admin);
      provider.setSelectedUserId(null); // Manager sieht wieder alle Schichten
      await Future<void>.delayed(Duration.zero);
      await provider.confirmShiftSwapRequest(requestId: requestId);
      await Future<void>.delayed(Duration.zero);

      final creditId = provider.swapCredits.single.id!;
      await provider.settleSwapCredit(creditId);
      expect(provider.swapCredits.single.status, SwapCreditStatus.settled);
    });
  });
}
