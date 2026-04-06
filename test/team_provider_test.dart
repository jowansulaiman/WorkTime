import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/team_definition.dart';
import 'package:worktime_app/models/travel_time_rule.dart';
import 'package:worktime_app/models/user_invite.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/team_provider.dart';
import 'package:worktime_app/services/database_service.dart';
import 'package:worktime_app/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TeamProvider local mode', () {
    late FirestoreService firestoreService;
    late AppUserProfile adminUser;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetCachedPrefs();
      firestoreService = FirestoreService(
        firestore: FakeFirebaseFirestore(),
      );
      adminUser = const AppUserProfile(
        uid: 'admin-1',
        orgId: 'org-1',
        email: 'admin@example.com',
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(name: 'Admin'),
      );
    });

    SiteDefinition buildGermanSite(
      String name, {
      String? id,
      String? code,
      String? street,
      String? postalCode,
      String? city,
      String? federalState,
      double? latitude,
      double? longitude,
    }) {
      return SiteDefinition(
        id: id,
        orgId: 'org-1',
        name: name,
        code: code,
        street: street ?? 'Musterstrasse 1',
        postalCode: postalCode ?? '10115',
        city: city ?? 'Berlin',
        federalState: federalState ?? 'Berlin',
        latitude: latitude ?? 52.5321,
        longitude: longitude ?? 13.3849,
        createdByUid: 'admin-1',
      );
    }

    test('stores local invites and creates selectable local members', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveInvite(
        UserInvite(
          orgId: adminUser.orgId,
          email: 'anna@example.com',
          role: UserRole.employee,
          settings: const UserSettings(name: 'Anna'),
          createdByUid: adminUser.uid,
        ),
      );

      expect(provider.invites, hasLength(1));
      expect(
        provider.members.any((member) => member.email == 'anna@example.com'),
        isTrue,
      );
    });

    test('bootstraps demo sites and employee assignment for demo logins',
        () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(
        LocalDemoData.adminAccount.toProfile(orgId: 'org-1'),
      );

      final peter = provider.members.firstWhere(
        (member) => member.email == 'peter@example.com',
      );
      final maria = provider.members.firstWhere(
        (member) => member.email == 'maria@example.com',
      );
      final lea = provider.members.firstWhere(
        (member) => member.email == 'lea.teamlead@example.com',
      );
      expect(peter.displayName, 'Peter');
      expect(maria.displayName, 'Maria');
      expect(lea.displayName, 'Lea');
      expect(lea.role, UserRole.teamlead);
      expect(
        provider.sites.map((site) => site.name),
        containsAll(['Hauptstandort Berlin', 'Filiale Hamburg']),
      );

      expect(
        provider.siteAssignments.any(
          (assignment) =>
              assignment.userId == peter.uid &&
              assignment.siteName == 'Filiale Hamburg',
        ),
        isTrue,
      );
      expect(
        provider.siteAssignments.any(
          (assignment) =>
              assignment.userId == maria.uid &&
              assignment.siteName == 'Hauptstandort Berlin',
        ),
        isTrue,
      );
      expect(
        provider.siteAssignments.any(
          (assignment) =>
              assignment.userId == lea.uid &&
              assignment.siteName == 'Filiale Hamburg',
        ),
        isTrue,
      );
    });

    test('stores teams locally', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveTeam(
        TeamDefinition(
          orgId: 'org-1',
          name: 'Service',
          memberIds: ['admin-1', 'invite-member-anna@example.com'],
          createdByUid: 'admin-1',
        ),
      );

      expect(provider.teams, hasLength(1));
      expect(provider.teams.single.name, 'Service');
    });

    test('stores sites locally and exposes a default rule set', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveSite(
        buildGermanSite('Berlin'),
      );

      expect(provider.sites, hasLength(1));
      expect(provider.sites.single.name, 'Berlin');
      expect(provider.ruleSets, isNotEmpty);
    });

    test('stores employee-specific protection rules in the contract', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveMemberProtectionRules(
        userId: adminUser.uid,
        isMinor: true,
      );

      var contract =
          provider.contracts.firstWhere((item) => item.userId == adminUser.uid);
      expect(contract.isMinor, isTrue);
      expect(contract.isPregnant, isFalse);
      expect(contract.maxDailyMinutes, 480);

      await provider.saveMemberProtectionRules(
        userId: adminUser.uid,
        isMinor: false,
        isPregnant: true,
      );

      contract =
          provider.contracts.firstWhere((item) => item.userId == adminUser.uid);
      expect(contract.isMinor, isFalse);
      expect(contract.isPregnant, isTrue);
      expect(contract.maxDailyMinutes, 510);
    });

    test('stores employee-specific work rule settings on the profile',
        () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveMemberWorkRuleSettings(
        userId: adminUser.uid,
        settings: const WorkRuleSettings(
          enforceBreakAfterSixHours: false,
          warnSundayWork: false,
        ),
      );

      final updatedMember =
          provider.members.firstWhere((item) => item.uid == adminUser.uid);
      expect(updatedMember.workRuleSettings.enforceBreakAfterSixHours, isFalse);
      expect(updatedMember.workRuleSettings.warnSundayWork, isFalse);
      expect(updatedMember.workRuleSettings.enforceMaxDailyMinutes, isTrue);
    });

    test('overwrites inverse local travel time rules instead of duplicating',
        () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveSite(
        buildGermanSite('Berlin'),
      );
      await provider.saveSite(
        buildGermanSite(
          'Hamburg',
          street: 'Spitalerstrasse 12',
          postalCode: '20095',
          city: 'Hamburg',
          federalState: 'Hamburg',
          latitude: 53.5511,
          longitude: 9.9937,
        ),
      );

      final berlin = provider.sites.firstWhere((site) => site.name == 'Berlin');
      final hamburg =
          provider.sites.firstWhere((site) => site.name == 'Hamburg');

      await provider.saveTravelTimeRule(
        TravelTimeRule(
          orgId: 'org-1',
          fromSiteId: berlin.id!,
          toSiteId: hamburg.id!,
          travelMinutes: 35,
          createdByUid: 'admin-1',
        ),
      );

      await provider.saveTravelTimeRule(
        TravelTimeRule(
          orgId: 'org-1',
          fromSiteId: hamburg.id!,
          toSiteId: berlin.id!,
          travelMinutes: 42,
          createdByUid: 'admin-1',
        ),
      );

      expect(provider.travelTimeRules, hasLength(1));
      expect(provider.travelTimeRules.single.travelMinutes, 42);
    });

    test('removes local travel time rules when a site is deleted', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await provider.saveSite(
        buildGermanSite('Berlin'),
      );
      await provider.saveSite(
        buildGermanSite(
          'Hamburg',
          street: 'Spitalerstrasse 12',
          postalCode: '20095',
          city: 'Hamburg',
          federalState: 'Hamburg',
          latitude: 53.5511,
          longitude: 9.9937,
        ),
      );

      final berlin = provider.sites.firstWhere((site) => site.name == 'Berlin');
      final hamburg =
          provider.sites.firstWhere((site) => site.name == 'Hamburg');

      await provider.saveTravelTimeRule(
        TravelTimeRule(
          orgId: 'org-1',
          fromSiteId: berlin.id!,
          toSiteId: hamburg.id!,
          travelMinutes: 30,
          createdByUid: 'admin-1',
        ),
      );

      expect(provider.travelTimeRules, hasLength(1));

      await provider.deleteSite(berlin.id!);

      expect(provider.travelTimeRules, isEmpty);
    });

    test('rejects sites with coordinates outside Germany', () async {
      final provider = TeamProvider(
        firestoreService: firestoreService,
        disableAuthentication: true,
      );
      await provider.updateSession(adminUser);

      await expectLater(
        provider.saveSite(
          buildGermanSite(
            'Paris Test',
            street: 'Rue de Test 3',
            postalCode: '75001',
            city: 'Paris',
            federalState: 'Berlin',
            latitude: 48.8566,
            longitude: 2.3522,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('innerhalb Deutschlands'),
          ),
        ),
      );
    });
  });

  group('TeamProvider remote mode', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreService firestoreService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      firestoreService = FirestoreService(
        firestore: firestore,
      );
    });

    test('teamlead loads organization members and teams for planning',
        () async {
      const teamLead = AppUserProfile(
        uid: 'lead-1',
        orgId: 'org-1',
        email: 'lead@example.com',
        role: UserRole.teamlead,
        isActive: true,
        settings: UserSettings(name: 'Lead'),
      );
      const employee = AppUserProfile(
        uid: 'employee-1',
        orgId: 'org-1',
        email: 'employee@example.com',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'Employee'),
      );

      await firestore.collection('users').doc(teamLead.uid).set(
            teamLead.toFirestoreMap(),
          );
      await firestore.collection('users').doc(employee.uid).set(
            employee.toFirestoreMap(),
          );
      await firestore
          .collection('organizations')
          .doc('org-1')
          .collection('teams')
          .doc('team-1')
          .set(
            TeamDefinition(
              id: 'team-1',
              orgId: 'org-1',
              name: 'Service',
              memberIds: ['lead-1', 'employee-1'],
              createdByUid: 'admin-1',
            ).toFirestoreMap(),
          );

      final provider = TeamProvider(
        firestoreService: firestoreService,
      );
      await provider.updateSession(teamLead);
      await Future<void>.delayed(Duration.zero);

      expect(
        provider.members.map((member) => member.uid),
        containsAll(['lead-1', 'employee-1']),
      );
      expect(provider.teams.map((team) => team.name), contains('Service'));
    });
  });
}
