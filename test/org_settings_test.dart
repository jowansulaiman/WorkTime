import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/org_settings.dart';

void main() {
  group('OrgSettings', () {
    test('defaults sind korrekt (Cap-Default weich = Überstunden-Modus)', () {
      final settings = OrgSettings.defaults('org-1');
      expect(settings.orgId, 'org-1');
      expect(settings.enforceHourCapHard, isFalse);
      expect(settings.defaultShiftMinutes, 480);
      expect(settings.defaultBreakMinutes, 30);
      expect(settings.defaultRequiredCount, 1);
    });

    test('round-trip Firestore (camelCase)', () {
      const settings = OrgSettings(
        id: OrgSettings.documentId,
        orgId: 'org-1',
        enforceHourCapHard: true,
        defaultShiftMinutes: 360,
        defaultBreakMinutes: 45,
        defaultRequiredCount: 3,
      );
      final restored = OrgSettings.fromFirestore(
        OrgSettings.documentId,
        settings.toFirestoreMap(),
      );
      expect(restored.enforceHourCapHard, isTrue);
      expect(restored.defaultShiftMinutes, 360);
      expect(restored.defaultBreakMinutes, 45);
      expect(restored.defaultRequiredCount, 3);
      expect(restored.orgId, 'org-1');
    });

    test('round-trip lokal (snake_case)', () {
      const settings = OrgSettings(
        orgId: 'org-1',
        enforceHourCapHard: true,
        defaultShiftMinutes: 420,
      );
      final map = settings.toMap();
      expect(map['enforce_hour_cap_hard'], isTrue);
      expect(map['default_shift_minutes'], 420);
      final restored = OrgSettings.fromMap(map);
      expect(restored.enforceHourCapHard, isTrue);
      expect(restored.defaultShiftMinutes, 420);
      expect(restored.defaultBreakMinutes, 30);
    });

    test('Altdaten / fehlende Felder fallen auf Defaults', () {
      final restored = OrgSettings.fromMap({'org_id': 'org-1'});
      expect(restored.enforceHourCapHard, isFalse);
      expect(restored.defaultShiftMinutes, 480);
      expect(restored.defaultRequiredCount, 1);
    });

    test('documentId ist deterministisch', () {
      expect(OrgSettings.documentId, 'orgSettings');
    });
  });
}
