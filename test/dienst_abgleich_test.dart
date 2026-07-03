import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/dienst_abgleich.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/clock_entry.dart';
import 'package:worktime_app/models/shift.dart';

void main() {
  final tag = DateTime(2026, 6, 10); // Mittwoch

  Shift schicht(
    String id,
    String uid, {
    int startStunde = 8,
    int stunden = 6,
    String siteId = 'site-1',
    ShiftStatus status = ShiftStatus.planned,
  }) {
    final start = DateTime(tag.year, tag.month, tag.day, startStunde);
    return Shift(
      id: id,
      orgId: 'org-1',
      userId: uid,
      employeeName: 'MA $uid',
      title: 'Laden',
      startTime: start,
      endTime: start.add(Duration(hours: stunden)),
      siteId: siteId,
      siteName: 'Strichmännchen',
      status: status,
    );
  }

  ClockEntry stempel(
    String id,
    String uid, {
    required int kommenStunde,
    int? kommenMinute,
    int? gehenStunde,
    String? shiftId,
    String siteId = 'site-1',
    ClockStatus status = ClockStatus.completed,
  }) {
    return ClockEntry(
      id: id,
      orgId: 'org-1',
      userId: uid,
      userName: 'MA $uid',
      kommen: DateTime(tag.year, tag.month, tag.day, kommenStunde,
          kommenMinute ?? 0),
      gehen: gehenStunde == null
          ? null
          : DateTime(tag.year, tag.month, tag.day, gehenStunde),
      status: status,
      shiftId: shiftId,
      siteId: siteId,
    );
  }

  AbsenceRequest abwesenheit(
    String uid, {
    DateTime? von,
    DateTime? bis,
    AbsenceStatus status = AbsenceStatus.approved,
  }) {
    return AbsenceRequest(
      orgId: 'org-1',
      userId: uid,
      employeeName: 'MA $uid',
      startDate: von ?? tag,
      endDate: bis ?? tag,
      type: AbsenceType.vacation,
      status: status,
    );
  }

  // now = deutlich nach allen Schichtenden, damit Fälligkeit greift.
  final now = DateTime(tag.year, tag.month, tag.day, 20);

  group('DienstAbgleichService.berechne — Grundfälle', () {
    test('pünktlich: Kommen im Karenzfenster', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8, stunden: 6)],
        stempel: [stempel('c1', 'a', kommenStunde: 8, gehenStunde: 14)],
        abwesenheiten: const [],
        now: now,
      );
      expect(r, hasLength(1));
      expect(r.single.status, DienstStatus.puenktlich);
      expect(r.single.abweichungMinuten, 0);
      expect(r.single.shiftId, 's1');
      expect(r.single.clockEntryId, 'c1');
    });

    test('verspätet: Kommen nach Karenz → Minuten', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8)],
        stempel: [
          stempel('c1', 'a', kommenStunde: 8, kommenMinute: 20, gehenStunde: 14)
        ],
        abwesenheiten: const [],
        now: now,
        karenzMinuten: 5,
      );
      expect(r.single.status, DienstStatus.verspaetet);
      expect(r.single.abweichungMinuten, 20);
    });

    test('nicht erschienen: kein Stempel, keine Abwesenheit, Schicht vorbei', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8)],
        stempel: const [],
        abwesenheiten: const [],
        now: now,
      );
      expect(r.single.status, DienstStatus.nichtErschienen);
    });

    test('früher gegangen: Gehen vor Schichtende → Minuten', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8, stunden: 6)], // Ende 14
        stempel: [stempel('c1', 'a', kommenStunde: 8, gehenStunde: 13)], // -60
        abwesenheiten: const [],
        now: now,
      );
      expect(r.single.status, DienstStatus.frueherGegangen);
      expect(r.single.abweichungMinuten, 60);
    });

    test('entschuldigt: genehmigte Abwesenheit deckt die Schicht', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8)],
        stempel: const [],
        abwesenheiten: [abwesenheit('a')],
        now: now,
      );
      expect(r.single.status, DienstStatus.abwesendEntschuldigt);
    });

    test('offen: Schicht liegt noch in der Zukunft', () {
      final vormittag = DateTime(tag.year, tag.month, tag.day, 6);
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8)],
        stempel: const [],
        abwesenheiten: const [],
        now: vormittag,
      );
      expect(r.single.status, DienstStatus.offen);
    });

    test('ungeplant anwesend: Stempel ohne passende Schicht', () {
      final r = DienstAbgleichService.berechne(
        schichten: const [],
        stempel: [stempel('c1', 'a', kommenStunde: 10, gehenStunde: 12)],
        abwesenheiten: const [],
        now: now,
      );
      expect(r.single.status, DienstStatus.ungeplantAnwesend);
      expect(r.single.shiftId, isNull);
      expect(r.single.clockEntryId, 'c1');
    });
  });

  group('DienstAbgleichService.berechne — Zuordnung & Kanten', () {
    test('harte shiftId-Verknüpfung schlägt zeitliche Nähe', () {
      // Zwei Schichten; Stempel trägt shiftId der SPÄTEREN Schicht, obwohl er
      // zeitlich näher an der früheren liegt.
      final r = DienstAbgleichService.berechne(
        schichten: [
          schicht('frueh', 'a', startStunde: 8, stunden: 4), // 8–12
          schicht('spaet', 'a', startStunde: 14, stunden: 4), // 14–18
        ],
        stempel: [
          stempel('c1', 'a',
              kommenStunde: 9, gehenStunde: 12, shiftId: 'spaet'),
        ],
        abwesenheiten: const [],
        now: now,
      );
      final spaet = r.firstWhere((e) => e.shiftId == 'spaet');
      final frueh = r.firstWhere((e) => e.shiftId == 'frueh');
      expect(spaet.clockEntryId, 'c1'); // hart zugeordnet
      expect(frueh.status, DienstStatus.nichtErschienen); // bleibt unbesetzt
    });

    test('zwei Schichten, zwei Stempel: nächste Zuordnung je Schicht', () {
      final r = DienstAbgleichService.berechne(
        schichten: [
          schicht('frueh', 'a', startStunde: 8, stunden: 4), // 8–12
          schicht('spaet', 'a', startStunde: 14, stunden: 4), // 14–18
        ],
        stempel: [
          stempel('c1', 'a', kommenStunde: 8, gehenStunde: 12),
          stempel('c2', 'a', kommenStunde: 14, gehenStunde: 18),
        ],
        abwesenheiten: const [],
        now: now,
      );
      expect(r.firstWhere((e) => e.shiftId == 'frueh').clockEntryId, 'c1');
      expect(r.firstWhere((e) => e.shiftId == 'spaet').clockEntryId, 'c2');
      expect(r.every((e) => e.status == DienstStatus.puenktlich), isTrue);
    });

    test('Über-Mitternacht-Schicht: Gehen am Folgetag zählt nicht als früher', () {
      final start = DateTime(tag.year, tag.month, tag.day, 22);
      final nacht = Shift(
        id: 'n1',
        orgId: 'org-1',
        userId: 'a',
        employeeName: 'MA a',
        title: 'Nacht',
        startTime: start,
        endTime: start.add(const Duration(hours: 8)), // 06:00 Folgetag
        siteId: 'site-1',
        siteName: 'Strichmännchen',
      );
      final ein = ClockEntry(
        id: 'c1',
        orgId: 'org-1',
        userId: 'a',
        kommen: start, // 22:00
        gehen: start.add(const Duration(hours: 8)), // 06:00 Folgetag
        status: ClockStatus.completed,
      );
      final r = DienstAbgleichService.berechne(
        schichten: [nacht],
        stempel: [ein],
        abwesenheiten: const [],
        now: start.add(const Duration(hours: 9)),
      );
      expect(r.single.status, DienstStatus.puenktlich);
    });

    test('abgesagte Schicht + deaktivierter Stempel werden ignoriert', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', status: ShiftStatus.cancelled)],
        stempel: [
          stempel('c1', 'a',
              kommenStunde: 8, gehenStunde: 14, status: ClockStatus.deaktiviert)
        ],
        abwesenheiten: const [],
        now: now,
      );
      expect(r, isEmpty);
    });

    test('Zuordnung mischt sich nicht über Mitarbeiter', () {
      final r = DienstAbgleichService.berechne(
        schichten: [
          schicht('sa', 'a', startStunde: 8),
          schicht('sb', 'b', startStunde: 8),
        ],
        stempel: [
          // Nur A stempelt; B fehlt.
          stempel('c1', 'a', kommenStunde: 8, gehenStunde: 14),
        ],
        abwesenheiten: const [],
        now: now,
      );
      expect(r.firstWhere((e) => e.userId == 'a').status,
          DienstStatus.puenktlich);
      expect(r.firstWhere((e) => e.userId == 'b').status,
          DienstStatus.nichtErschienen);
    });

    test('nur ausstehende (nicht genehmigte) Abwesenheit deckt NICHT', () {
      final r = DienstAbgleichService.berechne(
        schichten: [schicht('s1', 'a', startStunde: 8)],
        stempel: const [],
        abwesenheiten: [abwesenheit('a', status: AbsenceStatus.pending)],
        now: now,
      );
      expect(r.single.status, DienstStatus.nichtErschienen);
    });

    test('Ergebnis ist stabil nach Schichtbeginn sortiert', () {
      final r = DienstAbgleichService.berechne(
        schichten: [
          schicht('spaet', 'a', startStunde: 16),
          schicht('frueh', 'b', startStunde: 8),
        ],
        stempel: const [],
        abwesenheiten: const [],
        now: now,
      );
      expect(r.first.shiftId, 'frueh');
      expect(r.last.shiftId, 'spaet');
    });
  });
}
