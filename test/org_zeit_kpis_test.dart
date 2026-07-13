import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/org_zeit_kpis.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';

void main() {
  // Festes Monatssoll 9000 min (150 h) je Mitglied.
  SollzeitProfile profile(String userId) => SollzeitProfile(
        orgId: 'org-1',
        userId: userId,
        gueltigAb: DateTime(2025, 1, 1),
        montagMinutes: 480,
        dienstagMinutes: 480,
        mittwochMinutes: 480,
        donnerstagMinutes: 480,
        freitagMinutes: 480,
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 9000,
      );

  WorkEntry entry(
    String userId,
    int day, {
    WorkEntryStatus status = WorkEntryStatus.approved,
  }) =>
      WorkEntry(
        orgId: 'org-1',
        userId: userId,
        date: DateTime(2026, 6, day),
        startTime: DateTime(2026, 6, day, 8),
        endTime: DateTime(2026, 6, day, 16), // 480 min
        status: status,
      );

  group('computeOrgZeitKpis (REPORTING-2)', () {
    test('summiert Soll/Ist/mitarbeiterMitSoll über die Mitglieder', () {
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a', 'b'],
        profilesByUser: {
          'a': [profile('a')],
          'b': [profile('b')],
        },
        entries: [
          entry('a', 2),
          entry('a', 3), // a: 960 approved
          entry('b', 2), // b: 480 approved
        ],
        approvedAbsences: const [],
        currentMonthSnapshots: const [],
      );
      expect(kpis.sollMinutes, 18000); // 2 × 9000
      expect(kpis.istMinutes, 1440); // 960 + 480 (nur approved)
      expect(kpis.mitarbeiterMitSoll, 2);
    });

    test('E3: submitted/draft zählen NICHT ins Ist, nur als separate Zähler', () {
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a'],
        profilesByUser: {
          'a': [profile('a')],
        },
        entries: [
          entry('a', 2), // approved → Ist
          entry('a', 3, status: WorkEntryStatus.submitted),
          entry('a', 4, status: WorkEntryStatus.submitted),
          entry('a', 5, status: WorkEntryStatus.draft),
        ],
        approvedAbsences: const [],
        currentMonthSnapshots: const [],
      );
      expect(kpis.istMinutes, 480); // nur der approved-Eintrag
      expect(kpis.offeneFreigaben, 2); // submitted
      expect(kpis.offeneEntwuerfe, 1); // draft
    });

    test('Zähler ignorieren Einträge außerhalb des Zielmonats', () {
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a'],
        profilesByUser: {
          'a': [profile('a')],
        },
        entries: [
          WorkEntry(
            orgId: 'org-1',
            userId: 'a',
            date: DateTime(2026, 5, 20),
            startTime: DateTime(2026, 5, 20, 8),
            endTime: DateTime(2026, 5, 20, 16),
            status: WorkEntryStatus.submitted,
          ),
        ],
        approvedAbsences: const [],
        currentMonthSnapshots: const [],
      );
      expect(kpis.offeneFreigaben, 0);
    });

    test('Snapshot-Konsistenz: festgeschriebener Monat gewinnt gegen Live', () {
      // Live würde für 'a' 480 Ist ergeben; der persistierte abgeschlossene
      // Snapshot trägt 9999 → der Report muss dem Abschluss folgen.
      final locked = ZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'a',
        jahr: 2026,
        monat: 6,
        sollMinutes: 9000,
        istMinutes: 9999,
        saldoMinutes: 999,
        abgeschlossen: true,
      );
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a'],
        profilesByUser: {
          'a': [profile('a')],
        },
        entries: [entry('a', 2)],
        approvedAbsences: const [],
        currentMonthSnapshots: [locked],
      );
      expect(kpis.istMinutes, 9999);
      expect(kpis.saldoMinutes, 999);
      expect(kpis.sollMinutes, 9000);
    });

    test('offener persistierter Snapshot: ausgezahltMinutes senkt Live-Saldo',
        () {
      final offen = ZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'a',
        jahr: 2026,
        monat: 6,
        ausgezahltMinutes: 120,
        // abgeschlossen == false → Live-Berechnung, aber Auszahlung fließt ein.
      );
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a'],
        profilesByUser: {
          'a': [profile('a')],
        },
        entries: [entry('a', 2)], // 480 Ist, Soll 9000 → Überstunden -8520
        approvedAbsences: const [],
        currentMonthSnapshots: [offen],
      );
      // Saldo = 0 (kein Übertrag) + (480 − 9000) − 120 = -8640
      expect(kpis.istMinutes, 480);
      expect(kpis.saldoMinutes, (480 - 9000) - 120);
    });

    test('Mitglied ohne Soll zählt nicht in mitarbeiterMitSoll', () {
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a', 'b'],
        profilesByUser: {
          'a': [profile('a')],
          // 'b' hat kein Sollzeit-Profil
        },
        entries: const [],
        approvedAbsences: const [],
        currentMonthSnapshots: const [],
      );
      expect(kpis.mitarbeiterMitSoll, 1);
      expect(kpis.sollMinutes, 9000);
    });

    test('doppelte memberIds werden nur einmal gezählt', () {
      final kpis = computeOrgZeitKpis(
        orgId: 'org-1',
        jahr: 2026,
        monat: 6,
        memberIds: ['a', 'a'],
        profilesByUser: {
          'a': [profile('a')],
        },
        entries: const [],
        approvedAbsences: const [],
        currentMonthSnapshots: const [],
      );
      expect(kpis.mitarbeiterMitSoll, 1);
      expect(kpis.sollMinutes, 9000);
    });
  });
}
