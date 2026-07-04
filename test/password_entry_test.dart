import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/password_entry.dart';

/// PM-M1: Enums + Metadaten-Model. Prüft beide Serialisierungen, dass KEINE
/// Sensitiva im Model existieren, und die copyWith-`clearX`-Semantik.
void main() {
  group('PasswordCategory', () {
    test('.value ist snake_case, round-trippt', () {
      for (final c in PasswordCategory.values) {
        expect(PasswordCategoryX.fromValue(c.value), c);
      }
      expect(PasswordCategory.supplierPortal.value, 'supplier_portal');
      expect(PasswordCategory.authorityPortal.value, 'authority_portal');
    });

    test('fromValue mit unbekanntem Wert → other (Default-Branch)', () {
      expect(PasswordCategoryX.fromValue('quatsch'), PasswordCategory.other);
      expect(PasswordCategoryX.fromValue(null), PasswordCategory.other);
    });

    test('label ist deutsch', () {
      expect(PasswordCategory.kvg.label, 'KVG');
      expect(PasswordCategory.supplierPortal.label, 'Lieferantenportal');
    });
  });

  group('PasswordScope', () {
    test('.value round-trippt + Default personal', () {
      expect(PasswordScopeX.fromValue('shared'), PasswordScope.shared);
      expect(PasswordScopeX.fromValue('personal'), PasswordScope.personal);
      expect(PasswordScopeX.fromValue(null), PasswordScope.personal);
    });
  });

  group('PasswordEntry Serialisierung', () {
    const entry = PasswordEntry(
      id: 'e1',
      orgId: 'org-1',
      title: 'KVG Portal',
      category: PasswordCategory.kvg,
      siteId: 'site-1',
      siteName: 'Kiel',
      ownerUid: 'u1',
      ownerLabel: 'Peter',
      scope: PasswordScope.shared,
      audienceUids: ['u2', 'u3'],
      audienceRoles: ['teamlead'],
      audienceSiteIds: ['site-1'],
      url: 'https://kvg.example',
      hasSecret: true,
    );

    test('Firestore-Roundtrip (camelCase) erhält Metadaten', () {
      final back = PasswordEntry.fromFirestore('e1', entry.toFirestoreMap());
      expect(back.title, 'KVG Portal');
      expect(back.category, PasswordCategory.kvg);
      expect(back.scope, PasswordScope.shared);
      expect(back.audienceUids, ['u2', 'u3']);
      expect(back.audienceRoles, ['teamlead']);
      expect(back.audienceSiteIds, ['site-1']);
      expect(back.hasSecret, isTrue);
      expect(back.url, 'https://kvg.example');
      expect(back.siteName, 'Kiel');
    });

    test('lokaler Roundtrip (snake_case) erhält Metadaten', () {
      final map = entry.toMap();
      expect(map['audience_site_ids'], ['site-1']);
      expect(map['has_secret'], isTrue);
      final back = PasswordEntry.fromMap(map);
      expect(back.title, 'KVG Portal');
      expect(back.ownerUid, 'u1');
      expect(back.scope, PasswordScope.shared);
    });

    test('Model enthält KEINE Sensitiva (kein Passwort/Username/keyVersion)', () {
      final keys = {...entry.toFirestoreMap().keys, ...entry.toMap().keys};
      for (final forbidden in [
        'password',
        'plain_password',
        'username',
        'usernameHint',
        'username_hint',
        'notes',
        'keyVersion',
        'key_version',
        'strengthMeta',
        'strength_meta',
        'dupGroupHash',
      ]) {
        expect(keys.contains(forbidden), isFalse,
            reason: 'Sensitives Feld $forbidden darf nicht in Metadaten sein');
      }
    });

    test('copyWith(clearX) leert nullable Felder', () {
      final cleared = entry.copyWith(
          clearSiteId: true, clearSiteName: true, clearUrl: true);
      expect(cleared.siteId, isNull);
      expect(cleared.siteName, isNull);
      expect(cleared.url, isNull);
      expect(cleared.title, 'KVG Portal');
    });
  });
}
