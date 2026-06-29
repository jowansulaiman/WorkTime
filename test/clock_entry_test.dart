import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/clock_entry.dart';

void main() {
  ClockEntry ongoing() => ClockEntry(
        id: 'c1',
        orgId: 'org-1',
        userId: 'emp-1',
        userName: 'Peter',
        siteId: 'site-1',
        siteName: 'Strichmännchen',
        kommen: DateTime(2026, 6, 10, 9),
      );

  ClockEntry completed() => ClockEntry(
        id: 'c2',
        orgId: 'org-1',
        userId: 'emp-1',
        kommen: DateTime(2026, 6, 10, 9),
        gehen: DateTime(2026, 6, 10, 17),
        pauseMinuten: 45,
        nettoMinutes: 435,
        status: ClockStatus.completed,
        workEntryId: 'e9',
        anmerkung: 'ok',
      );

  group('ClockEntry Defaults & Getter', () {
    test('Default-Status ongoing, isOngoing true, gehen null', () {
      final c = ongoing();
      expect(c.status, ClockStatus.ongoing);
      expect(c.isOngoing, isTrue);
      expect(c.gehen, isNull);
    });

    test('abgeschlossen → isOngoing false', () {
      expect(completed().isOngoing, isFalse);
    });

    test('kommen fehlt/kaputt → FormatException', () {
      expect(() => ClockEntry.fromMap({'org_id': 'org-1'}),
          throwsA(isA<FormatException>()));
    });

    test('negative Pause/Netto werden auf 0 geklemmt', () {
      final c = ClockEntry(
        kommen: DateTime(2026, 6, 10, 9),
        pauseMinuten: -5,
        nettoMinutes: -10,
      );
      expect(c.pauseMinuten, 0);
      expect(c.nettoMinutes, 0);
    });
  });

  group('ClockStatus.fromValue', () {
    test('bekannte Werte', () {
      expect(ClockStatus.fromValue('completed'), ClockStatus.completed);
      expect(ClockStatus.fromValue('deaktiviert'), ClockStatus.deaktiviert);
    });
    test('unbekannt/leer/null → ongoing', () {
      expect(ClockStatus.fromValue('bogus'), ClockStatus.ongoing);
      expect(ClockStatus.fromValue(''), ClockStatus.ongoing);
      expect(ClockStatus.fromValue(null), ClockStatus.ongoing);
    });
  });

  group('Serialisierung', () {
    test('lokale Map round-trippt (snake_case)', () {
      final c = completed();
      final restored = ClockEntry.fromMap(c.toMap());
      expect(restored.id, 'c2');
      expect(restored.status, ClockStatus.completed);
      expect(restored.gehen!.toIso8601String(), c.gehen!.toIso8601String());
      expect(restored.pauseMinuten, 45);
      expect(restored.nettoMinutes, 435);
      expect(restored.workEntryId, 'e9');
      expect(restored.anmerkung, 'ok');
      expect(restored.isOngoing, isFalse);
    });

    test('toFirestoreMap setzt Status/Felder + createdAt nur initial', () {
      final map = ongoing().toFirestoreMap();
      expect(map['status'], 'ongoing');
      expect(map['siteName'], 'Strichmännchen');
      expect(map.containsKey('id'), isFalse); // Doc-ID separat
      expect(map.containsKey('createdAt'), isTrue); // createdAt == null → gesetzt

      // Bestehender createdAt → kein erneutes Setzen.
      final withCreated = ongoing().copyWith(createdAt: DateTime(2026, 1, 1));
      expect(withCreated.toFirestoreMap().containsKey('createdAt'), isFalse);
    });

    test('fromFirestore (camelCase) parst Felder', () {
      final restored = ClockEntry.fromFirestore('c9', {
        'orgId': 'org-1',
        'userId': 'emp-1',
        'kommen': DateTime(2026, 6, 10, 9),
        'gehen': DateTime(2026, 6, 10, 12),
        'pauseMinuten': 0,
        'nettoMinutes': 180,
        'status': 'completed',
        'siteId': 'site-2',
      });
      expect(restored.id, 'c9');
      expect(restored.status, ClockStatus.completed);
      expect(restored.nettoMinutes, 180);
      expect(restored.siteId, 'site-2');
    });
  });

  group('copyWith', () {
    test('Ausstempeln: gehen/netto/status setzen', () {
      final closed = ongoing().copyWith(
        gehen: DateTime(2026, 6, 10, 17),
        pauseMinuten: 30,
        nettoMinutes: 450,
        status: ClockStatus.completed,
        workEntryId: 'e1',
      );
      expect(closed.isOngoing, isFalse);
      expect(closed.gehen, isNotNull);
      expect(closed.workEntryId, 'e1');
    });

    test('clearGehen leert das Gehen', () {
      final reopened = completed().copyWith(
        clearGehen: true,
        status: ClockStatus.ongoing,
      );
      expect(reopened.gehen, isNull);
      expect(reopened.isOngoing, isTrue);
    });
  });
}
