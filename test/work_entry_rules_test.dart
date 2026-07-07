import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/work_entry_rules.dart';
import 'package:worktime_app/models/shift.dart';
import 'package:worktime_app/models/work_entry.dart';

WorkEntry _entry({
  WorkEntryStatus status = WorkEntryStatus.approved,
  DateTime? start,
  DateTime? end,
  double breakMinutes = 30,
  String? siteId = 'site-1',
}) {
  final s = start ?? DateTime(2026, 6, 10, 9);
  return WorkEntry(
    id: 'e1',
    orgId: 'org-1',
    userId: 'emp-1',
    date: DateTime(2026, 6, 10),
    startTime: s,
    endTime: end ?? DateTime(2026, 6, 10, 17),
    breakMinutes: breakMinutes,
    siteId: siteId,
    status: status,
  );
}

void main() {
  group('countsAsIst (E3 – strenge Zählung)', () {
    test('nur approved zählt ins bindende Ist', () {
      expect(countsAsIst(_entry(status: WorkEntryStatus.approved)), isTrue);
      expect(countsAsIst(_entry(status: WorkEntryStatus.submitted)), isFalse);
      expect(countsAsIst(_entry(status: WorkEntryStatus.draft)), isFalse);
      expect(countsAsIst(_entry(status: WorkEntryStatus.rejected)), isFalse);
    });

    test('Alt-Eintrag ohne status parst als approved → zählt (abwärtskompat.)',
        () {
      // fromFirestore ohne 'status' → Default approved.
      final legacy = WorkEntry.fromFirestore('e9', {
        'orgId': 'org-1',
        'userId': 'emp-1',
        'date': DateTime(2026, 6, 10),
        'startTime': DateTime(2026, 6, 10, 9),
        'endTime': DateTime(2026, 6, 10, 17),
        'breakMinutes': 0,
      });
      expect(legacy.status, WorkEntryStatus.approved);
      expect(countsAsIst(legacy), isTrue);
    });
  });

  group('isVorlaeufig', () {
    test('submitted und draft sind vorläufig, approved/rejected nicht', () {
      expect(isVorlaeufig(_entry(status: WorkEntryStatus.submitted)), isTrue);
      expect(isVorlaeufig(_entry(status: WorkEntryStatus.draft)), isTrue);
      expect(isVorlaeufig(_entry(status: WorkEntryStatus.approved)), isFalse);
      expect(isVorlaeufig(_entry(status: WorkEntryStatus.rejected)), isFalse);
    });
  });

  group('isMaterialWorkEntryChange (Material-Feld-Set)', () {
    test('identischer Eintrag → keine Material-Änderung', () {
      expect(isMaterialWorkEntryChange(_entry(), _entry()), isFalse);
    });

    test('startTime/endTime/breakMinutes/siteId lösen aus', () {
      final base = _entry();
      expect(
        isMaterialWorkEntryChange(
            base, _entry(start: DateTime(2026, 6, 10, 8))),
        isTrue,
      );
      expect(
        isMaterialWorkEntryChange(
            base, _entry(end: DateTime(2026, 6, 10, 18))),
        isTrue,
      );
      expect(
        isMaterialWorkEntryChange(base, _entry(breakMinutes: 45)),
        isTrue,
      );
      expect(
        isMaterialWorkEntryChange(base, _entry(siteId: 'site-2')),
        isTrue,
      );
    });

    test('note/category/status/date sind NICHT im Material-Set', () {
      final base = _entry(status: WorkEntryStatus.approved);
      final onlyStatus = _entry(status: WorkEntryStatus.submitted);
      expect(isMaterialWorkEntryChange(base, onlyStatus), isFalse);
    });

    test('breakMinutes wird auf ganze Minuten gerundet verglichen', () {
      expect(
        isMaterialWorkEntryChange(
            _entry(breakMinutes: 30.2), _entry(breakMinutes: 30.4)),
        isFalse,
      );
      expect(
        isMaterialWorkEntryChange(
            _entry(breakMinutes: 30.2), _entry(breakMinutes: 31.4)),
        isTrue,
      );
    });

    test('siteId leer == null (normalisiert)', () {
      expect(
        isMaterialWorkEntryChange(_entry(siteId: null), _entry(siteId: '  ')),
        isFalse,
      );
      expect(
        isMaterialWorkEntryChange(_entry(siteId: null), _entry(siteId: 'x')),
        isTrue,
      );
    });
  });

  group('applyOwnEntrySubmissionPolicy (Z2/Z4)', () {
    test('Nicht-Admin: approved-Erfassung wird submitted, Freigabe geleert', () {
      final input = _entry(status: WorkEntryStatus.approved).copyWith(
        approvedByUid: 'adm-1',
        approvedAt: DateTime(2026, 6, 10, 14),
      );
      final out = applyOwnEntrySubmissionPolicy(input, isAdmin: false);
      expect(out.status, WorkEntryStatus.submitted);
      expect(out.approvedByUid, isNull);
      expect(out.approvedAt, isNull);
    });

    test('Nicht-Admin: Korrektur eines genehmigten Eintrags → submitted (Z4)', () {
      final approved = _entry(status: WorkEntryStatus.approved).copyWith(
        approvedByUid: 'adm-1',
        approvedAt: DateTime(2026, 6, 10, 14),
      );
      final out = applyOwnEntrySubmissionPolicy(approved, isAdmin: false);
      expect(out.status, WorkEntryStatus.submitted);
      expect(out.approvedByUid, isNull);
    });

    test('Nicht-Admin: bereits sauber submitted bleibt unverändert (idempotent)',
        () {
      final input = _entry(status: WorkEntryStatus.submitted);
      final out = applyOwnEntrySubmissionPolicy(input, isAdmin: false);
      expect(identical(out, input), isTrue);
    });

    test('Admin: approved-Erfassung bleibt approved (ausgenommen)', () {
      final input = _entry(status: WorkEntryStatus.approved);
      final out = applyOwnEntrySubmissionPolicy(input, isAdmin: true);
      expect(out.status, WorkEntryStatus.approved);
    });
  });

  group('isEligibleForBulkApproval (E4/Z7)', () {
    WorkEntry stampEntry({
      WorkEntryStatus status = WorkEntryStatus.submitted,
      String? sourceShiftId = 's1',
      String? sourceClockEntryId = 'c1',
      String? correctionReason,
      DateTime? start,
      DateTime? end,
    }) =>
        WorkEntry(
          id: 'e1',
          orgId: 'org-1',
          userId: 'emp-1',
          date: DateTime(2026, 6, 10),
          startTime: start ?? DateTime(2026, 6, 10, 9),
          endTime: end ?? DateTime(2026, 6, 10, 17),
          status: status,
          sourceShiftId: sourceShiftId,
          sourceClockEntryId: sourceClockEntryId,
          correctionReason: correctionReason,
        );

    test('schicht-konformer Stempel-Eintrag ist sammel-freigabefähig', () {
      expect(isEligibleForBulkApproval(stampEntry()), isTrue);
    });

    test('nur submitted', () {
      expect(
        isEligibleForBulkApproval(
            stampEntry(status: WorkEntryStatus.approved)),
        isFalse,
      );
    });

    test('ohne sourceShiftId (ungeplant) nicht', () {
      expect(
        isEligibleForBulkApproval(stampEntry(sourceShiftId: null)),
        isFalse,
      );
    });

    test('ohne sourceClockEntryId (manuell erfasst) nicht', () {
      expect(
        isEligibleForBulkApproval(stampEntry(sourceClockEntryId: null)),
        isFalse,
      );
    });

    test('mit correctionReason (nachgearbeitet) nicht', () {
      expect(
        isEligibleForBulkApproval(stampEntry(correctionReason: 'Korrektur')),
        isFalse,
      );
    });

    test('mit Schicht: pünktlich (±15 min) ja, abweichend nein', () {
      final shift = Shift(
        id: 's1',
        orgId: 'org-1',
        userId: 'emp-1',
        employeeName: 'Anna',
        title: 'Dienst',
        startTime: DateTime(2026, 6, 10, 9),
        endTime: DateTime(2026, 6, 10, 17),
      );
      // pünktlich: Start 09:05, Ende 16:55 → innerhalb 15 min.
      expect(
        isEligibleForBulkApproval(
            stampEntry(
                start: DateTime(2026, 6, 10, 9, 5),
                end: DateTime(2026, 6, 10, 16, 55)),
            shift: shift),
        isTrue,
      );
      // verspätet: Start 09:40 → außerhalb 15 min.
      expect(
        isEligibleForBulkApproval(
            stampEntry(start: DateTime(2026, 6, 10, 9, 40)),
            shift: shift),
        isFalse,
      );
    });
  });
}
