import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/site_schedule.dart';
import 'package:worktime_app/models/third_party_cash.dart';

void main() {
  group('SiteDefinition weekdayHours + staffingDemands', () {
    SiteDefinition build() => const SiteDefinition(
          id: 'site-1',
          orgId: 'org-1',
          name: 'Laden',
          weekdayHours: [
            WeekdayHours(
              weekday: DateTime.monday,
              windows: [
                TimeWindow(startMinute: 540, endMinute: 780),
                TimeWindow(startMinute: 900, endMinute: 1140),
              ],
            ),
            WeekdayHours(
              weekday: DateTime.saturday,
              windows: [TimeWindow(startMinute: 480, endMinute: 1080)],
            ),
          ],
          staffingDemands: [
            StaffingDemand(
              weekday: DateTime.monday,
              window: TimeWindow(startMinute: 540, endMinute: 780),
              requiredCount: 2,
              requiredQualificationIds: ['q1', 'q2'],
            ),
          ],
        );

    test('round-trip Firestore (camelCase)', () {
      final original = build();
      final restored = SiteDefinition.fromFirestore(
        'site-1',
        original.toFirestoreMap(),
      );
      expect(restored.weekdayHours, hasLength(2));
      final monday = restored.weekdayHours.first;
      expect(monday.weekday, DateTime.monday);
      expect(monday.windows, hasLength(2));
      expect(monday.windows.first.startMinute, 540);
      expect(monday.windows.first.endMinute, 780);
      expect(restored.staffingDemands, hasLength(1));
      expect(restored.staffingDemands.first.requiredCount, 2);
      expect(
        restored.staffingDemands.first.requiredQualificationIds,
        ['q1', 'q2'],
      );
      expect(restored.staffingDemands.first.window.startMinute, 540);
    });

    test('round-trip lokal (snake_case)', () {
      final original = build();
      final restored = SiteDefinition.fromMap(original.toMap());
      expect(restored.weekdayHours, hasLength(2));
      expect(restored.weekdayHours.last.weekday, DateTime.saturday);
      expect(restored.weekdayHours.last.windows.single.startMinute, 480);
      expect(restored.staffingDemands, hasLength(1));
      expect(restored.staffingDemands.first.weekday, DateTime.monday);
      expect(restored.staffingDemands.first.window.endMinute, 780);
      expect(
        restored.staffingDemands.first.requiredQualificationIds,
        ['q1', 'q2'],
      );
    });

    test('snake_case Keys sind korrekt benannt', () {
      final map = build().toMap();
      expect(map.containsKey('weekday_hours'), isTrue);
      expect(map.containsKey('staffing_demands'), isTrue);
      final demand =
          (map['staffing_demands'] as List).first as Map<String, dynamic>;
      expect(demand['required_count'], 2);
      expect(demand['required_qualification_ids'], ['q1', 'q2']);
      final window = demand['window'] as Map<String, dynamic>;
      expect(window['start_minute'], 540);
      expect(window['end_minute'], 780);
    });

    test('leere Listen bleiben leer in beiden Formaten', () {
      const site = SiteDefinition(orgId: 'org-1', name: 'Leer');
      expect(site.weekdayHours, isEmpty);
      expect(site.staffingDemands, isEmpty);
      expect(
        SiteDefinition.fromMap(site.toMap()).weekdayHours,
        isEmpty,
      );
      expect(
        SiteDefinition.fromFirestore('x', site.toFirestoreMap())
            .staffingDemands,
        isEmpty,
      );
    });

    test('copyWith überschreibt Listen, ohne Adressfelder zu verlieren', () {
      final site = build();
      final updated = site.copyWith(weekdayHours: const []);
      expect(updated.weekdayHours, isEmpty);
      expect(updated.staffingDemands, hasLength(1));
      expect(updated.name, 'Laden');
    });

    test('Altdaten ohne die Felder lesen als leere Listen', () {
      final legacy = {
        'id': 'site-2',
        'org_id': 'org-1',
        'name': 'Alt',
      };
      final site = SiteDefinition.fromMap(legacy);
      expect(site.weekdayHours, isEmpty);
      expect(site.staffingDemands, isEmpty);
      expect(site.thirdPartyCashTypes, isEmpty);
    });
  });

  group('SiteDefinition thirdPartyCashTypes (Fremdgeld-Arten)', () {
    const site = SiteDefinition(
      id: 'site-1',
      orgId: 'org-1',
      name: 'Tabak Börse',
      thirdPartyCashTypes: [
        ThirdPartyCashType(
            id: 'lotto', name: 'Lotto', required: true, sortOrder: 1),
        ThirdPartyCashType(
            id: 'post', name: 'Deutsche Post', enabled: false, sortOrder: 0),
        ThirdPartyCashType(id: 'kvg', name: 'KVG-Tickets', sortOrder: 2),
      ],
    );

    test('Firestore-Roundtrip erhält die Fremdgeld-Arten', () {
      final back =
          SiteDefinition.fromFirestore('site-1', site.toFirestoreMap());
      expect(back.thirdPartyCashTypes.length, 3);
      expect(back.thirdPartyCashTypes.first.id, 'lotto');
      expect(back.thirdPartyCashTypes.first.required, isTrue);
    });

    test('lokaler Roundtrip (snake_case) erhält die Fremdgeld-Arten', () {
      final map = site.toMap();
      expect(map['third_party_cash_types'], isA<List>());
      final back = SiteDefinition.fromMap(map);
      expect(back.thirdPartyCashTypes.length, 3);
      expect(back.thirdPartyCashTypes[2].id, 'kvg');
    });

    test('activeThirdPartyCashTypes filtert deaktivierte + sortiert', () {
      final active = site.activeThirdPartyCashTypes;
      expect(active.map((t) => t.id), ['lotto', 'kvg']); // post deaktiviert
      expect(active.first.sortOrder, 1);
    });

    test('copyWith ersetzt die Liste', () {
      final updated = site.copyWith(thirdPartyCashTypes: const []);
      expect(updated.thirdPartyCashTypes, isEmpty);
      expect(updated.name, 'Tabak Börse');
    });
  });
}
