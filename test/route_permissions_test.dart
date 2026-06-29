import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/routing/route_permissions.dart';
import 'package:worktime_app/routing/shell_tab.dart';

const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

const _employee = AppUserProfile(
  uid: 'emp-1',
  orgId: 'org-1',
  email: 'peter@example.com',
  role: UserRole.employee,
  isActive: true,
  settings: UserSettings(name: 'Peter'),
);

void main() {
  group('RoutePermissions', () {
    test('Shop-Tab-Sichtbarkeit == /laden-Routenrecht (keine Divergenz, H-H2)',
        () {
      for (final user in [_admin, _employee, null]) {
        expect(
          RoutePermissions.isShellTabAllowed(ShellTab.shop, user),
          RoutePermissions.isLocationAllowed('/laden', user),
          reason: 'Tab und Route müssen dieselbe Regel tragen',
        );
      }
    });

    test('jeder Shell-Tab leitet aus seinem kanonischen Pfad ab', () {
      for (final tab in ShellTab.values) {
        final path = shellTabPaths[tab]!;
        expect(
          RoutePermissions.isShellTabAllowed(tab, _employee),
          RoutePermissions.isLocationAllowed(path, _employee),
        );
      }
    });

    test('Admin-only Bereiche sind für Mitarbeiter gesperrt', () {
      expect(RoutePermissions.isLocationAllowed(AppRoutes.personal, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.finance, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.team, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.auditLog, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.personal, _admin),
          isTrue);
    });

    test('Heute/Anfragen/Profil/Einstellungen sind immer erlaubt', () {
      for (final loc in ['/', '/anfragen', '/profil', AppRoutes.settings]) {
        expect(RoutePermissions.isLocationAllowed(loc, null), isTrue,
            reason: '$loc darf nie blockieren (Schleifenschutz)');
      }
    });
  });
}
