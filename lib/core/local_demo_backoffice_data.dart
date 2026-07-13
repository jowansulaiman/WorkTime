import '../models/datev_export_run.dart';
import '../models/employee_ausbildung.dart';
import '../models/employee_child.dart';
import '../models/employee_document.dart';
import '../models/employee_note.dart';
import '../models/employee_profile.dart';
import '../models/employee_qualification.dart';
import '../models/finance_models.dart';
import '../models/org_payroll_settings.dart';
import '../models/pay_line_type.dart';
import '../models/payroll_extras.dart';
import '../models/payroll_profile.dart';
import '../models/payroll_record.dart';
import '../models/sollzeit_profile.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import '../models/work_task.dart';
import 'datev_export.dart';
import 'local_demo_data.dart';

/// Reproduzierbare Beispieldaten fuer Personal, Lohn und Finanzen.
///
/// Die Fabriken sind absichtlich rein: Sie lesen und schreiben keinen
/// Provider-/Datenbankzustand. Ein Seeder kann dadurch nur fehlende stabile
/// Demo-IDs ergaenzen, ohne spaetere Aenderungen des Benutzers zu ueberschreiben.
/// Datumswerte liegen relativ zu [now], damit aktuelle Monats-/Jahresfilter
/// direkt aussagekraeftige Daten zeigen.
class LocalDemoBackofficeData {
  LocalDemoBackofficeData._();

  static DateTime _anchor(DateTime? now) {
    final value = now ?? DateTime.now();
    return DateTime(value.year, value.month, value.day, 12);
  }

  static DateTime _month(DateTime anchor, int offset, [int day = 15]) =>
      DateTime(anchor.year, anchor.month + offset, day, 12);

  static String _actor(String? createdByUid) =>
      createdByUid ?? LocalDemoData.adminAccount.uid;

  static String _monthToken(DateTime period) =>
      '${period.year}-${period.month.toString().padLeft(2, '0')}';

  static String costCenterId(String orgId, String key) =>
      'demo-cost-center-$orgId-$key';

  static String costTypeId(String orgId, String key) =>
      'demo-cost-type-$orgId-$key';

  static String payLineTypeId(String orgId, PayLineKind kind) =>
      'demo-pay-line-$orgId-${kind.name}';

  static String payrollJournalId({
    required String orgId,
    required String userId,
    required int year,
    required int month,
  }) =>
      'demo-journal-$orgId-payroll-$userId-$year-'
      '${month.toString().padLeft(2, '0')}';

