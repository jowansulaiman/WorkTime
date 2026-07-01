import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/notification_prefs.dart';
import 'package:worktime_app/models/user_settings.dart';

void main() {
  group('NotificationPrefs', () {
    test('Defaults: alles an, Ruhezeit aus, 22:00–06:00', () {
      const p = NotificationPrefs();
      expect(p.masterEnabled, isTrue);
      expect(p.bestand, isTrue);
      expect(p.quietHoursEnabled, isFalse);
      expect(p.quietStartMinutes, 22 * 60);
      expect(p.quietEndMinutes, 6 * 60);
    });

    test('camelCase Round-Trip (Firestore)', () {
      const p = NotificationPrefs(
        masterEnabled: true,
        bestand: false,
        quietHoursEnabled: true,
        quietStartMinutes: 1290,
        quietEndMinutes: 420,
      );
      final back = NotificationPrefs.fromMap(p.toFirestoreMap());
      expect(back.bestand, isFalse);
      expect(back.quietHoursEnabled, isTrue);
      expect(back.quietStartMinutes, 1290);
      expect(back.quietEndMinutes, 420);
    });

    test('snake_case Round-Trip (lokal)', () {
      const p = NotificationPrefs(genehmigungen: false, kundenwuensche: false);
      final back = NotificationPrefs.fromMap(p.toMap());
      expect(back.genehmigungen, isFalse);
      expect(back.kundenwuensche, isFalse);
      expect(back.schichtplan, isTrue);
    });

    test('categoryEnabled bildet die fünf Channels ab', () {
      const p = NotificationPrefs(schichtplan: false);
      expect(p.categoryEnabled('schichtplan'), isFalse);
      expect(p.categoryEnabled('genehmigungen'), isTrue);
      expect(p.categoryEnabled('unbekannt'), isTrue);
    });

    test('AppUserProfile trägt notificationPrefs durch beide Formate', () {
      const profile = AppUserProfile(
        uid: 'u1',
        orgId: 'org-1',
        email: 'u1@x.de',
        role: UserRole.employee,
        isActive: true,
        settings: UserSettings(name: 'U1'),
        notificationPrefs: NotificationPrefs(bestand: false),
      );
      final fs = AppUserProfile.fromFirestore('u1', profile.toFirestoreMap());
      expect(fs.notificationPrefs.bestand, isFalse);
      final local = AppUserProfile.fromMap(profile.toMap());
      expect(local.notificationPrefs.bestand, isFalse);
    });
  });
}
