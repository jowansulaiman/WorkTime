import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/zeitkonto_snapshot_builder.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';

void main() {
  // Mo–Fr je 8 h (480 min), Sa/So 0; zusätzlich festes Monatssoll 9000 (150 h).
  SollzeitProfile profile() => SollzeitProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        gueltigAb: DateTime(2025, 1, 1),
        montagMinutes: 480,
        dienstagMinutes: 480,
        mittwochMinutes: 480,
        donnerstagMinutes: 480,
        freitagMinutes: 480,
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 9000,
      );

  AbsenceRequest absence({
    required AbsenceType type,
    required DateTime start,
    required DateTime end,
    bool halfDay = false,
    double? hours,
    AbsenceStatus status = AbsenceStatus.approved,
  }) =>
      AbsenceRequest(
        orgId: 'org-1',
        userId: 'emp-1',
        employeeName: 'Peter',
        startDate: start,
        endDate: end,
        type: type,
        status: status,
        halfDay: halfDay,
        hours: hours,
      );

  group('ZeitkontoSnapshot Serialisierung', () {
    test('buildId ist deterministisch {userId}-{jahr}-{mm}', () {
      expect(ZeitkontoSnapshot.buildId('emp-1', 2026, 6), 'emp-1-2026-06');
    });

    test('lokale Map round-trippt', () {
      final snap = ZeitkontoSnapshot(
        id: 's1',
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        sollMinutes: 9000,
        istMinutes: 9120,
        ueberstundenMinutes: 120,
        uebertragMinutes: 600,
        saldoMinutes: 720,
        urlaubstageGesamt: 30,
        urlaubstageGenommen: 5,
        urlaubstageRest: 25,
        kranktage: 2,
        abgeschlossen: true,
        abgeschlossenVon: 'adm-1',
        abgeschlossenAm: DateTime(2026, 7, 1, 9),
      );
      final restored = ZeitkontoSnapshot.fromMap(snap.toMap());
      expect(restored.saldoMinutes, 720);
      expect(restored.uebertragMinutes, 600);
      expect(restored.urlaubstageRest, 25);
      expect(restored.kranktage, 2);
      expect(restored.abgeschlossen, isTrue);
      expect(restored.abgeschlossenVon, 'adm-1');
      expect(restored.abgeschlossenAm!.toIso8601String(),
          snap.abgeschlossenAm!.toIso8601String());
    });

    test('toFirestoreMap: createdAt nur initial, Doc-ID separat', () {
      final map = ZeitkontoSnapshot(jahr: 2026, monat: 6).toFirestoreMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('createdAt'), isTrue);
      final withCreated = ZeitkontoSnapshot(jahr: 2026, monat: 6)
          .copyWith(createdAt: DateTime(2026, 1, 1));
      expect(withCreated.toFirestoreMap().containsKey('createdAt'), isFalse);
    });
  });

  group('anrechenbareAbwesenheitsMinutes', () {
    test('7-Tage-Urlaub = genau 5 Werktage × 480 = 2400', () {
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(minutes, 2400);
    });

    test('halbtägig → halbes Tagessoll (5 × 240 = 1200)', () {
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
            halfDay: true,
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(minutes, 1200);
    });

    test('unbezahlter Urlaub wird NICHT angerechnet', () {
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.unpaidLeave,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(minutes, 0);
    });

    test('nicht genehmigte Abwesenheit zählt nicht', () {
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
            status: AbsenceStatus.pending,
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(minutes, 0);
    });

    test('EFZG: Krankheit > 42 Kalendertage wird gekappt (Folgemonat)', () {
      // Krankheit ab 05.01.2026 → EFZG-Fenster 05.01.–15.02.2026 (42 Tage).
      // Februar-Aufruf: nur Arbeitstage bis 15.02. zählen (Mo–Fr 02.–06. + 09.–13.
      // = 10 Arbeitstage × 480 = 4800), 16.–28.02. fallen aus der Anrechnung.
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.sickness,
            start: DateTime(2026, 1, 5),
            end: DateTime(2026, 3, 31),
          ),
        ],
        jahr: 2026,
        monat: 2,
      );
      expect(minutes, 4800);
    });

    test('EFZG: Urlaub wird NICHT gekappt (nur Krankheit)', () {
      // Gleiche Dauer wie oben, aber Urlaub → alle 20 Februar-Arbeitstage zählen.
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 1, 5),
            end: DateTime(2026, 3, 31),
          ),
        ],
        jahr: 2026,
        monat: 2,
      );
      expect(minutes, 9600);
    });

    test('EFZG: Krankheit innerhalb 42 Tagen voll angerechnet', () {
      // Kurze Krankheit Mo–Fr (5 Arbeitstage) → voll (5 × 480 = 2400).
      final minutes = anrechenbareAbwesenheitsMinutes(
        profiles: [profile()],
        absences: [
          absence(
            type: AbsenceType.sickness,
            start: DateTime(2026, 2, 2),
            end: DateTime(2026, 2, 6),
          ),
        ],
        jahr: 2026,
        monat: 2,
      );
      expect(minutes, 2400);
    });
  });

  group('krankTageImMonat', () {
    test('Krankheit 7 Tage → 7 Kalendertage', () {
      final days = krankTageImMonat(
        absences: [
          absence(
            type: AbsenceType.sickness,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(days, 7);
    });

    test('Urlaub zählt nicht als Kranktag', () {
      final days = krankTageImMonat(
        absences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
          ),
        ],
        jahr: 2026,
        monat: 6,
      );
      expect(days, 0);
    });
  });

  group('buildZeitkontoSnapshot (Übertrag + Anrechnung + Auszahlung)', () {
    test('Saldo = Übertrag + (Ist+Anrechnung − Soll) − Auszahlung', () {
      final entries = [
        WorkEntry(
          orgId: 'org-1',
          userId: 'emp-1',
          date: DateTime(2026, 6, 2),
          startTime: DateTime(2026, 6, 2, 8),
          endTime: DateTime(2026, 6, 2, 16),
        ),
        WorkEntry(
          orgId: 'org-1',
          userId: 'emp-1',
          date: DateTime(2026, 6, 3),
          startTime: DateTime(2026, 6, 3, 8),
          endTime: DateTime(2026, 6, 3, 16),
        ),
      ]; // 2 × 480 = 960 Ist aus Einträgen
      final previous = ZeitkontoSnapshot(jahr: 2026, monat: 5, saldoMinutes: 600);

      final snap = buildZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        profiles: [profile()],
        entries: entries,
        approvedAbsences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 7),
          ), // +2400 Anrechnung
        ],
        previous: previous,
        ausgezahltMinutes: 120,
        urlaubstageGesamt: 30,
        urlaubstageGenommen: 5,
      );

      expect(snap.sollMinutes, 9000);
      expect(snap.istMinutes, 960 + 2400); // 3360
      expect(snap.ueberstundenMinutes, 3360 - 9000); // -5640
      expect(snap.uebertragMinutes, 600);
      expect(snap.saldoMinutes, 600 + (3360 - 9000) - 120); // -5160
      expect(snap.urlaubstageRest, 25);
      expect(snap.ausgezahltMinutes, 120);
    });

    test('ohne Vormonat → Übertrag 0', () {
      final snap = buildZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        profiles: [profile()],
        entries: const [],
        approvedAbsences: const [],
      );
      expect(snap.uebertragMinutes, 0);
      expect(snap.istMinutes, 0);
      expect(snap.saldoMinutes, snap.ueberstundenMinutes);
    });
  });

  group('Zeitausgleich senkt den Saldo (Befund #15: abfeiern)', () {
    // 15.06.2026 ist ein Montag (Tagessoll 480).
    test('voller Zeitausgleichstag: Ist bleibt gutgeschrieben, Saldo sinkt um 480',
        () {
      final entries = [
        WorkEntry(
          orgId: 'org-1',
          userId: 'emp-1',
          date: DateTime(2026, 6, 2),
          startTime: DateTime(2026, 6, 2, 8),
          endTime: DateTime(2026, 6, 2, 16),
        ),
        WorkEntry(
          orgId: 'org-1',
          userId: 'emp-1',
          date: DateTime(2026, 6, 3),
          startTime: DateTime(2026, 6, 3, 8),
          endTime: DateTime(2026, 6, 3, 16),
        ),
      ]; // 960 Ist aus Einträgen
      final previous =
          ZeitkontoSnapshot(jahr: 2026, monat: 5, saldoMinutes: 600);

      final snap = buildZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        profiles: [profile()],
        entries: entries,
        approvedAbsences: [
          absence(
            type: AbsenceType.timeOff,
            start: DateTime(2026, 6, 15),
            end: DateTime(2026, 6, 15),
            hours: 8, // informeller Wert; Saldo folgt dem Tagessoll
          ),
        ],
        previous: previous,
      );

      // Ist (= Lohn-Grundlage) enthält die Zeitausgleichs-Gutschrift WEITERHIN.
      expect(snap.istMinutes, 960 + 480);
      // Die frühere (fehlerhafte) Saldo-Formel ohne Zeitausgleichs-Abzug:
      final saldoOhneAbzug = snap.uebertragMinutes +
          snap.ueberstundenMinutes -
          snap.ausgezahltMinutes;
      // Der Saldo ist jetzt um genau das abgefeierte Tagessoll (480) niedriger.
      expect(snap.saldoMinutes, saldoOhneAbzug - 480);
    });

    test('halbtägiger Zeitausgleich zieht halbes Tagessoll (240) ab', () {
      final snap = buildZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        profiles: [profile()],
        entries: const [],
        approvedAbsences: [
          absence(
            type: AbsenceType.timeOff,
            start: DateTime(2026, 6, 15),
            end: DateTime(2026, 6, 15),
            halfDay: true,
            hours: 4,
          ),
        ],
      );
      final saldoOhneAbzug = snap.uebertragMinutes +
          snap.ueberstundenMinutes -
          snap.ausgezahltMinutes;
      expect(snap.saldoMinutes, saldoOhneAbzug - 240);
    });

    test('Urlaub senkt den Saldo NICHT (nur Zeitausgleich)', () {
      final snap = buildZeitkontoSnapshot(
        orgId: 'org-1',
        userId: 'emp-1',
        jahr: 2026,
        monat: 6,
        profiles: [profile()],
        entries: const [],
        approvedAbsences: [
          absence(
            type: AbsenceType.vacation,
            start: DateTime(2026, 6, 15),
            end: DateTime(2026, 6, 15),
          ),
        ],
      );
      final saldoOhneAbzug = snap.uebertragMinutes +
          snap.ueberstundenMinutes -
          snap.ausgezahltMinutes;
      expect(snap.saldoMinutes, saldoOhneAbzug); // kein Abzug für Urlaub
    });
  });
}
