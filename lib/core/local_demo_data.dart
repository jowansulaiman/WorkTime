import '../models/app_user.dart';
import '../models/employee_site_assignment.dart';
import '../models/site_definition.dart';
import '../models/user_settings.dart';

class LocalDemoAccount {
  const LocalDemoAccount({
    required this.uid,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
    required this.description,
  });

  final String uid;
  final String email;
  final String password;
  final String name;
  final UserRole role;
  final String description;

  AppUserProfile toProfile({required String orgId}) {
    return AppUserProfile(
      uid: uid,
      orgId: orgId,
      email: email,
      role: role,
      isActive: true,
      settings: UserSettings(
        name: name,
        hourlyRate: role == UserRole.employee ? 16.5 : 0,
        dailyHours: 8,
        currency: 'EUR',
        vacationDays: 30,
      ),
    );
  }
}

class LocalDemoData {
  LocalDemoData._();

  static const LocalDemoAccount adminAccount = LocalDemoAccount(
    uid: 'local-demo-admin',
    email: 'admin@demo.local',
    password: 'demo1234',
    name: 'Lokaler Admin',
    role: UserRole.admin,
    description: 'Voller Zugriff auf Teamverwaltung, Planung und Auswertungen.',
  );

  static const LocalDemoAccount employeeAccount = LocalDemoAccount(
    uid: 'local-test-peter',
    email: 'peter@example.com',
    password: 'demo1234',
    name: 'Peter',
    role: UserRole.employee,
    description:
        'Mitarbeiterprofil fuer Zeiterfassung, Schichten und Abwesenheiten.',
  );

  static const LocalDemoAccount employeeSecondAccount = LocalDemoAccount(
    uid: 'local-test-maria',
    email: 'maria@example.com',
    password: 'demo1234',
    name: 'Maria',
    role: UserRole.employee,
    description:
        'Zweites Mitarbeiterprofil fuer Tests mit mehreren Mitarbeitern.',
  );

  static const LocalDemoAccount teamLeadAccount = LocalDemoAccount(
    uid: 'local-test-lea',
    email: 'lea.teamlead@example.com',
    password: 'demo1234',
    name: 'Lea',
    role: UserRole.teamlead,
    description:
        'Teamleiterprofil mit Zugriff auf Planung, Freigaben und Teamansichten.',
  );

  static const List<LocalDemoAccount> accounts = [
    adminAccount,
    employeeAccount,
    employeeSecondAccount,
    teamLeadAccount,
  ];

  static LocalDemoAccount? accountForUid(String? uid) {
    if (uid == null || uid.trim().isEmpty) {
      return null;
    }
    final normalizedUid = uid.trim();
    for (final account in accounts) {
      if (account.uid == normalizedUid) {
        return account;
      }
    }
    return null;
  }

  static LocalDemoAccount? accountForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    for (final account in accounts) {
      if (account.email.toLowerCase() == normalizedEmail) {
        return account;
      }
    }
    return null;
  }

  static AppUserProfile? profileForUid(
    String? uid, {
    required String orgId,
  }) {
    final account = accountForUid(uid);
    return account?.toProfile(orgId: orgId);
  }

  static AppUserProfile? authenticate({
    required String email,
    required String password,
    required String orgId,
  }) {
    final account = accountForEmail(email);
    if (account == null || account.password != password.trim()) {
      return null;
    }
    return account.toProfile(orgId: orgId);
  }

  static bool isDemoUser(AppUserProfile? profile) {
    if (profile == null) {
      return false;
    }
    return accountForUid(profile.uid) != null ||
        accountForEmail(profile.email) != null;
  }

  static List<AppUserProfile> profilesForOrg(String orgId) {
    return accounts
        .map((account) => account.toProfile(orgId: orgId))
        .toList(growable: false);
  }

  static List<SiteDefinition> sitesForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    return [
      SiteDefinition(
        id: 'demo-site-$orgId-berlin',
        orgId: orgId,
        name: 'Hauptstandort Berlin',
        code: 'BER-HQ',
        street: 'Invalidenstrasse 117',
        postalCode: '10115',
        city: 'Berlin',
        federalState: 'Berlin',
        countryCode: SiteDefinition.germanyCountryCode,
        latitude: 52.5321,
        longitude: 13.3849,
        description: 'Dummy-Standort fuer Tests im lokalen Modus.',
        createdByUid: createdByUid,
      ),
      SiteDefinition(
        id: 'demo-site-$orgId-hamburg',
        orgId: orgId,
        name: 'Filiale Hamburg',
        code: 'HAM',
        street: 'Spitalerstrasse 22',
        postalCode: '20095',
        city: 'Hamburg',
        federalState: 'Hamburg',
        countryCode: SiteDefinition.germanyCountryCode,
        latitude: 53.5511,
        longitude: 9.9937,
        description: 'Zweiter Dummy-Standort fuer Schicht- und Standorttests.',
        createdByUid: createdByUid,
      ),
    ];
  }

  static List<EmployeeSiteAssignment> siteAssignmentsForOrg({
    required String orgId,
    required String createdByUid,
  }) {
    return [
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-admin',
        orgId: orgId,
        userId: adminAccount.uid,
        siteId: 'demo-site-$orgId-berlin',
        siteName: 'Hauptstandort Berlin',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-peter',
        orgId: orgId,
        userId: employeeAccount.uid,
        siteId: 'demo-site-$orgId-hamburg',
        siteName: 'Filiale Hamburg',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-maria',
        orgId: orgId,
        userId: employeeSecondAccount.uid,
        siteId: 'demo-site-$orgId-berlin',
        siteName: 'Hauptstandort Berlin',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
      EmployeeSiteAssignment(
        id: 'demo-assignment-$orgId-lea',
        orgId: orgId,
        userId: teamLeadAccount.uid,
        siteId: 'demo-site-$orgId-hamburg',
        siteName: 'Filiale Hamburg',
        isPrimary: true,
        createdByUid: createdByUid,
      ),
    ];
  }
}
