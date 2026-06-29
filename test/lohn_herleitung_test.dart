import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/german_tax.dart';
import 'package:worktime_app/core/lohn_herleitung.dart';
import 'package:worktime_app/core/sfn_zuschlag.dart';
import 'package:worktime_app/models/employment_contract.dart' show SalaryKind;
import 'package:worktime_app/models/pay_line_type.dart' show PayLineKind;
import 'package:worktime_app/models/payroll_record.dart'
    show PayrollLine, TaxClass;
import 'package:worktime_app/models/payroll_settings.dart';

void main() {
  final settings = PayrollSettings.defaults2026();

  group('LohnHerleitung.grundlohnCents (§5.6)', () {
    test('Festgehalt: nimmt das Festgehalt, ignoriert Stunden', () {
      expect(
        LohnHerleitung.grundlohnCents(
          salaryKind: SalaryKind.monthly,
          festgehaltCents: 250000,
          istMinutes: 9999,
          hourlyRateCents: 1500,
        ),
        250000,
      );
    });

    test('Festgehalt ohne Wert → 0; negativ → 0', () {
      expect(
        LohnHerleitung.grundlohnCents(salaryKind: SalaryKind.monthly),
        0,
      );
      expect(
        LohnHerleitung.grundlohnCents(
            salaryKind: SalaryKind.monthly, festgehaltCents: -5),
        0,
      );
    });

    test('Stundenlohn: round(istMinutes/60 × Stundensatz)', () {
      // 100 h (6000 min) × 13,90 € = 1390,00 €
      expect(
        LohnHerleitung.grundlohnCents(
          salaryKind: SalaryKind.hourly,
          istMinutes: 6000,
          hourlyRateCents: 1390,
        ),
        139000,
      );
      // 90 min × 20,00 € = 1,5 h × 2000 = 3000 Cent
      expect(
        LohnHerleitung.grundlohnCents(
          salaryKind: SalaryKind.hourly,
          istMinutes: 90,
          hourlyRateCents: 2000,
        ),
        3000,
      );
    });

    test('Stundenlohn ohne Stunden/Satz → 0', () {
      expect(
        LohnHerleitung.grundlohnCents(
            salaryKind: SalaryKind.hourly,
            istMinutes: 0,
            hourlyRateCents: 1500),
        0,
      );
      expect(
        LohnHerleitung.grundlohnCents(
            salaryKind: SalaryKind.hourly,
            istMinutes: 600,
            hourlyRateCents: 0),
        0,
      );
    });
  });

  group('LohnHerleitung.sfn3bLine (§3b, Bindung an den Rechenkern)', () {
    test('Grundlohn < 25 €/h: voll steuer- UND SV-frei', () {
      // 20 €/h, Nacht (+25 %), 1 h → 5,00 € Zuschlag, voll frei.
      final line = LohnHerleitung.sfn3bLine(
        art: SfnZuschlagsart.nacht,
        grundlohnCentsProStunde: 2000,
        dauer: const Duration(hours: 1),
        datevLohnartNr: '300',
      );
      expect(line.kind, PayLineKind.zuschlag3b);
      expect(line.amountCents, 500);
      expect(line.effektivSteuerfreiCents, 500);
      expect(line.effektivSvFreiCents, 500);
      expect(line.steuerpflichtigCents, 0);
      expect(line.svPflichtigCents, 0);
      expect(line.datevLohnartNr, '300');
      expect(line.name, SfnZuschlagsart.nacht.label);
    });

    test('Grundlohn 60 €/h: steuerfrei bis 50 €, SV-frei bis 25 €', () {
      // 60 €/h, Sonntag (+50 %), 1 h → gesamt 30,00 €.
      // steuerfrei: 50 % × min(60,50) = 25,00 €; SV-frei: 50 % × min(60,25)=12,50 €
      final line = LohnHerleitung.sfn3bLine(
        art: SfnZuschlagsart.sonntag,
        grundlohnCentsProStunde: 6000,
        dauer: const Duration(hours: 1),
      );
      expect(line.amountCents, 3000);
      expect(line.effektivSteuerfreiCents, 2500);
      expect(line.effektivSvFreiCents, 1250);
      expect(line.steuerpflichtigCents, 500);
      expect(line.svPflichtigCents, 1750);
    });
  });

  group('GermanIncomeTax.sonstigerBezug (§39b Abs. 3 Jahresverfahren)', () {
    ({int incomeTaxCents, int soliCents, int churchBaseTaxCents}) bezug(
      int regularMonthly,
      int bonus, {
      TaxClass taxClass = TaxClass.i,
      int childCount = 0,
    }) {
      return GermanIncomeTax.sonstigerBezug(
        regularMonthlyGrossCents: regularMonthly,
        sonstigerBezugCents: bonus,
        taxClass: taxClass,
        tariff: settings.taxTariff,
        healthEmployeeShare: settings.healthRate / 2,
        healthAdditionalEmployeeShare: settings.healthAdditionalRate / 2,
        careEmployeeShare: settings.careRate / 2,
        bbgKvPvMonthlyCents: settings.bbgKvPvMonthlyCents,
        bbgRvAlvMonthlyCents: settings.bbgRvAlvMonthlyCents,
        childCount: childCount,
      );
    }

    test('Bezug 0 / negativ → keine Steuer', () {
      expect(bezug(300000, 0).incomeTaxCents, 0);
      expect(bezug(300000, -100).incomeTaxCents, 0);
    });

    test('Kleiner Bezug unter Grundfreibetrag (ohne laufenden Lohn) → 0', () {
      // regular 0, Bonus 5.000 € → Jahres-zvE weit unter Grundfreibetrag.
      expect(bezug(0, 500000).incomeTaxCents, 0);
    });

    test('Bezug auf hohes Gehalt kostet mehr LSt als auf niedriges (Progression)',
        () {
      final hoch = bezug(800000, 200000).incomeTaxCents; // 8.000 €/mo + 2.000 €
      final niedrig = bezug(200000, 200000).incomeTaxCents; // 2.000 €/mo + 2.000 €
      expect(hoch, greaterThan(niedrig));
      expect(niedrig, greaterThan(0));
    });

    test('Größerer Bezug → mehr LSt (monoton)', () {
      final klein = bezug(300000, 100000).incomeTaxCents;
      final gross = bezug(300000, 300000).incomeTaxCents;
      expect(gross, greaterThan(klein));
    });

    test('Grenzsteuersatz exakt: Bezug komplett in der 42%-Zone → ~42 % LSt',
        () {
      // 15.000 €/Monat (180.000 €/Jahr) + 12.000 € Bonus → beide Jahreswerte in
      // Zone 4 (linear 42 %); AN über BBG ⇒ Vorsorge gedeckelt ⇒ Δ-zvE = Bonus.
      // Das Jahresverfahren muss daher den Grenzsteuersatz 42 % liefern.
      final r = bezug(1500000, 1200000);
      expect(r.incomeTaxCents / 1200000, closeTo(0.42, 0.01));
      expect(r.soliCents, greaterThan(0)); // Spitzenverdiener über Soli-Grenze
    });
  });

  group('LohnHerleitung.einmalzahlungSteuer (§39b-Wrapper)', () {
    test('ohne Kirchensteuer = reiner §39b-Bezug; KiSt nur bei churchTax', () {
      final ohne = LohnHerleitung.einmalzahlungSteuer(
        regularMonthlyGrossCents: 300000,
        einmalzahlungCents: 200000,
        settings: settings,
        taxClass: TaxClass.i,
        churchTax: false,
      );
      final mit = LohnHerleitung.einmalzahlungSteuer(
        regularMonthlyGrossCents: 300000,
        einmalzahlungCents: 200000,
        settings: settings,
        taxClass: TaxClass.i,
        churchTax: true,
        federalState: 'Bayern',
      );
      expect(ohne.churchTaxCents, 0);
      expect(mit.churchTaxCents, greaterThan(0));
      // Lohnsteuer selbst ist identisch (Kirchensteuer ist additiv).
      expect(mit.incomeTaxCents, ohne.incomeTaxCents);
    });

    test('Bezug 0 → alles 0', () {
      final r = LohnHerleitung.einmalzahlungSteuer(
        regularMonthlyGrossCents: 300000,
        einmalzahlungCents: 0,
        settings: settings,
        taxClass: TaxClass.i,
      );
      expect(r.incomeTaxCents, 0);
      expect(r.soliCents, 0);
      expect(r.churchTaxCents, 0);
    });

    test('Kirchensteuer: Bayern (8 %) < andere Länder (9 %), LSt gleich', () {
      final bay = LohnHerleitung.einmalzahlungSteuer(
        regularMonthlyGrossCents: 300000,
        einmalzahlungCents: 200000,
        settings: settings,
        taxClass: TaxClass.i,
        churchTax: true,
        federalState: 'Bayern',
      );
      final hessen = LohnHerleitung.einmalzahlungSteuer(
        regularMonthlyGrossCents: 300000,
        einmalzahlungCents: 200000,
        settings: settings,
        taxClass: TaxClass.i,
        churchTax: true,
        federalState: 'Hessen',
      );
      expect(bay.churchTaxCents, greaterThan(0));
      expect(bay.churchTaxCents, lessThan(hessen.churchTaxCents));
      expect(bay.incomeTaxCents, hessen.incomeTaxCents);
    });
  });

  group('LohnHerleitung.grundlohnProStundeCents (§5.8b-Bemessung)', () {
    test('Monatsbrutto / Sollstunden → Cent/h', () {
      // 1.875,00 € / 160 h → round(187500 × 60 / 9600) = 1171? nein: 187500*60/9600
      // = 11.250.000 / 9600 = 1171,875 → 1172.
      expect(
        LohnHerleitung.grundlohnProStundeCents(
            monatsbruttoCents: 187500, monatsSollMinutes: 9600),
        1172,
      );
    });

    test('0-Sollzeit oder 0-Brutto → 0 (kein Division-durch-0)', () {
      expect(
        LohnHerleitung.grundlohnProStundeCents(
            monatsbruttoCents: 300000, monatsSollMinutes: 0),
        0,
      );
      expect(
        LohnHerleitung.grundlohnProStundeCents(
            monatsbruttoCents: 0, monatsSollMinutes: 9600),
        0,
      );
    });
  });

  group('LohnHerleitung.sfn3bLine – Parameter & Round-trip', () {
    test('name/datevLohnartNr/lineTypeId werden übernommen, sonst art.label',
        () {
      final mit = LohnHerleitung.sfn3bLine(
        art: SfnZuschlagsart.feiertag,
        grundlohnCentsProStunde: 2000,
        dauer: const Duration(hours: 1),
        name: 'Heiligabend',
        datevLohnartNr: '402',
        lineTypeId: 'plt-9',
      );
      expect(mit.name, 'Heiligabend');
      expect(mit.datevLohnartNr, '402');
      expect(mit.lineTypeId, 'plt-9');

      final ohne = LohnHerleitung.sfn3bLine(
        art: SfnZuschlagsart.feiertag,
        grundlohnCentsProStunde: 2000,
        dauer: const Duration(hours: 1),
      );
      expect(ohne.name, SfnZuschlagsart.feiertag.label);
    });

    test('partielle §3b-Anteile (60 €/h) überleben den Firestore-Round-trip',
        () {
      // 60 €/h, Feiertag (+125 %), 1 h → gesamt 75,00 €;
      // steuerfrei: 125 % × 50 € = 62,50 €; SV-frei: 125 % × 25 € = 31,25 €.
      final line = LohnHerleitung.sfn3bLine(
        art: SfnZuschlagsart.feiertag,
        grundlohnCentsProStunde: 6000,
        dauer: const Duration(hours: 1),
      );
      expect(line.amountCents, 7500);
      expect(line.steuerfreiAnteilCents, 6250);
      expect(line.svFreiAnteilCents, 3125);

      final fs = PayrollLine.fromFirestore(line.toFirestoreMap());
      expect(fs.amountCents, 7500);
      expect(fs.steuerfreiAnteilCents, 6250);
      expect(fs.svFreiAnteilCents, 3125);
      expect(fs.steuerpflichtigCents, 1250); // 7500 − 6250
      expect(fs.svPflichtigCents, 4375); // 7500 − 3125

      final local = PayrollLine.fromMap(line.toMap());
      expect(local.steuerfreiAnteilCents, 6250);
      expect(local.svFreiAnteilCents, 3125);
    });
  });
}
