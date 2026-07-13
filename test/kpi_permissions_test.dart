import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/kpi_permissions.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';

void main() {
  // Baut überschreibbare Permissions über die Rollen-Defaults (per-User-Override
  // wie in Firestore) — nur die genannten Flags weichen ab.
  UserPermissions perms(
    UserRole role, {
    bool? canEditSchedule,
    bool? canViewReports,
  }) =>
      UserPermissions.defaultsForRole(role).copyWith(
        canEditSchedule: canEditSchedule,
        canViewReports: canViewReports,
      );

  AppUserProfile profile({
    required UserRole role,
    bool isActive = true,
    UserPermissions? permissions,
  }) =>
      AppUserProfile(
        uid: 'u1',
        orgId: 'org-1',
        email: 'u1@example.com',
        role: role,
        isActive: isActive,
        settings: const UserSettings(name: 'Test'),
        permissions: permissions,
      );

  group('KpiPermissions.isKpiAllowed', () {
    test('null-Profil und inaktive Nutzer sehen NIE eine Kennzahl', () {
      for (final kpi in KpiId.values) {
        expect(KpiPermissions.isKpiAllowed(kpi, null), isFalse,
            reason: '$kpi bei null');
        expect(
          KpiPermissions.isKpiAllowed(
              kpi, profile(role: UserRole.admin, isActive: false)),
          isFalse,
          reason: '$kpi bei inaktivem Admin',
        );
      }
    });

    test('Admin sieht alle Kennzahlen', () {
      final admin = profile(role: UserRole.admin);
      for (final kpi in KpiId.values) {
        expect(KpiPermissions.isKpiAllowed(kpi, admin), isTrue,
            reason: '$kpi für Admin');
      }
    });

    test('Employee ohne Reports-Recht sieht keine Kennzahl', () {
      final employee = profile(
        role: UserRole.employee,
        permissions: perms(UserRole.employee, canViewReports: false),
      );
      for (final kpi in KpiId.values) {
        expect(KpiPermissions.isKpiAllowed(kpi, employee), isFalse,
            reason: '$kpi für rechtlosen Employee');
      }
    });

    test('eigeneZeitStatistik hängt an canViewReports (permission-basiert)', () {
      final mitReports = profile(
        role: UserRole.employee,
        permissions: perms(UserRole.employee,
            canViewReports: true, canEditSchedule: false),
      );
      expect(
          KpiPermissions.isKpiAllowed(KpiId.eigeneZeitStatistik, mitReports),
          isTrue);
      // Aber keine org-weite/Lohn-Kennzahl.
      expect(KpiPermissions.isKpiAllowed(KpiId.zeitkontoOrg, mitReports),
          isFalse);
      expect(
          KpiPermissions.isKpiAllowed(KpiId.lohnquote, mitReports), isFalse);
    });

    test('Override-Fall: Employee mit canEditSchedule sieht org-Zeit, aber '
        'keine Kassendaten (rollenbasierte Rules)', () {
      final teamleadFlags = profile(
        role: UserRole.employee,
        permissions: perms(UserRole.employee, canEditSchedule: true),
      );
      // canManageShifts == true via Override → org-Zeit erlaubt
      expect(KpiPermissions.isKpiAllowed(KpiId.zeitkontoOrg, teamleadFlags),
          isTrue);
      expect(KpiPermissions.isKpiAllowed(KpiId.offeneFreigaben, teamleadFlags),
          isTrue);
      // Kassendaten sind ROLLENbasiert → Employee-Override reicht NICHT
      expect(KpiPermissions.isKpiAllowed(KpiId.umsatz, teamleadFlags), isFalse);
      expect(
          KpiPermissions.isKpiAllowed(KpiId.belegeSite, teamleadFlags), isFalse);
    });

    test('Teamlead sieht Umsatz/Belege, aber nicht Rohertrag/Lohn', () {
      final teamlead = profile(role: UserRole.teamlead);
      expect(KpiPermissions.isKpiAllowed(KpiId.umsatz, teamlead), isTrue);
      expect(KpiPermissions.isKpiAllowed(KpiId.belegeSite, teamlead), isTrue);
      expect(KpiPermissions.isKpiAllowed(KpiId.rohertrag, teamlead), isFalse);
      expect(KpiPermissions.isKpiAllowed(KpiId.lohnquote, teamlead), isFalse);
      expect(
          KpiPermissions.isKpiAllowed(KpiId.betriebsergebnis, teamlead), isFalse);
    });

    test('bestandswertVk an canManageInventory, bestandswertEk admin-only', () {
      // Teamlead mit Default-Rechten hat canEditSchedule → canManageInventory.
      final teamlead = profile(role: UserRole.teamlead);
      expect(KpiPermissions.isKpiAllowed(KpiId.bestandswertVk, teamlead),
          isTrue);
      expect(KpiPermissions.isKpiAllowed(KpiId.bestandswertEk, teamlead),
          isFalse);

      // Employee OHNE canEditSchedule → kein canManageInventory → auch kein VK.
      final employee = profile(
        role: UserRole.employee,
        permissions: perms(UserRole.employee, canEditSchedule: false),
      );
      expect(KpiPermissions.isKpiAllowed(KpiId.bestandswertVk, employee),
          isFalse);
    });
  });

  group('KpiPermissions.visibleKpis', () {
    test('liefert Kennzahlen in Deklarationsreihenfolge', () {
      final admin = profile(role: UserRole.admin);
      final visible = KpiPermissions.visibleKpis(admin);
      expect(visible, KpiId.values); // Admin sieht alle, in Reihenfolge
    });

    test('leer für null-Profil', () {
      expect(KpiPermissions.visibleKpis(null), isEmpty);
    });
  });
}
