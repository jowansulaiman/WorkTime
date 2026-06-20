import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/ean.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/widgets/responsive_layout.dart';

void main() {
  group('EAN-Pruefziffer', () {
    test('akzeptiert gueltige EAN-13/EAN-8/UPC-A', () {
      expect(isValidEanChecksum('4006381333931'), isTrue); // EAN-13
      expect(isValidEanChecksum('5449000000996'), isTrue); // EAN-13 (Cola)
      expect(isValidEanChecksum('96385074'), isTrue); // EAN-8
      expect(isValidEanChecksum('036000291452'), isTrue); // UPC-A
    });

    test('lehnt falsche Pruefziffer ab', () {
      expect(isValidEanChecksum('4006381333930'), isFalse);
      expect(isValidEanChecksum('96385075'), isFalse);
    });

    test('lehnt nicht-numerische oder falsch lange Codes ab', () {
      expect(isValidEanChecksum('abc'), isFalse);
      expect(isValidEanChecksum('123'), isFalse); // zu kurz
      expect(isValidEanChecksum('40063813339311'), isFalse); // 14 Stellen
      expect(isValidEanChecksum(''), isFalse);
    });

    test('toleriert umschliessende Leerzeichen', () {
      expect(isValidEanChecksum('  4006381333931 '), isTrue);
    });

    test('looksLikeEan prueft nur die Laenge', () {
      expect(looksLikeEan('00000000'), isTrue); // 8 Stellen
      expect(looksLikeEan('000000000000'), isTrue); // 12 Stellen
      expect(looksLikeEan('0000000000000'), isTrue); // 13 Stellen
      expect(looksLikeEan('123'), isFalse);
      expect(looksLikeEan('12a45678'), isFalse);
    });
  });

  group('MobileBreakpoints.isNativeMobile', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('true auf Android/iOS (nicht Web — Test laeuft auf VM)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(MobileBreakpoints.isNativeMobile, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(MobileBreakpoints.isNativeMobile, isTrue);
    });

    test('false auf Desktop-Plattformen', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(MobileBreakpoints.isNativeMobile, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(MobileBreakpoints.isNativeMobile, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(MobileBreakpoints.isNativeMobile, isFalse);
    });
  });

  group('AppUserProfile.canUseScanner', () {
    AppUserProfile profile(UserRole role, {bool active = true}) =>
        AppUserProfile(
          uid: 'u',
          orgId: 'org-1',
          email: 'u@laden.test',
          role: role,
          isActive: active,
          settings: const UserSettings(name: 'X'),
        );

    test('Admin darf scannen', () {
      expect(profile(UserRole.admin).canUseScanner, isTrue);
    });

    test('inaktiver Admin darf nicht', () {
      expect(profile(UserRole.admin, active: false).canUseScanner, isFalse);
    });

    test('einfacher Mitarbeiter ohne Schichtrecht darf nicht', () {
      expect(profile(UserRole.employee).canUseScanner, isFalse);
    });
  });
}
