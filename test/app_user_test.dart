import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_invite.dart';
import 'package:worktime_app/models/user_settings.dart';

void main() {
  group('UserRoleX.fromValue', () {
    test('accepts legacy teamleiter alias', () {
      expect(UserRoleX.fromValue('teamleiter'), UserRole.teamlead);
      expect(UserRoleX.fromValue('TeamLeiter'), UserRole.teamlead);
    });
  });

  group('AppUserProfile.fromFirestore', () {
    test('treats legacy teamleiter role as teamlead defaults', () {
      final profile = AppUserProfile.fromFirestore('user-1', {
        'orgId': 'org-1',
        'email': 'lead@example.com',
        'role': 'teamleiter',
        'isActive': true,
        'settings': {'name': 'Lead'},
      });

      expect(profile.role, UserRole.teamlead);
      expect(profile.canManageShifts, isTrue);
    });

    test('parses string permissions as enabled flags', () {
      final profile = AppUserProfile.fromFirestore('user-1', {
        'orgId': 'org-1',
        'email': 'lead@example.com',
        'role': 'employee',
        'isActive': true,
        'permissions': {
          'canViewSchedule': 'true',
          'canEditSchedule': 'true',
          'canViewTimeTracking': 'true',
          'canEditTimeEntries': 'true',
          'canViewReports': 'true',
        },
        'settings': {'name': 'Lead'},
      });

      expect(profile.canManageShifts, isTrue);
      expect(profile.canViewSchedule, isTrue);
    });

    test('parses employee-specific work rule settings', () {
      final profile = AppUserProfile.fromFirestore('user-1', {
        'orgId': 'org-1',
        'email': 'employee@example.com',
        'role': 'employee',
        'isActive': true,
        'workRuleSettings': {
          'enforceBreakAfterSixHours': false,
          'warnSundayWork': 'false',
        },
        'settings': {'name': 'Mira'},
      });

      expect(profile.workRuleSettings.enforceBreakAfterSixHours, isFalse);
      expect(profile.workRuleSettings.enforceBreakAfterNineHours, isTrue);
      expect(profile.workRuleSettings.warnSundayWork, isFalse);
    });

    test('reads legacy snake_case profile fields from Firestore', () {
      final profile = AppUserProfile.fromFirestore('user-1', {
        'org_id': 'org-legacy',
        'email': 'lead@example.com',
        'role': 'teamleiter',
        'is_active': 'true',
        'photo_url': 'https://example.com/photo.png',
        'settings': {
          'name': 'Lead',
          'daily_hours': 7.5,
        },
      });

      expect(profile.orgId, 'org-legacy');
      expect(profile.isActive, isTrue);
      expect(profile.photoUrl, 'https://example.com/photo.png');
      expect(profile.settings.dailyHours, 7.5);
      expect(profile.canManageShifts, isTrue);
    });
  });

  group('AppUserProfile.canReviewAbsenceRequestFor', () {
    const admin = AppUserProfile(
      uid: 'admin-1',
      orgId: 'org-1',
      email: 'admin@example.com',
      role: UserRole.admin,
      isActive: true,
      settings: UserSettings(name: 'Admin'),
    );
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

    test('allows admins to review managed requests', () {
      expect(admin.canReviewAbsenceRequestFor(teamLead), isTrue);
      expect(admin.canReviewAbsenceRequestFor(admin), isTrue);
    });

    test('allows teamleads to review employee requests only', () {
      expect(teamLead.canReviewAbsenceRequestFor(employee), isTrue);
      expect(teamLead.canReviewAbsenceRequestFor(teamLead), isFalse);
      expect(teamLead.canReviewAbsenceRequestFor(admin), isFalse);
    });

    test('allows teamleads to manage approved vacations for self and employees',
        () {
      expect(teamLead.canManageApprovedVacationFor(employee), isTrue);
      expect(teamLead.canManageApprovedVacationFor(teamLead), isTrue);
      expect(teamLead.canManageApprovedVacationFor(admin), isFalse);
    });
  });

  group('UserInvite.fromFirestore', () {
    test('reads legacy snake_case invite fields from Firestore', () {
      final invite = UserInvite.fromFirestore('lead@example.com', {
        'org_id': 'org-legacy',
        'email': 'lead@example.com',
        'role': 'teamleiter',
        'created_by_uid': 'admin-1',
        'is_active': true,
        'settings': {
          'name': 'Lead',
          'daily_hours': 7.5,
        },
      });

      expect(invite.orgId, 'org-legacy');
      expect(invite.createdByUid, 'admin-1');
      expect(invite.isActive, isTrue);
      expect(invite.settings.dailyHours, 7.5);
      expect(invite.effectivePermissions.canEditSchedule, isTrue);
    });
  });
}
