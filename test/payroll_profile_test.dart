import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/models/payroll_profile.dart';
import 'package:worktime_app/models/payroll_record.dart';

void main() {
  const profile = PayrollProfile(
    id: 'user-1',
    orgId: 'org-1',
    userId: 'user-1',
    taxClass: TaxClass.iii,
    kind: PayrollEmploymentKind.midijob,
    churchTax: true,
    federalState: 'Bayern',
    monthlyGrossCents: 180000,
  );

  group('PayrollProfile', () {
    test('deterministische Doc-ID = userId', () {
      expect(profile.documentId, 'user-1');
    });

    test('snake_case Round-Trip (lokal)', () {
      final restored = PayrollProfile.fromMap(profile.toMap());
      expect(restored.userId, 'user-1');
      expect(restored.taxClass, TaxClass.iii);
      expect(restored.kind, PayrollEmploymentKind.midijob);
      expect(restored.churchTax, isTrue);
      expect(restored.federalState, 'Bayern');
      expect(restored.monthlyGrossCents, 180000);
    });

    test('camelCase Round-Trip (Firestore, ID separat)', () {
      final map = profile.toFirestoreMap();
      // serverTimestamp ersetzt updatedAt -> fuer das Parsen entfernen.
      map.remove('updatedAt');
      final restored = PayrollProfile.fromFirestore('user-1', map);
      expect(restored.id, 'user-1');
      expect(restored.taxClass, TaxClass.iii);
      expect(restored.kind, PayrollEmploymentKind.midijob);
      expect(restored.federalState, 'Bayern');
      expect(restored.monthlyGrossCents, 180000);
    });

    test('copyWith clearX leert nullable Felder', () {
      final cleared = profile.copyWith(
        clearFederalState: true,
        clearMonthlyGross: true,
      );
      expect(cleared.federalState, isNull);
      expect(cleared.monthlyGrossCents, isNull);
      // Andere Felder bleiben erhalten.
      expect(cleared.taxClass, TaxClass.iii);
    });

    test('sameMasterData erkennt unveraenderte Stammdaten', () {
      expect(profile.sameMasterData(profile.copyWith()), isTrue);
      expect(
        profile.sameMasterData(profile.copyWith(taxClass: TaxClass.i)),
        isFalse,
      );
      expect(
        profile.sameMasterData(profile.copyWith(monthlyGrossCents: 999)),
        isFalse,
      );
    });
  });
}
