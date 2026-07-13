import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/local_demo_backoffice_data.dart';
import 'package:worktime_app/core/local_demo_data.dart';
import 'package:worktime_app/models/datev_export_run.dart';
import 'package:worktime_app/models/employee_ausbildung.dart';
import 'package:worktime_app/models/employee_document.dart';
import 'package:worktime_app/models/employee_profile.dart';
import 'package:worktime_app/models/employee_qualification.dart';
import 'package:worktime_app/models/finance_models.dart';
import 'package:worktime_app/models/pay_line_type.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/urlaubsanpassung.dart';
import 'package:worktime_app/models/work_task.dart';

void main() {
  const orgId = 'demo-org-test';
  final now = DateTime(2026, 7, 13, 12);
  final knownUserIds = LocalDemoData.accounts.map((item) => item.uid).toSet();

  group('LocalDemoBackofficeData Personal und Lohn', () {
    test('Aufgaben decken Status, Prioritaet und Fristvarianten ab', () {
      final tasks = LocalDemoBackofficeData.workTasksForOrg(
        orgId: orgId,
        now: now,
      );

      expect(
        tasks.map((item) => item.status).toSet(),
        TaskStatus.values.toSet(),
      );
      expect(
        tasks.map((item) => item.priority).toSet(),
        TaskPriority.values.toSet(),
      );
      expect(tasks.any((item) => item.dueDate == null), isTrue);
      expect(
        tasks.any(
          (item) =>
              item.dueDate != null &&
              item.dueDate!.isBefore(now) &&
              !item.isDone,
        ),
        isTrue,
      );
      expect(
        tasks.any((item) => item.dueDate != null && item.dueDate!.isAfter(now)),
        isTrue,
      );
      expect(
        tasks.every((item) => knownUserIds.contains(item.assignedUserId)),
        isTrue,
      );
    });

    test('Lohnprofile und Abrechnungen decken alle zentralen Enums ab', () {
      final profiles = LocalDemoBackofficeData.payrollProfilesForOrg(
        orgId: orgId,
        now: now,
      );
      final records = LocalDemoBackofficeData.payrollRecordsForOrg(
        orgId: orgId,
        now: now,
      );
      final lineTypes = LocalDemoBackofficeData.payLineTypesForOrg(
        orgId: orgId,
        now: now,
      );
      final lineTypeIds = lineTypes.map((item) => item.id).toSet();

      expect(
        profiles.map((item) => item.taxClass).toSet(),
        TaxClass.values.toSet(),
      );
      expect(
        profiles.map((item) => item.kind).toSet(),
        PayrollEmploymentKind.values.toSet(),
      );
      expect(
        records.map((item) => item.status).toSet(),
        PayrollStatus.values.toSet(),
      );
      expect(
        records.map((item) => item.kind).toSet(),
        PayrollEmploymentKind.values.toSet(),
      );
      expect(
        records
            .expand((item) => item.lines)
            .every(
              (line) =>
                  line.lineTypeId != null &&
                  lineTypeIds.contains(line.lineTypeId),
            ),
        isTrue,
      );
      expect(records.every((item) => item.netCents <= item.grossCents), isTrue);
      expect(
        records.every((item) => item.employerTotalCents >= item.grossCents),
        isTrue,
      );
      expect(
        records.every(
          (item) =>
              item.employerTotalCents ==
              item.grossCents +
                  item.employerSocialTotalCents +
                  item.minijobEmployerFlatCents +
                  item.employerU1Cents +
                  item.employerU2Cents +
                  item.employerInsolvencyCents +
                  item.employerAccidentCents,
        ),
        isTrue,
      );
      expect(
        records.every((item) => knownUserIds.contains(item.userId)),
        isTrue,
      );
    });

    test('Mitarbeiterstamm deckt Status, Gruppen und Versicherungen ab', () {
      final profiles = LocalDemoBackofficeData.employeeProfilesForOrg(
        orgId: orgId,
        now: now,
      );

      expect(
        profiles.map((item) => item.status).toSet(),
        EmployeeStatus.values.toSet(),
      );
      expect(
        profiles
            .map((item) => item.personnelGroup)
            .whereType<PersonnelGroup>()
            .toSet(),
        PersonnelGroup.values.toSet(),
      );
      expect(
        profiles
            .map((item) => item.healthInsuranceType)
            .whereType<HealthInsuranceType>()
            .toSet(),
        HealthInsuranceType.values.toSet(),
      );
      expect(
        profiles.every((item) => knownUserIds.contains(item.userId)),
        isTrue,
      );
      expect(profiles.any((item) => item.vwl != null), isTrue);
      expect(profiles.any((item) => item.zulagen.isNotEmpty), isTrue);
      expect(profiles.every((item) => item.bankAccounts.isNotEmpty), isTrue);
    });

    test('Sollzeit und Lohnkonfiguration enthalten relevante Varianten', () {
      final sollzeiten = LocalDemoBackofficeData.sollzeitProfilesForOrg(
        orgId: orgId,
        now: now,
      );
      final settings = LocalDemoBackofficeData.orgPayrollSettingsForOrg(
        orgId: orgId,
        now: now,
      );

      expect(sollzeiten.any((item) => item.isMonatsarbeitszeit), isTrue);
      expect(sollzeiten.any((item) => item.arbeitstageProWoche < 5), isTrue);
      expect(sollzeiten.any((item) => item.samstagMinutes > 0), isTrue);
      expect(sollzeiten.any((item) => item.urlaubAlsStunden), isTrue);
      expect(sollzeiten.any((item) => item.gleitzeit), isTrue);
      expect(sollzeiten.any((item) => item.fakultativeUeberstunden), isTrue);
      expect(settings.map((item) => item.jahr).toSet(), {
        now.year,
        now.year - 1,
      });
      expect(settings.map((item) => item.settings.u1Applies).toSet(), {
        true,
        false,
      });
    });

    test('Dokumente decken Kategorien, ACL, Bestaetigung und Retention ab', () {
      final documents = LocalDemoBackofficeData.employeeDocumentsForOrg(
        orgId: orgId,
        now: now,
      );

      expect(
        documents.map((item) => item.category).toSet(),
        DocumentCategory.values.toSet(),
      );
      expect(documents.map((item) => item.visibleToEmployee).toSet(), {
        true,
        false,
      });
      expect(documents.map((item) => item.acknowledged).toSet(), {true, false});
      expect(
        documents
            .where((item) => item.acknowledged)
            .every((item) => item.visibleToEmployee),
        isTrue,
      );
      expect(documents.any((item) => item.retentionExpired(now)), isTrue);
      expect(
        documents.any(
          (item) => item.retentionUntil != null && !item.retentionExpired(now),
        ),
        isTrue,
      );
      expect(documents.any((item) => item.retentionUntil == null), isTrue);
      expect(
        documents.every(
          (item) =>
              knownUserIds.contains(item.userId) &&
              item.storagePath.endsWith(item.id!),
        ),
        isTrue,
      );
    });

    test('Personal-Unterobjekte decken ihre fachlichen Varianten ab', () {
      final children = LocalDemoBackofficeData.employeeChildrenForOrg(
        orgId: orgId,
        now: now,
      );
      final notes = LocalDemoBackofficeData.employeeNotesForOrg(
        orgId: orgId,
        now: now,
      );
      final qualifications =
          LocalDemoBackofficeData.employeeQualificationsForOrg(
            orgId: orgId,
            now: now,
          );
      final trainings = LocalDemoBackofficeData.employeeAusbildungenForOrg(
        orgId: orgId,
        now: now,
      );
      final vacationAccounts = LocalDemoBackofficeData.urlaubskontoJahreForOrg(
        orgId: orgId,
        now: now,
      );
      final adjustments = LocalDemoBackofficeData.urlaubsanpassungenForOrg(
        orgId: orgId,
        now: now,
      );

      expect(children.map((item) => item.zaehltFuerFreibetrag).toSet(), {
        true,
        false,
      });
      expect(notes, isNotEmpty);
      expect(
        qualifications.map((item) => item.erwerb).toSet(),
        QualiErwerb.values.toSet(),
      );
      expect(
        qualifications.map((item) => item.gueltigkeitStatus(now)).toSet(),
        QualiGueltigkeit.values.toSet(),
      );
      expect(qualifications.any((item) => item.gueltigBis == null), isTrue);
      expect(
        qualifications
            .map((item) => item.qualificationId)
            .whereType<String>()
            .toSet(),
        {
          'demo-qualification-$orgId-lotto',
          'demo-qualification-$orgId-hygiene',
          'demo-qualification-$orgId-first-aid',
        },
      );
      expect(
        trainings.map((item) => item.status).toSet(),
        AusbildungStatus.values.toSet(),
      );
      expect(vacationAccounts.map((item) => item.jahr).toSet(), {
        now.year,
        now.year - 1,
      });
      expect(
        adjustments.map((item) => item.art).toSet(),
        UrlaubsAnpassungArt.values.toSet(),
      );
    });

    test('Lohnarten decken Art, Werttyp, Intervall und Aktivzustand ab', () {
      final types = LocalDemoBackofficeData.payLineTypesForOrg(
        orgId: orgId,
        now: now,
      );

      expect(
        types.map((item) => item.kind).toSet(),
        PayLineKind.values.toSet(),
      );
      expect(
        types.map((item) => item.wertTyp).toSet(),
        PayWertTyp.values.toSet(),
      );
      expect(
        types.map((item) => item.intervall).toSet(),
        PayInterval.values.toSet(),
      );
      expect(types.map((item) => item.deaktiviert).toSet(), {true, false});
      expect(
        types.every(
          (item) => PayLineType.isValidDatevLohnartNr(item.datevLohnartNr),
        ),
        isTrue,
      );
    });
  });

  group('LocalDemoBackofficeData Finanzen', () {
    test('Kostenstamm deckt Gruppen, Aktivzustand und Standortlinks ab', () {
      final centers = LocalDemoBackofficeData.costCentersForOrg(
        orgId: orgId,
        now: now,
      );
      final types = LocalDemoBackofficeData.costTypesForOrg(
        orgId: orgId,
        now: now,
      );

      expect(centers.map((item) => item.isActive).toSet(), {true, false});
      expect(types.map((item) => item.isActive).toSet(), {true, false});
      expect(
        types.map((item) => item.group).toSet(),
        CostTypeGroup.values.toSet(),
      );
      expect(centers.map((item) => item.siteId).whereType<String>().toSet(), {
        LocalDemoData.tabakSiteId(orgId),
        LocalDemoData.strichmaennchenSiteId(orgId),
        LocalDemoData.paketshopSiteId(orgId),
      });
      expect(centers.any((item) => item.siteId == null), isTrue);
    });

    test('Journal, Budgets, Payroll und DATEV referenzieren gueltige IDs', () {
      final centers = LocalDemoBackofficeData.costCentersForOrg(
        orgId: orgId,
        now: now,
      );
      final types = LocalDemoBackofficeData.costTypesForOrg(
        orgId: orgId,
        now: now,
      );
      final journal = LocalDemoBackofficeData.journalEntriesForOrg(
        orgId: orgId,
        now: now,
      );
      final budgets = LocalDemoBackofficeData.budgetsForOrg(
        orgId: orgId,
        now: now,
      );
      final payroll = LocalDemoBackofficeData.payrollRecordsForOrg(
        orgId: orgId,
        now: now,
      );
      final datev = LocalDemoBackofficeData.datevConfigForOrg(orgId);
      final centerIds = centers.map((item) => item.id).toSet();
      final typeIds = types.map((item) => item.id).toSet();
      final journalIds = journal.map((item) => item.id).toSet();

      expect(
        journal.every(
          (item) =>
              centerIds.contains(item.costCenterId) &&
              typeIds.contains(item.costTypeId),
        ),
        isTrue,
      );
      expect(
        budgets.every(
          (item) =>
              centerIds.contains(item.costCenterId) &&
              (item.costTypeId == null || typeIds.contains(item.costTypeId)),
        ),
        isTrue,
      );
      expect(
        payroll
            .where((item) => item.journalEntryId != null)
            .every((item) => journalIds.contains(item.journalEntryId)),
        isTrue,
      );
      expect(journal.any((item) => item.isExpense), isTrue);
      expect(journal.any((item) => item.isCredit), isTrue);
      expect(journal.any((item) => item.date.year == now.year - 1), isTrue);
      expect(datev.isConfigured, isTrue);
      expect(datev.revenueAccountByRate.keys.toSet(), {7, 19});
      expect(datev.revenueAccountByRate.values.every(typeIds.contains), isTrue);
    });

    test('Budgets enthalten bewusst einen Ueber- und Unterplan-Fall', () {
      final journal = LocalDemoBackofficeData.journalEntriesForOrg(
        orgId: orgId,
        now: now,
      );
      final budgets = LocalDemoBackofficeData.budgetsForOrg(
        orgId: orgId,
        now: now,
      );
      final tabakId = LocalDemoBackofficeData.costCenterId(orgId, 'tabak');
      final strichId = LocalDemoBackofficeData.costCenterId(orgId, 'strich');
      final tabakBudget =
          budgets
              .where(
                (item) =>
                    item.year == now.year &&
                    item.costCenterId == tabakId &&
                    item.isTotalBudget,
              )
              .single;
      final strichBudget =
          budgets
              .where(
                (item) =>
                    item.year == now.year &&
                    item.costCenterId == strichId &&
                    item.isTotalBudget,
              )
              .single;
      int actualFor(String centerId) => journal
          .where(
            (item) =>
                item.date.year == now.year && item.costCenterId == centerId,
          )
          .fold(0, (sum, item) => sum + item.amountCents);

      expect(actualFor(tabakId), greaterThan(tabakBudget.plannedAmountCents));
      expect(actualFor(strichId), lessThan(strichBudget.plannedAmountCents));
    });

    test('DATEV-Historie deckt Finanz, Lohn und Reproduzierbarkeit ab', () {
      final runs = LocalDemoBackofficeData.datevExportRunsForOrg(
        orgId: orgId,
        now: now,
      );

      expect(
        runs.map((run) => run.exportArt).toSet(),
        DatevExportArt.values.toSet(),
      );
      for (final art in DatevExportArt.values) {
        final artRuns = runs.where((run) => run.exportArt == art).toList();
        expect(artRuns, hasLength(2));
        expect(
          artRuns.map((run) => run.canRebuildByteIdentical).toSet(),
          {true, false},
        );
      }
      expect(runs.map((run) => run.snapshotTruncated).toSet(), {true, false});
      expect(
        runs.every(
          (run) =>
              run.orgId == orgId &&
              RegExp(r'^[0-9a-f]{64}$').hasMatch(run.fileSha256),
        ),
        isTrue,
      );
      expect(
        runs
            .where((run) => run.exportArt == DatevExportArt.finanz)
            .every((run) => run.configSnapshot != null),
        isTrue,
      );
      expect(
        runs
            .where((run) =>
                run.exportArt == DatevExportArt.lohn &&
                run.canRebuildByteIdentical)
            .single
            .subjectUserIds,
        containsAll({
          LocalDemoData.employeeAccount.uid,
          LocalDemoData.employeeSecondAccount.uid,
        }),
      );
    });
  });

  test('IDs sind eindeutig, stabil und als Demo-Daten erkennbar', () {
    final first = <List<String?>>[
      LocalDemoBackofficeData.workTasksForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.payrollProfilesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.payrollRecordsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.employeeProfilesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.employeeDocumentsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.journalEntriesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.budgetsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.datevExportRunsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
    ];
    final second = <List<String?>>[
      LocalDemoBackofficeData.workTasksForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.payrollProfilesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.payrollRecordsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.employeeProfilesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.employeeDocumentsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.journalEntriesForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.budgetsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
      LocalDemoBackofficeData.datevExportRunsForOrg(
        orgId: orgId,
        now: now,
      ).map((item) => item.id).toList(),
    ];

    expect(second, first);
    for (final ids in first) {
      expect(ids.every((id) => id != null && id.startsWith('demo-')), isTrue);
      expect(ids.toSet().length, ids.length);
    }
  });
}
