import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/app_config.dart';
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

const _teamlead = AppUserProfile(
  uid: 'lead-1',
  orgId: 'org-1',
  email: 'lea@example.com',
  role: UserRole.teamlead,
  isActive: true,
  settings: UserSettings(name: 'Lea'),
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
      expect(RoutePermissions.isLocationAllowed(AppRoutes.auditLog, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.personal, _admin),
          isTrue);
    });

    test('Werbe-Displays (/werbung): nie für Nicht-Admins; Admin nur bei Flag',
        () {
      // Nicht-Admins sind IMMER gesperrt (unabhängig vom Feature-Flag).
      expect(RoutePermissions.isLocationAllowed(AppRoutes.signage, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.signage, _teamlead),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.signage, null),
          isFalse);
      // Admin nur bei aktivem APP_SIGNAGE_ENABLED (im Test standardmäßig aus) —
      // spiegelt die Hub-Kachel + verhindert Deep-Link-Umgehung des Flags.
      expect(RoutePermissions.isLocationAllowed(AppRoutes.signage, _admin),
          AppConfig.signageEnabled);
    });

    test('Mitarbeiter-Detail-Deep-Link /personal/{uid} ist admin-only', () {
      // Konkreter Pfad mit gefülltem :id — matcht KEINEN exakten switch-case und
      // fiele ohne den `/personal/`-Prefix-Guard auf default:true (Leck).
      final path = AppRoutes.personalDetailPath('emp-1');
      expect(RoutePermissions.isLocationAllowed(path, _admin), isTrue);
      expect(RoutePermissions.isLocationAllowed(path, _teamlead), isFalse);
      expect(RoutePermissions.isLocationAllowed(path, _employee), isFalse);
      expect(RoutePermissions.isLocationAllowed(path, null), isFalse);
      // Der Prefix-Guard darf die eigenständige „Meine Akte"-Route (/meine-akte)
      // NICHT fälschlich als /personal-Unterpfad greifen.
      expect(RoutePermissions.isLocationAllowed(AppRoutes.meineAkte, _employee),
          isTrue);
    });

    test('Kontakt-Detail-Deep-Link /kontakte/{id} = canViewContacts', () {
      // Konkreter Pfad mit gefülltem :id — matcht KEINEN exakten switch-case und
      // fiele ohne den `/kontakte/`-Prefix-Guard auf default:true (Leck).
      // Anders als Personal: JEDES aktive Mitglied darf lesen (canViewContacts),
      // nur der URL-Kontext ist gegatet; Verwaltungs-Aktionen im Screen.
      final path = AppRoutes.contactDetailPath('kontakt-1');
      expect(RoutePermissions.isLocationAllowed(path, _admin), isTrue);
      expect(RoutePermissions.isLocationAllowed(path, _teamlead), isTrue);
      expect(RoutePermissions.isLocationAllowed(path, _employee), isTrue);
      expect(RoutePermissions.isLocationAllowed(path, null), isFalse);
      // Der Kontakt-Tab-Case (/kontakte) und der Detail-Deep-Link müssen
      // dieselbe Regel tragen.
      expect(
        RoutePermissions.isLocationAllowed(path, _employee),
        RoutePermissions.isLocationAllowed('/kontakte', _employee),
      );
    });

    test('Inventur (/inventur): canManageInventory — Admin+Teamleitung ja, '
        'Mitarbeiter nein', () {
      expect(RoutePermissions.isLocationAllowed(AppRoutes.inventur, _admin),
          isTrue);
      // Teamleitung hat per Default canEditSchedule -> canManageInventory.
      expect(RoutePermissions.isLocationAllowed(AppRoutes.inventur, _teamlead),
          isTrue);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.inventur, _employee),
          isFalse);
      expect(RoutePermissions.isLocationAllowed(AppRoutes.inventur, null),
          isFalse);
    });

    test('Kassenbericht: nur Admin (EK/Marge/Gewinn, M4)', () {
      expect(RoutePermissions.isLocationAllowed(AppRoutes.kassenbericht, _admin),
          isTrue);
      expect(
          RoutePermissions.isLocationAllowed(AppRoutes.kassenbericht, _teamlead),
          isFalse);
      expect(
          RoutePermissions.isLocationAllowed(AppRoutes.kassenbericht, _employee),
          isFalse);
    });

    test('Tagesabschluss: Admin + Teamleitung ja, Mitarbeiter nein (M3)', () {
      expect(RoutePermissions.isLocationAllowed(AppRoutes.dailyClosing, _admin),
          isTrue);
      expect(
          RoutePermissions.isLocationAllowed(AppRoutes.dailyClosing, _teamlead),
          isTrue);
      expect(
          RoutePermissions.isLocationAllowed(AppRoutes.dailyClosing, _employee),
          isFalse);
    });

    test('Heute/Anfragen/Profil/Einstellungen sind immer erlaubt', () {
      for (final loc in ['/', '/anfragen', '/profil', AppRoutes.settings]) {
        expect(RoutePermissions.isLocationAllowed(loc, null), isTrue,
            reason: '$loc darf nie blockieren (Schleifenschutz)');
      }
    });
  });
}
