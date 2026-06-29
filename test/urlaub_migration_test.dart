import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/urlaub_migration.dart';

void main() {
  group('buildUrlaubMigrationProfile (M0)', () {
    test('No-op, wenn bereits ein SollzeitProfile existiert', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        hasSollzeitProfile: true,
        annualVacationDays: 30,
      );
      expect(p, isNull);
    });

    test('No-op, wenn keine Altdaten vorliegen', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        hasSollzeitProfile: false,
      );
      expect(p, isNull);
    });

    test('No-op bei reinem Default-30-Vertrag (kein deliberater Wert)', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        hasSollzeitProfile: false,
        vertragVacationDays: 30, // = Model-Default -> nicht migrieren
      );
      expect(p, isNull);
    });

    test('deterministische Doc-ID (idempotenter Upsert)', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        hasSollzeitProfile: false,
        annualVacationDays: 30,
      )!;
      expect(p.id, 'urlaub-migration-emp-1');
    });

    test('übernimmt annualVacationDays verbatim, 5-Tage-Basis (keine Skalierung)',
        () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'org-1',
        userId: 'emp-1',
        hasSollzeitProfile: false,
        annualVacationDays: 30, // 5-Tage-Vollzeit
        vertragVacationDays: 28,
      )!;
      // B1: 30 bleibt 30 (kein 30×5/6=25).
      expect(p.urlaubstageJahr, 30);
      expect(p.arbeitstageProWoche, 5);
      expect(p.urlaubsbasisWerktage, 5);
      expect(p.orgId, 'org-1');
      expect(p.userId, 'emp-1');
      // Reines Urlaubs-Profil: Tagessoll noch 0 (Arbeitszeit-Modell folgt M-Z1).
      expect(p.wochensollMinutes, 0);
    });

    test('Vorrang annualVacationDays > vertragVacationDays', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'o',
        userId: 'u',
        hasSollzeitProfile: false,
        annualVacationDays: 32,
        vertragVacationDays: 30,
      )!;
      expect(p.urlaubstageJahr, 32);
    });

    test('fällt auf Vertrag zurück, wenn Mitarbeiterfeld fehlt', () {
      final p = buildUrlaubMigrationProfile(
        orgId: 'o',
        userId: 'u',
        hasSollzeitProfile: false,
        vertragVacationDays: 28,
      )!;
      expect(p.urlaubstageJahr, 28);
    });

    test('gueltigAb: Eintrittsdatum bevorzugt, sonst weit-zurück-Default', () {
      final mitEintritt = buildUrlaubMigrationProfile(
        orgId: 'o',
        userId: 'u',
        hasSollzeitProfile: false,
        annualVacationDays: 30,
        gueltigAb: DateTime(2022, 5, 1),
      )!;
      expect(mitEintritt.gueltigAb, DateTime(2022, 5, 1));

      final ohneEintritt = buildUrlaubMigrationProfile(
        orgId: 'o',
        userId: 'u',
        hasSollzeitProfile: false,
        annualVacationDays: 30,
      )!;
      // Weit genug zurück, damit das Profil für „heute" als aktiv gilt.
      expect(ohneEintritt.gueltigAb.isBefore(DateTime(2021, 1, 1)), isTrue);
    });
  });
}
