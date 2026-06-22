import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/payroll_record.dart';

void main() {
  group('PayrollRecord', () {
    const record = PayrollRecord(
      orgId: 'org-1',
      userId: 'u1',
      periodYear: 2026,
      periodMonth: 6,
      grossCents: 300000,
      taxClass: TaxClass.iii,
      churchTax: true,
      kind: PayrollEmploymentKind.standard,
      incomeTaxCents: 30000,
      healthEmployeeCents: 21900,
      netCents: 210000,
      employerTotalCents: 360000,
    );

    test('round-trips snake_case (toMap/fromMap)', () {
      final restored = PayrollRecord.fromMap(record.toMap());
      expect(restored.grossCents, 300000);
      expect(restored.taxClass, TaxClass.iii);
      expect(restored.churchTax, isTrue);
      expect(restored.kind, PayrollEmploymentKind.standard);
      expect(restored.incomeTaxCents, 30000);
      expect(restored.healthEmployeeCents, 21900);
      expect(restored.netCents, 210000);
      expect(restored.employerTotalCents, 360000);
    });

    test('round-trips camelCase (toFirestoreMap/fromFirestore)', () {
      final map = record.toFirestoreMap();
      expect(map['taxClass'], '3');
      expect(map['grossCents'], 300000);
      expect(map['kind'], 'standard');

      final restored = PayrollRecord.fromFirestore('u1-2026-06', map);
      expect(restored.id, 'u1-2026-06');
      expect(restored.taxClass, TaxClass.iii);
      expect(restored.netCents, 210000);
    });

    test('documentId is deterministic with zero-padded month', () {
      expect(record.documentId, 'u1-2026-06');
      const december = PayrollRecord(
        orgId: 'o',
        userId: 'abc',
        periodYear: 2026,
        periodMonth: 12,
      );
      expect(december.documentId, 'abc-2026-12');
    });

    test('enum mappings and defaults', () {
      expect(TaxClass.vi.value, '6');
      expect(TaxClass.iii.shortLabel, 'III');
      expect(TaxClassX.fromValue('3'), TaxClass.iii);
      expect(TaxClassX.fromValue(null), TaxClass.i);
      expect(PayrollEmploymentKindX.fromValue('minijob'),
          PayrollEmploymentKind.minijob);
      expect(PayrollEmploymentKindX.fromValue('zzz'),
          PayrollEmploymentKind.standard);
    });

    test('derived totals', () {
      expect(record.employeeSocialTotalCents, 21900);
      // incomeTax(30000) + soli(0) + kist(0) + employeeSocial(21900)
      expect(record.totalDeductionsCents, 51900);
    });

    test('copyWith clear flags', () {
      final withNote = record.copyWith(note: 'Bonus', federalState: 'Bayern');
      expect(withNote.note, 'Bonus');
      final cleared = withNote.copyWith(clearNote: true, clearFederalState: true);
      expect(cleared.note, isNull);
      expect(cleared.federalState, isNull);
    });

    test('Status: Default Entwurf, Enum-Mapping + fromValue-Default', () {
      expect(record.status, PayrollStatus.entwurf);
      expect(PayrollStatus.freigegeben.value, 'freigegeben');
      expect(PayrollStatusX.fromValue('bezahlt'), PayrollStatus.bezahlt);
      expect(PayrollStatusX.fromValue('zzz'), PayrollStatus.entwurf);
      expect(PayrollStatus.freigegeben.isFinalized, isTrue);
      expect(PayrollStatus.bezahlt.isFinalized, isTrue);
      expect(PayrollStatus.entwurf.isFinalized, isFalse);
      expect(PayrollStatus.storniert.isFinalized, isFalse);
    });

    test('Status + finalized-Felder round-trippen (beide Formate)', () {
      final finalized = record.copyWith(
        status: PayrollStatus.bezahlt,
        finalizedByUid: 'admin-1',
        finalizedAt: DateTime(2026, 6, 30, 9, 30),
      );
      final local = PayrollRecord.fromMap(finalized.toMap());
      expect(local.status, PayrollStatus.bezahlt);
      expect(local.finalizedByUid, 'admin-1');
      expect(local.finalizedAt, DateTime(2026, 6, 30, 9, 30));

      final fsMap = finalized.toFirestoreMap();
      expect(fsMap['status'], 'bezahlt');
      final cloud = PayrollRecord.fromFirestore('u1-2026-06', fsMap);
      expect(cloud.status, PayrollStatus.bezahlt);
      expect(cloud.finalizedByUid, 'admin-1');
      expect(cloud.finalizedAt, DateTime(2026, 6, 30, 9, 30));
    });

    test('copyWith clear-Flags für finalized-Felder', () {
      final finalized = record.copyWith(
        status: PayrollStatus.freigegeben,
        finalizedByUid: 'admin-1',
        finalizedAt: DateTime(2026, 6, 30),
      );
      final reverted = finalized.copyWith(
        status: PayrollStatus.entwurf,
        clearFinalizedBy: true,
        clearFinalizedAt: true,
      );
      expect(reverted.status, PayrollStatus.entwurf);
      expect(reverted.finalizedByUid, isNull);
      expect(reverted.finalizedAt, isNull);
    });
  });
}
