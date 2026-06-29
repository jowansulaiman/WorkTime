import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/monatsabschluss_service.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/zeitkonto_snapshot.dart';

void main() {
  const service = MonatsabschlussService();
  // Fester „Jetzt"-Zeitpunkt: Juni/2026 ist damit ein vollständig vergangener
  // Monat und blockiert nicht über die Zukunfts-Prüfung.
  final now = DateTime(2026, 7, 1);

  ZeitkontoSnapshot snap({
    int jahr = 2026,
    int monat = 6,
    int sollMinutes = 9600,
    int istMinutes = 9600,
    int kranktage = 0,
    bool abgeschlossen = false,
  }) {
    return ZeitkontoSnapshot(
      orgId: 'org-1',
      userId: 'u1',
      jahr: jahr,
      monat: monat,
      sollMinutes: sollMinutes,
      istMinutes: istMinutes,
      ueberstundenMinutes: istMinutes - sollMinutes,
      saldoMinutes: istMinutes - sollMinutes,
      kranktage: kranktage,
      abgeschlossen: abgeschlossen,
    );
  }

  WorkEntry entry(WorkEntryStatus status) {
    final d = DateTime(2026, 6, 10);
    return WorkEntry(
      id: 'e-${status.name}',
      orgId: 'org-1',
      userId: 'u1',
      date: d,
      startTime: DateTime(2026, 6, 10, 8),
      endTime: DateTime(2026, 6, 10, 16),
      status: status,
    );
  }

  group('validate', () {
    test('schließbar bei allen genehmigten Einträgen und keinem Vormonat', () {
      final v = service.validate(
        snapshot: snap(),
        entries: [entry(WorkEntryStatus.approved)],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isTrue);
      expect(v.errors, isEmpty);
    });

    test('rejected zählt als entschieden (blockiert NICHT)', () {
      final v = service.validate(
        snapshot: snap(),
        entries: [entry(WorkEntryStatus.approved), entry(WorkEntryStatus.rejected)],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isTrue);
    });

    test('offene Einträge (draft/submitted) blockieren', () {
      final v = service.validate(
        snapshot: snap(),
        entries: [entry(WorkEntryStatus.submitted), entry(WorkEntryStatus.draft)],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isFalse);
      expect(v.errors.any((e) => e.contains('genehmigt')), isTrue);
    });

    test('bereits abgeschlossen blockiert', () {
      final v = service.validate(
        snapshot: snap(abgeschlossen: true),
        entries: const [],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isFalse);
      expect(v.errors.first, contains('bereits abgeschlossen'));
    });

    test('laufender Monat blockiert (noch nicht vorbei)', () {
      final v = service.validate(
        snapshot: snap(monat: 7),
        entries: const [],
        vormonat: null,
        now: DateTime(2026, 7, 15),
      );
      expect(v.canClose, isFalse);
      expect(v.errors.any((e) => e.contains('noch nicht vollständig vorbei')),
          isTrue);
    });

    test('zukünftiger Monat blockiert', () {
      final v = service.validate(
        snapshot: snap(monat: 9),
        entries: const [],
        vormonat: null,
        now: DateTime(2026, 7, 15),
      );
      expect(v.canClose, isFalse);
    });

    test('offener Vormonat-Snapshot blockiert', () {
      final v = service.validate(
        snapshot: snap(monat: 6),
        entries: const [],
        vormonat: snap(monat: 5, abgeschlossen: false),
        now: now,
      );
      expect(v.canClose, isFalse);
      expect(v.errors.any((e) => e.contains('Vormonat')), isTrue);
    });

    test('abgeschlossener Vormonat blockiert nicht', () {
      final v = service.validate(
        snapshot: snap(monat: 6),
        entries: const [],
        vormonat: snap(monat: 5, abgeschlossen: true),
        now: now,
      );
      expect(v.canClose, isTrue);
    });

    test('fehlender Vormonats-Snapshot ist kein Blocker', () {
      final v = service.validate(
        snapshot: snap(monat: 1),
        entries: const [],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isTrue);
    });

    test('Warnung: kein Ist trotz Soll (nicht blockierend)', () {
      final v = service.validate(
        snapshot: snap(istMinutes: 0),
        entries: const [],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isTrue);
      expect(v.warnings.any((w) => w.contains('Keine Ist-Stunden')), isTrue);
    });

    test('Warnung: viele Kranktage (nicht blockierend)', () {
      final v = service.validate(
        snapshot: snap(kranktage: 21),
        entries: const [],
        vormonat: null,
        now: now,
      );
      expect(v.canClose, isTrue);
      expect(v.warnings.any((w) => w.contains('Krankheitstage')), isTrue);
    });
  });

  group('applyLock / applyUnlock', () {
    test('applyLock setzt abgeschlossen + Akteur + Zeitpunkt', () {
      final am = DateTime(2026, 7, 1, 9, 30);
      final locked = service.applyLock(snap(), von: 'admin-1', am: am);
      expect(locked.abgeschlossen, isTrue);
      expect(locked.abgeschlossenVon, 'admin-1');
      expect(locked.abgeschlossenAm, am);
    });

    test('applyUnlock entfernt Sperre + Akteur + Zeitpunkt', () {
      final locked = service.applyLock(snap(), von: 'admin-1', am: DateTime(2026, 7, 1));
      final unlocked = service.applyUnlock(locked);
      expect(unlocked.abgeschlossen, isFalse);
      expect(unlocked.abgeschlossenVon, isNull);
      expect(unlocked.abgeschlossenAm, isNull);
    });
  });
}