  static List<WorkTask> workTasksForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      WorkTask(
        id: 'demo-work-task-$orgId-overdue',
        orgId: orgId,
        assignedUserId: LocalDemoData.employeeAccount.uid,
        title: 'Personalunterlagen vervollstaendigen',
        description: 'Fehlende Steuer-ID in der Personalakte nachtragen.',
        dueDate: anchor.subtract(const Duration(days: 3)),
        priority: TaskPriority.high,
        status: TaskStatus.open,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 14)),
        updatedAt: anchor.subtract(const Duration(days: 2)),
      ),
      WorkTask(
        id: 'demo-work-task-$orgId-in-progress',
        orgId: orgId,
        assignedUserId: LocalDemoData.employeeSecondAccount.uid,
        title: 'Urlaubsplanung abstimmen',
        description: 'Resturlaub und Sommervertretung mit dem Team klaeren.',
        dueDate: anchor,
        priority: TaskPriority.medium,
        status: TaskStatus.inProgress,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 8)),
        updatedAt: anchor.subtract(const Duration(hours: 4)),
      ),
      WorkTask(
        id: 'demo-work-task-$orgId-done',
        orgId: orgId,
        assignedUserId: LocalDemoData.maikeAccount.uid,
        title: 'Kassenschulung bestaetigen',
        dueDate: anchor.subtract(const Duration(days: 7)),
        priority: TaskPriority.low,
        status: TaskStatus.done,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 20)),
        updatedAt: anchor.subtract(const Duration(days: 9)),
      ),
      WorkTask(
        id: 'demo-work-task-$orgId-future-high',
        orgId: orgId,
        assignedUserId: LocalDemoData.edithAccount.uid,
        title: 'Befristung pruefen',
        description: 'Verlaengerung oder Austritt rechtzeitig vorbereiten.',
        dueDate: anchor.add(const Duration(days: 21)),
        priority: TaskPriority.high,
        status: TaskStatus.open,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 1)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
      WorkTask(
        id: 'demo-work-task-$orgId-no-deadline',
        orgId: orgId,
        assignedUserId: LocalDemoData.jarlaAccount.uid,
        title: 'Weiterbildungswunsch besprechen',
        description: 'Ohne feste Frist als Backlog-Testfall.',
        priority: TaskPriority.low,
        status: TaskStatus.open,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 5)),
        updatedAt: anchor.subtract(const Duration(days: 5)),
      ),
      WorkTask(
        id: 'demo-work-task-$orgId-done-medium',
        orgId: orgId,
        assignedUserId: LocalDemoData.raffaelAccount.uid,
        title: 'Bankverbindung aktualisiert',
        dueDate: anchor.add(const Duration(days: 5)),
        priority: TaskPriority.medium,
        status: TaskStatus.done,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 4)),
        updatedAt: anchor.subtract(const Duration(days: 1)),
      ),
    ];
  }

  static List<PayrollProfile> payrollProfilesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final values = [
      (
        LocalDemoData.employeeAccount.uid,
        TaxClass.i,
        PayrollEmploymentKind.standard,
        false,
        320000,
      ),
      (
        LocalDemoData.employeeSecondAccount.uid,
        TaxClass.ii,
        PayrollEmploymentKind.midijob,
        true,
        175000,
      ),
      (
        LocalDemoData.teamLeadAccount.uid,
        TaxClass.iii,
        PayrollEmploymentKind.standard,
        false,
        420000,
      ),
      (
        LocalDemoData.maikeAccount.uid,
        TaxClass.iv,
        PayrollEmploymentKind.minijob,
        false,
        60300,
      ),
      (
        LocalDemoData.edithAccount.uid,
        TaxClass.v,
        PayrollEmploymentKind.minijob,
        true,
        52000,
      ),
      (
        LocalDemoData.raffaelAccount.uid,
        TaxClass.vi,
        PayrollEmploymentKind.midijob,
        false,
        145000,
      ),
    ];
    return [
      for (var index = 0; index < values.length; index++)
        PayrollProfile(
          id: 'demo-payroll-profile-$orgId-${values[index].$1}',
          orgId: orgId,
          userId: values[index].$1,
          taxClass: values[index].$2,
          kind: values[index].$3,
          churchTax: values[index].$4,
          federalState: index == 2 ? 'Bayern' : 'Schleswig-Holstein',
          monthlyGrossCents: values[index].$5,
          createdByUid: actor,
          createdAt: anchor.subtract(Duration(days: 180 - index)),
          updatedAt: anchor.subtract(Duration(days: index)),
        ),
    ];
  }

  static List<PayrollRecord> payrollRecordsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final current = _month(anchor, 0, 1);
    final previous = _month(anchor, -1, 1);
    final beforePrevious = _month(anchor, -2, 1);
    final priorYear = DateTime(anchor.year - 1, 12, 1, 12);

    return [
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        period: current,
        grossCents: 320000,
        taxClass: TaxClass.i,
        kind: PayrollEmploymentKind.standard,
        status: PayrollStatus.entwurf,
        actor: actor,
        anchor: anchor,
      ),
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        period: previous,
        grossCents: 175000,
        taxClass: TaxClass.ii,
        kind: PayrollEmploymentKind.midijob,
        status: PayrollStatus.freigegeben,
        actor: actor,
        anchor: anchor,
        churchTax: true,
        withJournal: true,
      ),
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        period: previous,
        grossCents: 60300,
        taxClass: TaxClass.iv,
        kind: PayrollEmploymentKind.minijob,
        status: PayrollStatus.bezahlt,
        actor: actor,
        anchor: anchor,
        withJournal: true,
      ),
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.teamLeadAccount.uid,
        period: beforePrevious,
        grossCents: 420000,
        taxClass: TaxClass.iii,
        kind: PayrollEmploymentKind.standard,
        status: PayrollStatus.storniert,
        actor: actor,
        anchor: anchor,
      ),
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        period: current,
        grossCents: 52000,
        taxClass: TaxClass.v,
        kind: PayrollEmploymentKind.minijob,
        status: PayrollStatus.entwurf,
        actor: actor,
        anchor: anchor,
      ),
      _payrollRecord(
        orgId: orgId,
        userId: LocalDemoData.raffaelAccount.uid,
        period: priorYear,
        grossCents: 145000,
        taxClass: TaxClass.vi,
        kind: PayrollEmploymentKind.midijob,
        status: PayrollStatus.bezahlt,
        actor: actor,
        anchor: anchor,
        withJournal: true,
      ),
    ];
  }

  static PayrollRecord _payrollRecord({
    required String orgId,
    required String userId,
    required DateTime period,
    required int grossCents,
    required TaxClass taxClass,
    required PayrollEmploymentKind kind,
    required PayrollStatus status,
    required String actor,
    required DateTime anchor,
    bool churchTax = false,
    bool withJournal = false,
  }) {
    final incomeTaxCents = switch (kind) {
      PayrollEmploymentKind.minijob => 0,
      PayrollEmploymentKind.midijob => (grossCents * 0.06).round(),
      PayrollEmploymentKind.standard => (grossCents * 0.12).round(),
    };
    final healthEmployeeCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.085).round();
    final careEmployeeCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.018).round();
    final pensionEmployeeCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.093).round();
    final unemploymentEmployeeCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.013).round();
    final churchTaxCents = churchTax ? (incomeTaxCents * 0.09).round() : 0;
    final employeeDeductions =
        incomeTaxCents +
        churchTaxCents +
        healthEmployeeCents +
        careEmployeeCents +
        pensionEmployeeCents +
        unemploymentEmployeeCents;
    final healthEmployerCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.085).round();
    final careEmployerCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.018).round();
    final pensionEmployerCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.093).round();
    final unemploymentEmployerCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.013).round();
    final minijobFlat =
        kind == PayrollEmploymentKind.minijob
            ? (grossCents * 0.314).round()
            : 0;
    final employerSocial =
        healthEmployerCents +
        careEmployerCents +
        pensionEmployerCents +
        unemploymentEmployerCents +
        minijobFlat;
    final employerU1Cents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.011).round();
    final employerU2Cents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.0024).round();
    final employerInsolvencyCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.0015).round();
    final employerAccidentCents =
        kind == PayrollEmploymentKind.minijob
            ? 0
            : (grossCents * 0.013).round();
    final finalized = status.isFinalized;
    final recordId =
        'demo-payroll-record-$orgId-$userId-${_monthToken(period)}';
    return PayrollRecord(
      id: recordId,
      orgId: orgId,
      userId: userId,
      periodYear: period.year,
      periodMonth: period.month,
      grossCents: grossCents,
      istMinutes: kind == PayrollEmploymentKind.minijob ? 2100 : 8400,
      taxClass: taxClass,
      churchTax: churchTax,
      federalState: 'Schleswig-Holstein',
      kind: kind,
      incomeTaxCents: incomeTaxCents,
      churchTaxCents: churchTaxCents,
      healthEmployeeCents: healthEmployeeCents,
      careEmployeeCents: careEmployeeCents,
      pensionEmployeeCents: pensionEmployeeCents,
      unemploymentEmployeeCents: unemploymentEmployeeCents,
      healthEmployerCents: healthEmployerCents,
      careEmployerCents: careEmployerCents,
      pensionEmployerCents: pensionEmployerCents,
      unemploymentEmployerCents: unemploymentEmployerCents,
      netCents: grossCents - employeeDeductions,
      employerTotalCents:
          grossCents +
          employerSocial +
          employerU1Cents +
          employerU2Cents +
          employerInsolvencyCents +
          employerAccidentCents,
      minijobEmployerFlatCents: minijobFlat,
      employerU1Cents: employerU1Cents,
      employerU2Cents: employerU2Cents,
      employerInsolvencyCents: employerInsolvencyCents,
      employerAccidentCents: employerAccidentCents,
      status: status,
      finalizedByUid: finalized ? actor : null,
      finalizedAt:
          finalized ? DateTime(period.year, period.month + 1, 2, 10) : null,
      journalEntryId:
          withJournal
              ? payrollJournalId(
                orgId: orgId,
                userId: userId,
                year: period.year,
                month: period.month,
              )
              : null,
      lines: [
        PayrollLine(
          lineTypeId: payLineTypeId(orgId, PayLineKind.grundlohn),
          name: 'Grundlohn',
          datevLohnartNr: '1000',
          amountCents: grossCents,
          kind: PayLineKind.grundlohn,
          mengeStunden: kind == PayrollEmploymentKind.minijob ? 35 : 140,
        ),
        if (kind != PayrollEmploymentKind.minijob)
          PayrollLine(
            lineTypeId: payLineTypeId(orgId, PayLineKind.zuschlag3b),
            name: 'Sonntagszuschlag',
            datevLohnartNr: '4110',
            amountCents: 3500,
            kind: PayLineKind.zuschlag3b,
            steuerfrei: true,
            svFrei: true,
            mengeStunden: 7,
          ),
      ],
      note: switch (status) {
        PayrollStatus.entwurf => 'Demo: noch zu pruefen',
        PayrollStatus.freigegeben => 'Demo: fuer DATEV freigegeben',
        PayrollStatus.bezahlt => 'Demo: Ueberweisung erfolgt',
        PayrollStatus.storniert => 'Demo: durch Korrekturlauf ersetzt',
      },
      createdByUid: actor,
      createdAt: DateTime(period.year, period.month, 5, 10),
      updatedAt: finalized ? anchor.subtract(const Duration(days: 1)) : anchor,
    );
  }

  static List<EmployeeProfile> employeeProfilesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final accounts = [
      LocalDemoData.employeeAccount,
      LocalDemoData.employeeSecondAccount,
      LocalDemoData.teamLeadAccount,
      LocalDemoData.maikeAccount,
      LocalDemoData.edithAccount,
      LocalDemoData.raffaelAccount,
      LocalDemoData.majdAccount,
    ];
    const statuses = [
      EmployeeStatus.aktiv,
      EmployeeStatus.probezeit,
      EmployeeStatus.gekuendigt,
      EmployeeStatus.ausgeschieden,
      EmployeeStatus.ruhend,
      EmployeeStatus.aktiv,
      EmployeeStatus.aktiv,
    ];
    const groups = [
      PersonnelGroup.angestellter,
      PersonnelGroup.arbeiter,
      PersonnelGroup.leitenderAngestellter,
      PersonnelGroup.auszubildender,
      PersonnelGroup.praktikant,
      PersonnelGroup.werkstudent,
      PersonnelGroup.geringfuegigBeschaeftigter,
    ];
    const healthTypes = [
      HealthInsuranceType.gesetzlich,
      HealthInsuranceType.privat,
      HealthInsuranceType.freiwillig,
      HealthInsuranceType.gesetzlich,
      HealthInsuranceType.privat,
      HealthInsuranceType.freiwillig,
      HealthInsuranceType.gesetzlich,
    ];
    const erwerbsarten = [
      Erwerbsart.festanstellungHaupterwerb,
      Erwerbsart.festanstellungNebenerwerb,
      Erwerbsart.midijob,
      Erwerbsart.praktikum,
      Erwerbsart.werkstudent,
      Erwerbsart.geringfuegigeBeschaeftigung,
      Erwerbsart.festanstellungHaupterwerb,
    ];
    return [
      for (var index = 0; index < accounts.length; index++)
        EmployeeProfile(
          id: 'demo-employee-profile-$orgId-${accounts[index].uid}',
          orgId: orgId,
          userId: accounts[index].uid,
          salutation: index.isEven ? 'Herr' : 'Frau',
          birthDate: DateTime(1984 + index, (index % 12) + 1, 10, 12),
          nationality: 'deutsch',
          kuerzel: accounts[index].name.substring(0, 1).toUpperCase(),
          geburtsort: 'Kiel',
          street: 'Demostrasse',
          houseNumber: '${10 + index}',
          postalCode: '2410${index % 6}',
          city: 'Kiel',
          privateMobile: '0151 00000${100 + index}',
          privateEmail: accounts[index].email,
          personnelNumber: 'DEMO-${(index + 1).toString().padLeft(3, '0')}',
          status: statuses[index],
          personnelGroup: groups[index],
          hireDate: anchor.subtract(Duration(days: 900 - index * 70)),
          exitDate: switch (statuses[index]) {
            EmployeeStatus.ausgeschieden => anchor.subtract(
              const Duration(days: 90),
            ),
            EmployeeStatus.gekuendigt => anchor.add(const Duration(days: 60)),
            _ => null,
          },
          probationEnd:
              statuses[index] == EmployeeStatus.probezeit
                  ? anchor.add(const Duration(days: 45))
                  : null,
          limitedUntil:
              groups[index] == PersonnelGroup.praktikant
                  ? anchor.add(const Duration(days: 120))
                  : null,
          maritalStatus:
              MaritalStatus.values[index % MaritalStatus.values.length],
          confession: Confession.values[index % Confession.values.length],
          childrenCount: index % 3,
          taxId: '00000000${(100 + index).toString().padLeft(3, '0')}',
          socialSecurityNumber: 'DEMO-SV-${1000 + index}',
          healthInsurance:
              healthTypes[index] == HealthInsuranceType.privat
                  ? 'Demo Privatversicherung'
                  : 'Demo Krankenkasse Nord',
          healthInsuranceType: healthTypes[index],
          healthInsuranceSurchargePercent:
              healthTypes[index] == HealthInsuranceType.privat ? null : 1.7,
          iban: 'DE00100000000000000${100 + index}',
          bic: 'DEMODEFFXXX',
          accountHolder: accounts[index].name,
          emergencyContactName: 'Demo Notfallkontakt ${index + 1}',
          emergencyContactPhone: '0431 000${100 + index}',
          note: 'Reine Testdaten fuer Status- und Stammdatenansichten.',
          abteilung: index < 3 ? 'Verkauf' : 'Filialbetrieb',
          position: groups[index].label,
          kostenstelle: '${100 + index}',
          vorgesetzterName: LocalDemoData.jowanAccount.name,
          produktiveZeitProzent: index == 4 ? 60 : 85,
          fteFaktor: index == 6 ? 0.25 : (index == 5 ? 0.5 : 1),
          erwerbsart: erwerbsarten[index],
          teilnahmeZeiterfassung: true,
          autoBuchung: index.isEven,
          langzeitkrankAb:
              statuses[index] == EmployeeStatus.ruhend
                  ? anchor.subtract(const Duration(days: 50))
                  : null,
          letzterArbeitstag:
              statuses[index] == EmployeeStatus.ausgeschieden
                  ? anchor.subtract(const Duration(days: 91))
                  : null,
          kuendigungsfristWert: 4,
          kuendigungsfristTyp:
              KuendigungsfristTyp.values[index %
                  KuendigungsfristTyp.values.length],
          kuendigungsDatum:
              statuses[index] == EmployeeStatus.gekuendigt
                  ? anchor.subtract(const Duration(days: 10))
                  : null,
          kuendigungsgrund:
              statuses[index] == EmployeeStatus.gekuendigt
                  ? 'Demo: betriebliche Veraenderung'
                  : null,
          austrittsgrund:
              statuses[index] == EmployeeStatus.ausgeschieden
                  ? 'Demo: Vertragsende'
                  : null,
          entgeltgruppe: 'DEMO-E${index + 1}',
          gehaltGueltigAb: DateTime(anchor.year, 1, 1, 12),
          vwl:
              index == 0
                  ? VwlData(
                    arbeitgeberAnteilCents: 2000,
                    arbeitnehmerAnteilCents: 2000,
                    vertragsnummer: 'DEMO-VWL-001',
                    institut: 'Demo Sparbank',
                    vertragBeginn: DateTime(anchor.year - 1, 1, 1, 12),
                  )
                  : null,
          zulagen:
              index == 0
                  ? [
                    SalaryAllowance(
                      id: 'demo-allowance-$orgId-${accounts[index].uid}',
                      bezeichnung: 'Verantwortungszulage',
                      betragCents: 7500,
                      gueltigAb: DateTime(anchor.year, 1, 1, 12),
                    ),
                  ]
                  : const [],
          bankAccounts: [
            BankAccount(
              id: 'demo-bank-$orgId-${accounts[index].uid}',
              kontoinhaber: accounts[index].name,
              iban: 'DE00100000000000000${100 + index}',
              bic: 'DEMODEFFXXX',
              bankname: 'Demo Bank',
            ),
          ],
          createdByUid: actor,
          createdAt: anchor.subtract(Duration(days: 400 - index)),
          updatedAt: anchor.subtract(Duration(days: index)),
        ),
    ];
  }

  static List<SollzeitProfile> sollzeitProfilesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final validFrom = DateTime(anchor.year, 1, 1, 12);
    return [
      SollzeitProfile(
        id: 'demo-sollzeit-$orgId-fulltime',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        gueltigAb: validFrom,
        montagMinutes: 480,
        dienstagMinutes: 480,
        mittwochMinutes: 480,
        donnerstagMinutes: 480,
        freitagMinutes: 480,
        arbeitstageProWoche: 5,
        urlaubstageJahr: 30,
        zusatzurlaubstage: 2,
        rahmenVonMinutes: 360,
        rahmenBisMinutes: 1200,
        kernzeitVonMinutes: 540,
        kernzeitBisMinutes: 840,
        azMaximumMinutes: 600,
        createdByUid: actor,
      ),
      SollzeitProfile(
        id: 'demo-sollzeit-$orgId-parttime',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        gueltigAb: validFrom,
        montagMinutes: 360,
        mittwochMinutes: 360,
        freitagMinutes: 360,
        arbeitstageProWoche: 3,
        urlaubstageJahr: 30,
        urlaubsbasisWerktage: 5,
        azRunden: true,
        azRundenAufMinutes: 15,
        azRundenStart: true,
        azRundenEnde: true,
        createdByUid: actor,
      ),
      SollzeitProfile(
        id: 'demo-sollzeit-$orgId-monthly',
        orgId: orgId,
        userId: LocalDemoData.teamLeadAccount.uid,
        gueltigAb: validFrom,
        isMonatsarbeitszeit: true,
        monatsarbeitszeitMinutes: 9600,
        arbeitstageProWoche: 5,
        urlaubstageJahr: 30,
        gleitzeit: true,
        createdByUid: actor,
      ),
      SollzeitProfile(
        id: 'demo-sollzeit-$orgId-weekend',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        gueltigAb: validFrom,
        freitagMinutes: 300,
        samstagMinutes: 300,
        arbeitstageProWoche: 2,
        urlaubstageJahr: 25,
        urlaubAlsStunden: true,
        createdByUid: actor,
      ),
      SollzeitProfile(
        id: 'demo-sollzeit-$orgId-flex',
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        gueltigAb: validFrom,
        montagMinutes: 420,
        dienstagMinutes: 420,
        donnerstagMinutes: 420,
        freitagMinutes: 420,
        arbeitstageProWoche: 4,
        urlaubstageJahr: 28,
        gleitzeit: true,
        fakultativeUeberstunden: true,
        fakultativeUeberstundenTyp: 'Freizeitausgleich',
        fakultativeUeberstundenZeitraum: 'Quartal',
        createdByUid: actor,
      ),
    ];
  }

  static List<OrgPayrollSettings> orgPayrollSettingsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final currentSettings = OrgPayrollSettings.defaultSettingsForYear(
      anchor.year,
    ).copyWith(
      healthAdditionalRate: 0.027,
      umlageU1Rate: 0.012,
      uvRate: 0.014,
      u1Applies: true,
    );
    final previousSettings = OrgPayrollSettings.defaultSettingsForYear(
      anchor.year - 1,
    ).copyWith(u1Applies: false);
    return [
      OrgPayrollSettings(
        id: 'demo-org-payroll-$orgId-${anchor.year}',
        orgId: orgId,
        jahr: anchor.year,
        settings: currentSettings,
        createdByUid: actor,
        createdAt: DateTime(anchor.year, 1, 2, 12),
        updatedAt: anchor,
      ),
      OrgPayrollSettings(
        id: 'demo-org-payroll-$orgId-${anchor.year - 1}',
        orgId: orgId,
        jahr: anchor.year - 1,
        settings: previousSettings,
        createdByUid: actor,
        createdAt: DateTime(anchor.year - 1, 1, 2, 12),
        updatedAt: DateTime(anchor.year - 1, 6, 1, 12),
      ),
    ];
  }

  static List<EmployeeChild> employeeChildrenForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      EmployeeChild(
        id: 'demo-child-$orgId-peter-1',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        vorname: 'Mia',
        name: 'Demo',
        geschlecht: 'weiblich',
        steuerIdKind: '00000000101',
        geburtstag: DateTime(anchor.year - 8, 5, 12, 12),
        zaehltFuerFreibetrag: true,
        createdByUid: actor,
      ),
      EmployeeChild(
        id: 'demo-child-$orgId-peter-2',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        vorname: 'Noah',
        name: 'Demo',
        geburtstag: DateTime(anchor.year - 19, 9, 3, 12),
        anmerkungen: 'Testfall: zaehlt nicht fuer den Freibetrag.',
        zaehltFuerFreibetrag: false,
        createdByUid: actor,
      ),
      EmployeeChild(
        id: 'demo-child-$orgId-maria-1',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        vorname: 'Lina',
        name: 'Demo',
        geburtstag: DateTime(anchor.year - 3, 2, 20, 12),
        zaehltFuerFreibetrag: true,
        createdByUid: actor,
      ),
    ];
  }

  static List<EmployeeNote> employeeNotesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      EmployeeNote(
        id: 'demo-note-$orgId-peter-development',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        text:
            'Moechte mittelfristig Verantwortung fuer die Bestellung uebernehmen.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 35)),
      ),
      EmployeeNote(
        id: 'demo-note-$orgId-maria-hours',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        text: 'Teilzeitmodell zum Jahreswechsel erneut abstimmen.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 12)),
      ),
      EmployeeNote(
        id: 'demo-note-$orgId-maike-training',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        text: 'Hermes-Schulung erfolgreich abgeschlossen.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 2)),
      ),
    ];
  }

  /// In-memory document metadata for all personnel-file categories.
  ///
  /// The referenced storage objects deliberately do not exist: callers can use
  /// the metadata to exercise lists, filters, acknowledgements and retention
  /// warnings without uploading demo binaries.
  static List<EmployeeDocument> employeeDocumentsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final users = [
      LocalDemoData.employeeAccount.uid,
      LocalDemoData.employeeSecondAccount.uid,
      LocalDemoData.teamLeadAccount.uid,
      LocalDemoData.maikeAccount.uid,
      LocalDemoData.edithAccount.uid,
      LocalDemoData.raffaelAccount.uid,
      LocalDemoData.majdAccount.uid,
    ];

    return [
      for (var index = 0; index < DocumentCategory.values.length; index++)
        EmployeeDocument(
          id:
              'demo-employee-document-$orgId-'
              '${DocumentCategory.values[index].name}',
          orgId: orgId,
          userId: users[index % users.length],
          category: DocumentCategory.values[index],
          title: '${DocumentCategory.values[index].label} (Demo)',
          fileName: 'demo-${DocumentCategory.values[index].value}.pdf',
          contentType: 'application/pdf',
          sizeBytes: 12000 + index * 1379,
          storagePath:
              'employee-documents/$orgId/${users[index % users.length]}/'
              'demo-employee-document-$orgId-'
              '${DocumentCategory.values[index].name}',
          note:
              index.isOdd
                  ? 'Demodokument fuer interne und abgelaufene Ansichten.'
                  : null,
          visibleToEmployee:
              DocumentCategory.values[index] != DocumentCategory.abmahnung &&
              DocumentCategory.values[index] !=
                  DocumentCategory.fuehrungszeugnis,
          acknowledgedAt:
              index % 3 == 0 &&
                      DocumentCategory.values[index] !=
                          DocumentCategory.abmahnung &&
                      DocumentCategory.values[index] !=
                          DocumentCategory.fuehrungszeugnis
                  ? anchor.subtract(Duration(days: 4 + index))
                  : null,
          retentionUntil:
              index == DocumentCategory.values.length - 1
                  ? null
                  : index.isOdd
                  ? anchor.subtract(Duration(days: 2 + index))
                  : anchor.add(Duration(days: 90 + index)),
          uploadedByUid: actor,
          createdAt: anchor.subtract(Duration(days: 90 + index)),
          updatedAt: anchor.subtract(Duration(days: index)),
        ),
    ];
  }

  static List<EmployeeQualification> employeeQualificationsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      EmployeeQualification(
        id: 'demo-employee-quali-$orgId-valid',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        qualificationId: 'demo-qualification-$orgId-lotto',
        qualificationName: 'Lotto-Annahme',
        erwerb: QualiErwerb.vorab,
        erworbenAm: anchor.subtract(const Duration(days: 300)),
        gueltigBis: anchor.add(const Duration(days: 180)),
        zertifikatNr: 'DEMO-LOTTO-101',
        ausstellendeStelle: 'Demo Schulungszentrum',
        createdByUid: actor,
      ),
      EmployeeQualification(
        id: 'demo-employee-quali-$orgId-expiring',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        qualificationId: 'demo-qualification-$orgId-hygiene',
        qualificationName: 'Hygieneunterweisung',
        erwerb: QualiErwerb.intern,
        erworbenAm: anchor.subtract(const Duration(days: 355)),
        gueltigBis: anchor.add(const Duration(days: 10)),
        bemerkung: 'Laeuft innerhalb der Warnfrist ab.',
        createdByUid: actor,
      ),
      EmployeeQualification(
        id: 'demo-employee-quali-$orgId-expired',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        qualificationId: 'demo-qualification-$orgId-first-aid',
        qualificationName: 'Erste Hilfe',
        erwerb: QualiErwerb.extern,
        erworbenAm: anchor.subtract(const Duration(days: 800)),
        gueltigBis: anchor.subtract(const Duration(days: 10)),
        createdByUid: actor,
      ),
      EmployeeQualification(
        id: 'demo-employee-quali-$orgId-unlimited',
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        qualificationName: 'Paketshop-System',
        erwerb: QualiErwerb.intern,
        erworbenAm: anchor.subtract(const Duration(days: 60)),
        qualifikationsart: 'Interne Einweisung',
        beschreibung: 'Unbefristeter freier Qualifikationsdatensatz.',
        createdByUid: actor,
      ),
    ];
  }

  static List<EmployeeAusbildung> employeeAusbildungenForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      EmployeeAusbildung(
        id: 'demo-training-$orgId-running',
        orgId: orgId,
        userId: LocalDemoData.majdAccount.uid,
        bezeichnung: 'Ausbildung Kaufmann im Einzelhandel',
        beginn: DateTime(anchor.year - 1, 8, 1, 12),
        ende: DateTime(anchor.year + 2, 7, 31, 12),
        ausbilderUserId: LocalDemoData.jowanAccount.uid,
        ausbildungsart: 'Duale Ausbildung',
        ausbildungsstaette: 'IHK Kiel',
        fachrichtung: 'Einzelhandel',
        status: AusbildungStatus.laufend,
        noteZwischen: 'gut',
        createdByUid: actor,
      ),
      EmployeeAusbildung(
        id: 'demo-training-$orgId-completed',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        bezeichnung: 'Filialleitung kompakt',
        beginn: anchor.subtract(const Duration(days: 180)),
        ende: anchor.subtract(const Duration(days: 120)),
        ausbilderUserId: LocalDemoData.teamLeadAccount.uid,
        ausbildungsart: 'Weiterbildung',
        abschluss: 'Zertifikat',
        status: AusbildungStatus.abgeschlossen,
        noteAbschluss: 'sehr gut',
        createdByUid: actor,
      ),
      EmployeeAusbildung(
        id: 'demo-training-$orgId-cancelled',
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        bezeichnung: 'Onlinekurs Warenpraesentation',
        beginn: anchor.subtract(const Duration(days: 90)),
        ende: anchor.subtract(const Duration(days: 70)),
        ausbildungsart: 'Onlinekurs',
        status: AusbildungStatus.abgebrochen,
        bemerkung: 'Demo: Terminserie kollidierte mit Einsatzplanung.',
        createdByUid: actor,
      ),
    ];
  }

  static List<UrlaubskontoJahr> urlaubskontoJahreForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      UrlaubskontoJahr(
        id: 'demo-vacation-account-$orgId-peter-${anchor.year}',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        jahr: anchor.year,
        vortragVorjahrTage: 4,
        vortragVerfaelltAm: UrlaubskontoJahr.defaultVerfall(anchor.year),
        hinweisErteiltAm: DateTime(anchor.year, 1, 15, 12),
        gewaehrterMehrurlaubTage: 2,
        createdByUid: actor,
      ),
      UrlaubskontoJahr(
        id: 'demo-vacation-account-$orgId-maria-${anchor.year}',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        jahr: anchor.year,
        vortragVorjahrTage: 3.5,
        vortragVerfaelltAm: UrlaubskontoJahr.defaultVerfall(anchor.year),
        // Absichtlich ohne Hinweis: der Vortrag darf nicht verfallen.
        gewaehrterMehrurlaubTage: 0,
        createdByUid: actor,
      ),
      UrlaubskontoJahr(
        id: 'demo-vacation-account-$orgId-maike-${anchor.year}',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        jahr: anchor.year,
        vortragVorjahrTage: 0,
        gewaehrterMehrurlaubTage: 1,
        createdByUid: actor,
      ),
      UrlaubskontoJahr(
        id: 'demo-vacation-account-$orgId-peter-${anchor.year - 1}',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        jahr: anchor.year - 1,
        vortragVorjahrTage: 1,
        vortragVerfaelltAm: UrlaubskontoJahr.defaultVerfall(anchor.year - 1),
        hinweisErteiltAm: DateTime(anchor.year - 1, 1, 12, 12),
        createdByUid: actor,
      ),
    ];
  }

  static List<Urlaubsanpassung> urlaubsanpassungenForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      Urlaubsanpassung(
        id: 'demo-vacation-adjustment-$orgId-general-deduction',
        orgId: orgId,
        userId: LocalDemoData.employeeAccount.uid,
        jahr: anchor.year,
        tage: -1,
        art: UrlaubsAnpassungArt.abzugAllgemein,
        anmerkung: 'Korrektur einer Doppelbuchung.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 40)),
      ),
      Urlaubsanpassung(
        id: 'demo-vacation-adjustment-$orgId-expiry',
        orgId: orgId,
        userId: LocalDemoData.employeeSecondAccount.uid,
        jahr: anchor.year,
        tage: -2,
        art: UrlaubsAnpassungArt.abzugFrist,
        anmerkung: 'Dokumentierter Verfall nach Hinweis.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 30)),
      ),
      Urlaubsanpassung(
        id: 'demo-vacation-adjustment-$orgId-special',
        orgId: orgId,
        userId: LocalDemoData.maikeAccount.uid,
        jahr: anchor.year,
        tage: 1,
        art: UrlaubsAnpassungArt.sonderurlaub,
        anmerkung: 'Sonderurlaub als positiver Testfall.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 20)),
      ),
      Urlaubsanpassung(
        id: 'demo-vacation-adjustment-$orgId-general',
        orgId: orgId,
        userId: LocalDemoData.edithAccount.uid,
        jahr: anchor.year,
        tage: 0.5,
        art: UrlaubsAnpassungArt.allgemein,
        anmerkung: 'Halber Tag aus Kulanz.',
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 10)),
      ),
    ];
  }

  static List<PayLineType> payLineTypesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final rows = [
      (
        PayLineKind.grundlohn,
        'Grundlohn',
        '1000',
        PayWertTyp.nominal,
        PayInterval.monatlich,
        false,
        false,
        false,
      ),
      (
        PayLineKind.zulage,
        'Leistungszulage',
        '2000',
        PayWertTyp.prozent,
        PayInterval.quartal,
        false,
        false,
        false,
      ),
      (
        PayLineKind.abzug,
        'Vorschuss-Abzug',
        '9001',
        PayWertTyp.nominal,
        PayInterval.einmalig,
        false,
        false,
        false,
      ),
      (
        PayLineKind.fixum,
        'Monatsfixum',
        '1100',
        PayWertTyp.nominal,
        PayInterval.monatlich,
        false,
        false,
        false,
      ),
      (
        PayLineKind.vwl,
        'Vermoegenswirksame Leistungen',
        '4700',
        PayWertTyp.nominal,
        PayInterval.monatlich,
        false,
        false,
        false,
      ),
      (
        PayLineKind.zuschlag3b,
        'Sonntag/Feiertag §3b',
        '4110',
        PayWertTyp.prozent,
        PayInterval.monatlich,
        true,
        true,
        false,
      ),
      (
        PayLineKind.einmalzahlung,
        'Weihnachtsgeld (Alt)',
        '5000',
        PayWertTyp.nominal,
        PayInterval.jaehrlich,
        false,
        false,
        true,
      ),
    ];
    return [
      for (var index = 0; index < rows.length; index++)
        PayLineType(
          id: payLineTypeId(orgId, rows[index].$1),
          orgId: orgId,
          name: rows[index].$2,
          datevLohnartNr: rows[index].$3,
          kind: rows[index].$1,
          wertTyp: rows[index].$4,
          intervall: rows[index].$5,
          steuerfrei: rows[index].$6,
          svFrei: rows[index].$7,
          deaktiviert: rows[index].$8,
          createdByUid: actor,
          createdAt: anchor.subtract(Duration(days: 200 - index)),
          updatedAt: anchor.subtract(Duration(days: index)),
        ),
    ];
  }

  static List<CostCenter> costCentersForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      CostCenter(
        id: costCenterId(orgId, 'tabak'),
        orgId: orgId,
        number: '100',
        name: 'Tabak Boerse',
        description: 'Standortbezogene Kostenstelle Blücherplatz.',
        costBearerRef: 'FIL-TABAK',
        siteId: LocalDemoData.tabakSiteId(orgId),
        annualBudgetCents: 1800000,
        isBillable: true,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 500)),
      ),
      CostCenter(
        id: costCenterId(orgId, 'strich'),
        orgId: orgId,
        number: '200',
        name: 'Strichmaennchen',
        costBearerRef: 'FIL-STRICH',
        siteId: LocalDemoData.strichmaennchenSiteId(orgId),
        annualBudgetCents: 2400000,
        isBillable: true,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 500)),
      ),
      CostCenter(
        id: costCenterId(orgId, 'paket'),
        orgId: orgId,
        number: '300',
        name: 'Paketshop Dietrichsdorf',
        costBearerRef: 'FIL-PAKET',
        siteId: LocalDemoData.paketshopSiteId(orgId),
        annualBudgetCents: 1600000,
        isBillable: true,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 400)),
      ),
      CostCenter(
        id: costCenterId(orgId, 'central'),
        orgId: orgId,
        number: '900',
        name: 'Zentrale / Verwaltung',
        description: 'Standortuebergreifende Kosten.',
        annualBudgetCents: 900000,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 450)),
      ),
      CostCenter(
        id: costCenterId(orgId, 'legacy'),
        orgId: orgId,
        number: '999',
        name: 'Geschlossene Alt-Filiale',
        description: 'Inaktiv fuer Filter- und Historienansichten.',
        isActive: false,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 1200)),
      ),
    ];
  }

  static List<CostType> costTypesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final rows = [
      ('rent', '4210', 'Miete und Nebenkosten', CostTypeGroup.overhead, true),
      ('utilities', '4240', 'Energie', CostTypeGroup.overhead, true),
      ('goods', '3400', 'Wareneinsatz', CostTypeGroup.direct, true),
      ('personnel', '4100', 'Personalkosten', CostTypeGroup.direct, true),
      (
        'marketing',
        '4600',
        'Werbung und Aktionen',
        CostTypeGroup.activity,
        true,
      ),
      ('software', '4964', 'Software und IT', CostTypeGroup.activity, true),
      (
        'revenue-19',
        '8400',
        'Umsatzerloese 19 %',
        CostTypeGroup.activity,
        true,
      ),
      ('revenue-7', '8300', 'Umsatzerloese 7 %', CostTypeGroup.activity, true),
      (
        'legacy',
        '4999',
        'Historische Kostenart',
        CostTypeGroup.overhead,
        false,
      ),
    ];
    return [
      for (var index = 0; index < rows.length; index++)
        CostType(
          id: costTypeId(orgId, rows[index].$1),
          orgId: orgId,
          number: rows[index].$2,
          name: rows[index].$3,
          group: rows[index].$4,
          isActive: rows[index].$5,
          createdByUid: actor,
          createdAt: anchor.subtract(Duration(days: 600 - index)),
          updatedAt: anchor.subtract(Duration(days: index)),
        ),
    ];
  }

  static List<JournalEntry> journalEntriesForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final entries = <JournalEntry>[
      JournalEntry(
        id: 'demo-journal-$orgId-rent-current',
        orgId: orgId,
        date: _month(anchor, 0, 3),
        costCenterId: costCenterId(orgId, 'tabak'),
        costTypeId: costTypeId(orgId, 'rent'),
        description: 'Monatsmiete Tabak Boerse',
        amountCents: 180000,
        reference: 'DEMO-MIETE-${_monthToken(anchor)}',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-rent-credit-current',
        orgId: orgId,
        date: _month(anchor, 0, 8),
        costCenterId: costCenterId(orgId, 'tabak'),
        costTypeId: costTypeId(orgId, 'rent'),
        description: 'Nebenkosten-Gutschrift',
        amountCents: -25000,
        reference: 'DEMO-GS-${_monthToken(anchor)}',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-goods-previous',
        orgId: orgId,
        date: _month(anchor, -1, 12),
        costCenterId: costCenterId(orgId, 'strich'),
        costTypeId: costTypeId(orgId, 'goods'),
        description: 'Wareneinkauf Presse und Schreibwaren',
        amountCents: 450000,
        reference: 'DEMO-WE-${_monthToken(_month(anchor, -1))}',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-marketing-two-months',
        orgId: orgId,
        date: _month(anchor, -2, 18),
        costCenterId: costCenterId(orgId, 'paket'),
        costTypeId: costTypeId(orgId, 'marketing'),
        description: 'Eroeffnungsaktion Paketshop',
        amountCents: 85000,
        reference: 'DEMO-KAMPAGNE-01',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-software-current',
        orgId: orgId,
        date: _month(anchor, 0, 10),
        costCenterId: costCenterId(orgId, 'central'),
        costTypeId: costTypeId(orgId, 'software'),
        description: 'Jahreslizenz Warenwirtschaft',
        amountCents: 120000,
        reference: 'DEMO-LIZENZ-${anchor.year}',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-revenue-credit',
        orgId: orgId,
        date: _month(anchor, -1, 28),
        costCenterId: costCenterId(orgId, 'strich'),
        costTypeId: costTypeId(orgId, 'revenue-19'),
        description: 'Demo-Umsatzerloes als Gutschrift',
        amountCents: -980000,
        reference: 'DEMO-UMSATZ-${_monthToken(_month(anchor, -1))}',
        createdByUid: actor,
      ),
      JournalEntry(
        id: 'demo-journal-$orgId-rent-prior-year',
        orgId: orgId,
        date: DateTime(anchor.year - 1, 11, 3, 12),
        costCenterId: costCenterId(orgId, 'tabak'),
        costTypeId: costTypeId(orgId, 'rent'),
        description: 'Vorjahresmiete fuer Jahresvergleich',
        amountCents: 175000,
        reference: 'DEMO-MIETE-${anchor.year - 1}-11',
        createdByUid: actor,
      ),
    ];

    final payroll = payrollRecordsForOrg(
      orgId: orgId,
      createdByUid: actor,
      now: anchor,
    ).where((record) => record.journalEntryId != null);
    for (final record in payroll) {
      final centerKey = switch (record.userId) {
        final uid when uid == LocalDemoData.maikeAccount.uid => 'paket',
        final uid when uid == LocalDemoData.employeeSecondAccount.uid =>
          'strich',
        _ => 'tabak',
      };
      entries.add(
        JournalEntry(
          id: record.journalEntryId,
          orgId: orgId,
          date: DateTime(record.periodYear, record.periodMonth, 28, 12),
          costCenterId: costCenterId(orgId, centerKey),
          costTypeId: costTypeId(orgId, 'personnel'),
          description: 'Personalkosten ${record.userId}',
          amountCents: record.employerTotalCents,
          reference: record.id,
          createdByUid: actor,
        ),
      );
    }
    return entries;
  }

  static List<Budget> budgetsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    return [
      Budget(
        id: 'demo-budget-$orgId-tabak-${anchor.year}',
        orgId: orgId,
        costCenterId: costCenterId(orgId, 'tabak'),
        year: anchor.year,
        // 1550 EUR laufende Miete nach Gutschrift => bewusst ueber Plan.
        plannedAmountCents: 100000,
        createdByUid: actor,
      ),
      Budget(
        id: 'demo-budget-$orgId-strich-${anchor.year}',
        orgId: orgId,
        costCenterId: costCenterId(orgId, 'strich'),
        year: anchor.year,
        // Trotz Wareneinsatz/Personal und Erloes-Gutschrift deutlich unter Plan.
        plannedAmountCents: 2500000,
        createdByUid: actor,
      ),
      Budget(
        id: 'demo-budget-$orgId-paket-marketing-${anchor.year}',
        orgId: orgId,
        costCenterId: costCenterId(orgId, 'paket'),
        costTypeId: costTypeId(orgId, 'marketing'),
        year: anchor.year,
        plannedAmountCents: 50000,
        createdByUid: actor,
      ),
      Budget(
        id: 'demo-budget-$orgId-central-software-${anchor.year}',
        orgId: orgId,
        costCenterId: costCenterId(orgId, 'central'),
        costTypeId: costTypeId(orgId, 'software'),
        year: anchor.year,
        plannedAmountCents: 180000,
        createdByUid: actor,
      ),
      Budget(
        id: 'demo-budget-$orgId-tabak-${anchor.year - 1}',
        orgId: orgId,
        costCenterId: costCenterId(orgId, 'tabak'),
        year: anchor.year - 1,
        plannedAmountCents: 600000,
        createdByUid: actor,
      ),
    ];
  }

  /// Flüchtige DATEV-Exporthistorie für lokale Demo-Sichten.
  ///
  /// Beide Exportarten enthalten je einen byte-identisch reproduzierbaren und
  /// einen bewusst gekappten, nicht byte-identisch reproduzierbaren Lauf. Die
  /// Historie ist reine Metadaten-/Snapshot-Testdata und wird nicht persistiert.
  static List<DatevExportRun> datevExportRunsForOrg({
    required String orgId,
    String? createdByUid,
    DateTime? now,
  }) {
    final anchor = _anchor(now);
    final actor = _actor(createdByUid);
    final financeEntries = journalEntriesForOrg(
      orgId: orgId,
      createdByUid: actor,
      now: anchor,
    ).where((entry) => entry.date.year == anchor.year).toList();
    final financeSnapshot = [
      for (final entry in financeEntries)
        <String, dynamic>{
          'id': entry.id,
          'dateMillis': entry.date.millisecondsSinceEpoch,
          'costCenterId': entry.costCenterId,
          'costTypeId': entry.costTypeId,
          'amountCents': entry.amountCents,
          'description': entry.description,
          'reference': entry.reference,
        },
    ];
    final sollCents = financeEntries
        .where((entry) => entry.amountCents > 0)
        .fold<int>(0, (sum, entry) => sum + entry.amountCents);
    final habenCents = financeEntries
        .where((entry) => entry.amountCents < 0)
        .fold<int>(0, (sum, entry) => sum - entry.amountCents);
    final lohnRows = <Map<String, dynamic>>[
      {
        'personalnummer': 'DEMO-001',
        'lohnartNr': '1000',
        'mengeStunden': 140.0,
        'betragCents': 320000,
      },
      {
        'personalnummer': 'DEMO-002',
        'lohnartNr': '1000',
        'mengeStunden': 80.0,
        'betragCents': 175000,
      },
      {
        'personalnummer': 'DEMO-002',
        'lohnartNr': '4110',
        'mengeStunden': 7.0,
        'betragCents': 3500,
      },
    ];

    return [
      DatevExportRun(
        id: 'demo-datev-run-$orgId-finanz-reproducible',
        orgId: orgId,
        exportArt: DatevExportArt.finanz,
        kind: 'extf_buchungsstapel',
        periodYear: anchor.year,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 2)),
        entryCount: financeSnapshot.length,
        sollCents: sollCents,
        habenCents: habenCents,
        fileName: 'EXTF_Buchungsstapel_${anchor.year}.csv',
        fileSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        generatedAtMillis:
            anchor.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        configSnapshot: datevConfigForOrg(orgId).toFirestoreMap(),
        entriesSnapshot: financeSnapshot,
        snapshotRowCount: financeSnapshot.length,
        acceptedWarningCodes: const ['DATEV-DEMO-HINWEIS'],
        problemeAnzahl: 1,
        overrideBestaetigt: true,
        note: 'Vollständiger Finanz-Snapshot für byte-identischen Re-Download.',
      ),
      DatevExportRun(
        id: 'demo-datev-run-$orgId-finanz-truncated',
        orgId: orgId,
        exportArt: DatevExportArt.finanz,
        kind: 'extf_buchungsstapel',
        periodYear: anchor.year - 1,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 35)),
        entryCount: 2505,
        sollCents: 128500000,
        habenCents: 93200000,
        fileName: 'EXTF_Buchungsstapel_${anchor.year - 1}.csv',
        fileSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        generatedAtMillis:
            anchor.subtract(const Duration(days: 35)).millisecondsSinceEpoch,
        configSnapshot: datevConfigForOrg(orgId).toFirestoreMap(),
        entriesSnapshot: financeSnapshot.take(2).toList(growable: false),
        snapshotTruncated: true,
        snapshotRowCount:
            financeSnapshot.length < 2 ? financeSnapshot.length : 2,
        problemeAnzahl: 3,
        note: 'Snapshot-Grenze überschritten; nur Neuaufbau und Hashvergleich.',
      ),
      DatevExportRun(
        id: 'demo-datev-run-$orgId-lohn-reproducible',
        orgId: orgId,
        exportArt: DatevExportArt.lohn,
        kind: 'lodas_bewegungsdaten',
        periodYear: anchor.year,
        periodMonth: anchor.month,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 1)),
        entryCount: lohnRows.length,
        summeCents: 498500,
        fileName:
            'DATEV_Lohn_${anchor.year}_'
            '${anchor.month.toString().padLeft(2, '0')}.csv',
        fileSha256:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        rowsSnapshot: lohnRows,
        snapshotRowCount: lohnRows.length,
        subjectUserIds: [
          LocalDemoData.employeeAccount.uid,
          LocalDemoData.employeeSecondAccount.uid,
        ],
        monatFestgeschrieben: true,
        note: 'Kanonische Lohnzeilen für byte-identischen Re-Download.',
      ),
      DatevExportRun(
        id: 'demo-datev-run-$orgId-lohn-truncated',
        orgId: orgId,
        exportArt: DatevExportArt.lohn,
        kind: 'lohn_und_gehalt_bewegungsdaten',
        periodYear: anchor.year - 1,
        periodMonth: 12,
        createdByUid: actor,
        createdAt: anchor.subtract(const Duration(days: 65)),
        entryCount: 2201,
        summeCents: 184500000,
        fileName: 'DATEV_Lohn_${anchor.year - 1}_12.csv',
        fileSha256:
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        rowsSnapshot: lohnRows.take(1).toList(growable: false),
        snapshotTruncated: true,
        snapshotRowCount: 1,
        subjectUserIds: [
          LocalDemoData.employeeAccount.uid,
          LocalDemoData.employeeSecondAccount.uid,
          LocalDemoData.maikeAccount.uid,
        ],
        acceptedWarningCodes: const ['LOHN-DEMO-ALTLOHNART'],
        problemeAnzahl: 2,
        overrideBestaetigt: true,
        note: 'Gekappter Lohn-Snapshot als nicht reproduzierbarer Testfall.',
      ),
    ];
  }

  static DatevExportConfig datevConfigForOrg(String orgId) => DatevExportConfig(
    schemaVersion: 1,
    consultantNumber: '1234567',
    clientNumber: '4711',
    accountLength: 4,
    defaultContraAccount: '9000',
    designation: 'WorkTime Demo $orgId',
    revenueAccountByRate: {
      19: costTypeId(orgId, 'revenue-19'),
      7: costTypeId(orgId, 'revenue-7'),
    },
  );
}
