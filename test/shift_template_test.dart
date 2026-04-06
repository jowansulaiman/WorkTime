import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/shift_template.dart';

void main() {
  group('ShiftTemplate', () {
    test('serializes and restores templates', () {
      final template = ShiftTemplate(
        id: 'template-1',
        orgId: 'org-1',
        userId: 'lead-1',
        name: 'Fruehdienst Berlin',
        title: 'Fruehdienst',
        startMinutes: 8 * 60,
        endMinutes: 16 * 60,
        breakMinutes: 30,
        teamId: 'team-1',
        teamName: 'Service',
        siteId: 'site-1',
        siteName: 'Berlin',
        requiredQualificationIds: const ['q-1', 'q-2'],
        notes: 'Kasse zuerst besetzen',
        color: '#2196F3',
      );

      final restored = ShiftTemplate.fromMap(template.toMap());

      expect(restored.id, 'template-1');
      expect(restored.orgId, 'org-1');
      expect(restored.userId, 'lead-1');
      expect(restored.name, 'Fruehdienst Berlin');
      expect(restored.title, 'Fruehdienst');
      expect(restored.startMinutes, 8 * 60);
      expect(restored.endMinutes, 16 * 60);
      expect(restored.breakMinutes, 30);
      expect(restored.teamId, 'team-1');
      expect(restored.teamName, 'Service');
      expect(restored.siteId, 'site-1');
      expect(restored.siteName, 'Berlin');
      expect(restored.requiredQualificationIds, ['q-1', 'q-2']);
      expect(restored.notes, 'Kasse zuerst besetzen');
      expect(restored.color, '#2196F3');
    });
  });
}
