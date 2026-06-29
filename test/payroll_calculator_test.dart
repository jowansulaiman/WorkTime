import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/payroll_calculator.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/payroll_settings.dart';

void main() {
  final settings = PayrollSettings.defaults2026();

  PayrollResult calc({
    required int gross,
    TaxClass taxClass = TaxClass.i,
    bool church = false,
    String? state,
    PayrollEmploymentKind kind = PayrollEmploymentKind.standard,
    int childCount = 0,
    bool pvChildless = false,
    double? kvOverride,
  }) {
    return PayrollCalculator.calculate(
      grossCents: gross,
      taxClass: taxClass,
      churchTax: church,
      federalState: state,
      kind: kind,
      settings: settings,
      childCount: childCount,
      pvChildless: pvChildless,
      healthAdditionalRateOverride: kvOverride,
    );
  }

  group('PayrollCalculator (Richtwert)', () {
    test('standard Klasse I, 3000 € brutto — exakte Positionen', () {
      final r = calc(gross: 300000);
      // § 32a-Tarif: ~304 €/Monat (realistischer Single-Wert, Kl. I) statt der
      // alten Pauschale von 18 % (= 540 €), die niedrige Loehne massiv ueberbesteuerte.
      expect(r.incomeTaxCents, 30408);
      expect(r.soliCents, 0); // Jahres-Lohnsteuer unter Soli-Freigrenze
      expect(r.churchTaxCents, 0);
      expect(r.healthEmployeeCents, 25650); // 8,55 % von 3000 €
      expect(r.careEmployeeCents, 5400); // 1,8 %
      expect(r.pensionEmployeeCents, 27900); // 9,3 %
      expect(r.unemploymentEmployeeCents, 3900); // 1,3 %
      expect(r.employeeSocialTotalCents, 62850);
      expect(r.netCents, 206742); // 300000 - 30408 - 62850
      // AG-Umlagen auf 3000 €: U1 1,1 % = 3300, U2 0,24 % = 720,
      // InsO 0,15 % (gesetzl. Regelsatz) = 450, UV 1,3 % = 3900 -> Summe 8370.
      expect(r.employerU1Cents, 3300);
      expect(r.employerU2Cents, 720);
      expect(r.employerInsolvencyCents, 450);
      expect(r.employerAccidentCents, 3900);
      expect(r.employerLeviesTotalCents, 8370);
      // AG-Gesamt = Brutto + AG-Sozial (62850) + AG-Umlagen (8370).
      expect(r.employerTotalCents, 371220);
    });

    test('niedriger Lohn nahe Grundfreibetrag — ~0 Lohnsteuer (Kernkorrektur)',
        () {
      // 1000 €/Monat = 12.000 €/Jahr: nach Pauschalen unter dem Grundfreibetrag
      // -> 0 Lohnsteuer. Die alte Pauschale haette faelschlich 180 € berechnet.
      final r = calc(gross: 100000);
      expect(r.incomeTaxCents, 0);
      expect(r.soliCents, 0);
      // Netto = Brutto - AN-SV (keine Steuer).
      expect(r.netCents, 100000 - r.employeeSocialTotalCents);
    });

    test('Netto- und AG-Invariante halten immer', () {
      for (final gross in [120000, 300000, 600000, 900000]) {
        final r = calc(gross: gross);
        expect(
          r.netCents,
          r.grossCents -
              r.incomeTaxCents -
              r.soliCents -
              r.churchTaxCents -
              r.employeeSocialTotalCents,
        );
        expect(
          r.employerTotalCents,
          r.grossCents +
              r.employerSocialTotalCents +
              r.employerLeviesTotalCents,
        );
      }
    });

    test('Klasse V hat höhere Lohnsteuer als Klasse I', () {
      expect(
        calc(gross: 300000, taxClass: TaxClass.v).incomeTaxCents,
        greaterThan(calc(gross: 300000).incomeTaxCents),
      );
    });

    test('Soli ab Schwelle, BBG-Deckelung der KV', () {
      final r = calc(gross: 800000); // 8000 €
      // § 32a, Zone 4 (42 %): ~1854 €/Monat (der hohe Verdiener wurde von der
      // alten 18-%-Pauschale unterbesteuert).
      expect(r.incomeTaxCents, 185425);
      // Soli greift (Jahres-LSt > Freigrenze), in der Milderungszone (11,9 %).
      expect(r.soliCents, 4087);
      // KV/PV auf BBG (5512,50 €) gedeckelt -> kleiner als ungedeckelt.
      expect(r.healthEmployeeCents, 47132); // 8,55 % von 551250
      expect(r.healthEmployeeCents, lessThan((800000 * 0.0855).round()));
      // RV/ALV-Bemessung = volles Brutto (unter RV-BBG).
      expect(r.contributionBaseCents, 800000);
    });

    test('Minijob: keine AN-Abzüge, AG-Pauschale', () {
      final r = calc(gross: 55600, kind: PayrollEmploymentKind.minijob);
      expect(r.incomeTaxCents, 0);
      expect(r.employeeSocialTotalCents, 0);
      expect(r.netCents, 55600);
      // AG-Pauschalen aufgeschlüsselt: 31,38 % von 556 € = 174,47 €.
      expect(r.minijobEmployerFlatCents, 17447);
      expect(r.employerTotalCents, 73047); // 55600 + 17447
    });

    test('Minijob-AG-Pauschalsatz ist Summe der Komponenten', () {
      expect(settings.minijobEmployerTotalRate,
          closeTo(0.13 + 0.15 + 0.0138 + 0.02, 1e-9));
    });

    test('Mindestlohn-Warnung greift unterhalb der Schwelle', () {
      // Default 13,90 €/h (2026).
      expect(settings.minimumHourlyWageCents, 1390);
      expect(settings.isBelowMinimumWage(1389), isTrue); // 13,89 €
      expect(settings.isBelowMinimumWage(1390), isFalse); // 13,90 € (Schwelle)
      expect(settings.isBelowMinimumWage(1400), isFalse); // 14,00 €
      expect(settings.isBelowMinimumWage(0), isFalse); // kein Lohn -> keine Warnung
    });

    test('PayrollSettings toMap/fromMap erhält die neuen Felder', () {
      final custom = PayrollSettings.defaults2026();
      final restored = PayrollSettings.fromMap(custom.toMap());
      expect(restored.minimumHourlyWageCents, custom.minimumHourlyWageCents);
      expect(restored.minijobEmployerHealthRate,
          custom.minijobEmployerHealthRate);
      expect(restored.minijobEmployerTotalRate,
          closeTo(custom.minijobEmployerTotalRate, 1e-9));
      expect(restored.reducedChurchTaxStates, custom.reducedChurchTaxStates);
      // AG-Umlagen runden ebenfalls round-trip-sicher durch.
      expect(restored.umlageU1Rate, closeTo(custom.umlageU1Rate, 1e-9));
      expect(restored.umlageU2Rate, closeTo(custom.umlageU2Rate, 1e-9));
      expect(restored.insolvenzgeldumlageRate,
          closeTo(custom.insolvenzgeldumlageRate, 1e-9));
      expect(restored.uvRate, closeTo(custom.uvRate, 1e-9));
      expect(restored.u1Applies, custom.u1Applies);
    });

    test('copyWith ändert nur die übergebenen Felder', () {
      final base = PayrollSettings.defaults2026();
      final changed = base.copyWith(umlageU1Rate: 0.02, u1Applies: false);
      expect(changed.umlageU1Rate, 0.02);
      expect(changed.u1Applies, isFalse);
      // Unberührte Felder bleiben gleich.
      expect(changed.umlageU2Rate, base.umlageU2Rate);
      expect(changed.healthRate, base.healthRate);
      expect(changed.minijobCeilingCents, base.minijobCeilingCents);
    });

    test('Midijob: reduzierte AN-Bemessung gegenüber Standard', () {
      final midi = calc(gross: 150000, kind: PayrollEmploymentKind.midijob);
      final std = calc(gross: 150000);
      expect(midi.contributionBaseCents, lessThan(150000));
      expect(midi.contributionBaseCents, greaterThan(0));
      expect(midi.employeeSocialTotalCents,
          lessThan(std.employeeSocialTotalCents));
    });

    test('Kirchensteuer: 9 % Standard, 8 % in Bayern, 0 wenn aus', () {
      // Klasse III (Splittingtarif) -> niedrige Lohnsteuer (~45 €/Monat).
      final base = calc(gross: 300000, taxClass: TaxClass.iii);
      expect(base.churchTaxCents, 0);
      final berlin = calc(gross: 300000, taxClass: TaxClass.iii, church: true);
      expect(berlin.churchTaxCents, 407); // 9 % der Lohnsteuer
      final bayern = calc(
          gross: 300000,
          taxClass: TaxClass.iii,
          church: true,
          state: 'Bayern');
      expect(bayern.churchTaxCents, 361); // 8 %
    });

    test('Richtwert-Flag und Disclaimer vorhanden', () {
      final r = calc(gross: 300000);
      expect(r.isRichtwert, isTrue);
      expect(PayrollResult.disclaimer, contains('Richtwert'));
    });

    test('PV-Kinderlosenzuschlag erhöht nur den AN-PV-Anteil', () {
      final ohne = calc(gross: 300000);
      final mit = calc(gross: 300000, pvChildless: true);
      // AN-PV höher (1,8 % -> 2,4 %), AG-PV unverändert.
      expect(mit.careEmployeeCents, greaterThan(ohne.careEmployeeCents));
      expect(mit.careEmployerCents, ohne.careEmployerCents);
      // 0,6 % von 3000 € = 18 € = 1800 Cent zusätzlich.
      expect(mit.careEmployeeCents - ohne.careEmployeeCents, 1800);
      // Netto sinkt entsprechend.
      expect(mit.netCents, lessThan(ohne.netCents));
    });

    test('kassenindividueller KV-Zusatzbeitrag (Override) wirkt auf KV', () {
      final standard = calc(gross: 300000); // Default-Zusatz 2,5 %
      final guenstig = calc(gross: 300000, kvOverride: 0.009); // 0,9 %
      expect(guenstig.healthEmployeeCents,
          lessThan(standard.healthEmployeeCents));
      expect(guenstig.healthEmployerCents,
          lessThan(standard.healthEmployerCents));
      // (14,6 % + 0,9 %) / 2 = 7,75 % von 3000 € = 232,50 €.
      expect(guenstig.healthEmployeeCents, 23250);
    });

    test('Kinder senken die Kirchensteuer, nicht die Lohnsteuer', () {
      final ohne = calc(
          gross: 400000, taxClass: TaxClass.iv, church: true);
      final mit = calc(
          gross: 400000,
          taxClass: TaxClass.iv,
          church: true,
          childCount: 2);
      expect(mit.incomeTaxCents, ohne.incomeTaxCents); // Lohnsteuer gleich
      expect(mit.churchTaxCents, lessThan(ohne.churchTaxCents)); // KiSt niedriger
    });

    test('Default (keine neuen Parameter) bleibt unverändert', () {
      // Sicherheitsnetz gegen versehentliche Verhaltensänderung der Altpfade.
      final r = calc(gross: 300000);
      expect(r.careEmployeeCents, 5400); // 1,8 %, kein Kinderlosenzuschlag
      expect(r.churchTaxCents, 0);
    });
  });

  group('Arbeitgeber-Umlagen (U1/U2/InsO/UV)', () {
    PayrollResult calcWith(PayrollSettings s,
        {int gross = 300000,
        PayrollEmploymentKind kind = PayrollEmploymentKind.standard}) {
      return PayrollCalculator.calculate(
        grossCents: gross,
        taxClass: TaxClass.i,
        churchTax: false,
        kind: kind,
        settings: s,
      );
    }

    test('U1 entfällt, wenn u1Applies = false (≥ 30 MA)', () {
      final ohneU1 = calcWith(settings.copyWith(u1Applies: false));
      expect(ohneU1.employerU1Cents, 0);
      // U2/InsO/UV bleiben (immer fällig).
      expect(ohneU1.employerU2Cents, 720);
      expect(ohneU1.employerInsolvencyCents, 450);
      expect(ohneU1.employerAccidentCents, 3900);
      expect(ohneU1.employerLeviesTotalCents, 5070);
    });

    test('U2/InsO/UV greifen immer, U1 nur wenn aktiv', () {
      final r = calcWith(settings);
      expect(r.employerU1Cents, greaterThan(0));
      expect(r.employerU2Cents, greaterThan(0));
      expect(r.employerInsolvencyCents, greaterThan(0));
      expect(r.employerAccidentCents, greaterThan(0));
    });

    test('Editierbare Sätze wirken auf die AG-Umlagen', () {
      final custom = settings.copyWith(
        umlageU1Rate: 0.02, // 2 %
        umlageU2Rate: 0.005, // 0,5 %
        insolvenzgeldumlageRate: 0.001, // 0,1 %
        uvRate: 0.0, // abgeschaltet
      );
      final r = calcWith(custom, gross: 200000); // 2000 €
      expect(r.employerU1Cents, 4000); // 2 % von 2000 €
      expect(r.employerU2Cents, 1000); // 0,5 %
      expect(r.employerInsolvencyCents, 200); // 0,1 %
      expect(r.employerAccidentCents, 0);
      expect(r.employerLeviesTotalCents, 5200);
    });

    test('Minijob trägt keine separaten Umlagen (im Pauschalsatz enthalten)', () {
      final r = calcWith(settings,
          gross: 50000, kind: PayrollEmploymentKind.minijob);
      expect(r.employerLeviesTotalCents, 0);
      expect(r.employerU1Cents, 0);
      // AG-Gesamt = Brutto + Pauschale (keine Doppelzählung der Umlagen).
      expect(r.employerTotalCents, r.grossCents + r.minijobEmployerFlatCents);
    });

    test('Midijob trägt AG-Umlagen wie reguläre Beschäftigung', () {
      const gross = 150000; // 1500 €
      final midi =
          calcWith(settings, gross: gross, kind: PayrollEmploymentKind.midijob);
      final std = calcWith(settings, gross: gross); // standard
      // AG-Umlagen liegen auf dem vollen (gedeckelten) Brutto, NICHT auf der
      // reduzierten Midijob-Bemessung -> identisch zur regulären Beschäftigung.
      expect(midi.employerLeviesTotalCents, std.employerLeviesTotalCents);
      expect(midi.employerU1Cents, 1650); // 1,1 % von 1500 €
      expect(midi.employerU2Cents, 360); // 0,24 %
      expect(midi.employerInsolvencyCents, 225); // 0,15 %
      expect(midi.employerAccidentCents, 1950); // 1,3 %
      expect(midi.employerLeviesTotalCents, 4185);
    });
  });
}
