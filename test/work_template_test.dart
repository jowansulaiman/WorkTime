import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/work_template.dart';

void main() {
  group('WorkTemplate', () {
    test('serializes and restores templates', () {
      final template = WorkTemplate(
        id: '4',
        name: 'Frühdienst',
        startMinutes: 6 * 60,
        endMinutes: 14 * 60 + 30,
        breakMinutes: 45,
        note: 'Lager öffnen',
      );

      final map = template.toMap();
      final restored = WorkTemplate.fromMap(map);

      expect(restored.id, '4');
      expect(restored.name, 'Frühdienst');
      expect(restored.startMinutes, 360);
      expect(restored.endMinutes, 870);
      expect(restored.breakMinutes, 45);
      expect(restored.note, 'Lager öffnen');
    });

    test('trims empty notes to null', () {
      final template = WorkTemplate(
        name: 'Bürotag',
        startMinutes: 8 * 60,
        endMinutes: 17 * 60,
        note: '   ',
      );

      expect(template.note, isNull);
    });
  });
}
