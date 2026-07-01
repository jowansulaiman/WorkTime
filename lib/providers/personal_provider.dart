import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/employment_contract_resolver.dart';
import '../core/lohn_herleitung.dart';
import '../core/payroll_calculator.dart';
import '../core/urlaub_calculator.dart';
import '../core/urlaub_migration.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import '../core/zeitkonto_calculator.dart';
import '../core/zeitkonto_snapshot_builder.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/employee_ausbildung.dart';
import '../models/employee_child.dart';
import '../models/employee_profile.dart';
import '../models/employee_qualification.dart';
import '../models/employment_contract.dart';
import '../models/org_payroll_settings.dart';
import '../models/pay_line_type.dart';
import '../models/payroll_profile.dart';
import '../models/payroll_record.dart';
import '../models/payroll_settings.dart';
import '../models/employee_site_assignment.dart';
import '../models/site_definition.dart';
import '../models/sollzeit_profile.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Sink zum automatischen Buchen der Personalkosten eines freigegebenen
/// [PayrollRecord] in die Finanzbuchhaltung (H-A1). Liefert die erzeugte
/// `JournalEntry.id` oder `null`, wenn nicht gebucht wurde. **Best-effort**:
/// darf die Lohn-Freigabe nie blockieren. In `main.dart` aus der lebenden
/// `FinanceProvider`-Instanz gesetzt (Finance steht NACH Personal in der Kette,
/// daher Injektion per Sink statt Proxy-Abhängigkeit — keine Kettenumsortierung).
typedef PayrollJournalPoster = Future<String?> Function(
  PayrollRecord record, {
  String? primarySiteId,
  String employeeLabel,
});

/// Aggregierte Abwesenheits-Kennzahlen eines Mitarbeiters (Statistik).
class AbsenceStats {
  const AbsenceStats({
    this.sicknessCount = 0,
    this.sicknessDays = 0,
    this.unavailableCount = 0,
    this.unavailableDays = 0,
    this.vacationCount = 0,
    this.vacationDays = 0,
  });

  final int sicknessCount;
  final int sicknessDays;
  final int unavailableCount;
  final int unavailableDays;
  final int vacationCount;
  final int vacationDays;

  int get totalCount => sicknessCount + unavailableCount + vacationCount;
}

/// Zustand des Personal-Bereichs (nur Admin): Arbeitsaufträge und
/// Lohnabrechnungen als eigene org-skopierte Collections, plus aggregierende
/// Sichten über Stammdaten (Mitarbeiter, Verträge, Standorte) und Abwesenheiten.
///
/// Kundenaufträge werden NICHT hier verwaltet – dafür existiert die
/// Warenwirtschaft ([InventoryProvider]); der Personal-Screen liest sie dort.
///
/// Speicher-Verhalten analog [InventoryProvider]: Cloud/Hybrid über
/// Firestore-Streams (Offline-Cache), local über SharedPreferences. Schreibende
/// Operationen fallen im Hybrid-Modus offline lokal zurück.
class PersonalProvider extends ChangeNotifier {
  PersonalProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestore = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestore;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<WorkTask>>? _tasksSubscription;
  StreamSubscription<List<PayrollRecord>>? _payrollSubscription;
  StreamSubscription<List<PayrollProfile>>? _profilesSubscription;
  StreamSubscription<List<EmployeeProfile>>? _employeeProfilesSubscription;
  StreamSubscription<List<SollzeitProfile>>? _sollzeitProfilesSubscription;
  StreamSubscription<List<OrgPayrollSettings>>? _payrollConfigSubscription;
  StreamSubscription<List<EmployeeChild>>? _childrenSubscription;
  StreamSubscription<List<EmployeeQualification>>? _qualificationsSubscription;
  StreamSubscription<List<EmployeeAusbildung>>? _ausbildungenSubscription;
  StreamSubscription<List<UrlaubskontoJahr>>? _urlaubskontoSubscription;
  StreamSubscription<List<Urlaubsanpassung>>? _urlaubsanpassungSubscription;
  StreamSubscription<List<PayLineType>>? _payLineTypesSubscription;
  StreamSubscription<List<AbsenceRequest>>? _absencesSubscription;

  AppUserProfile? _currentUser;
  List<WorkTask> _tasks = [];
  List<PayrollRecord> _payrollRecords = [];
  List<PayrollProfile> _payrollProfiles = [];
  List<EmployeeProfile> _employeeProfiles = [];
  List<SollzeitProfile> _sollzeitProfiles = [];
  List<OrgPayrollSettings> _orgPayrollSettings = [];
  List<EmployeeChild> _children = [];
  List<EmployeeQualification> _qualifications = [];
  List<EmployeeAusbildung> _ausbildungen = [];
  List<UrlaubskontoJahr> _urlaubskontoJahre = [];
  List<Urlaubsanpassung> _urlaubsanpassungen = [];
  List<PayLineType> _payLineTypes = [];
  List<AbsenceRequest> _absences = [];

  // Stammdaten aus dem TeamProvider (org-weit, via updateReferenceData).
  List<AppUserProfile> _members = [];
  List<EmploymentContract> _contracts = [];
  List<SiteDefinition> _sites = [];
  List<EmployeeSiteAssignment> _siteAssignments = [];

  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;

  // --- Getter --------------------------------------------------------------

  List<WorkTask> get tasks => _tasks;
  List<PayrollRecord> get payrollRecords => _payrollRecords;
  List<PayrollProfile> get payrollProfiles => _payrollProfiles;
  List<EmployeeProfile> get employeeProfiles => _employeeProfiles;
  List<SollzeitProfile> get sollzeitProfiles => _sollzeitProfiles;
  List<OrgPayrollSettings> get orgPayrollSettings => _orgPayrollSettings;
  List<EmployeeChild> get employeeChildren => _children;
  List<EmployeeQualification> get employeeQualifications => _qualifications;
  List<EmployeeAusbildung> get employeeAusbildungen => _ausbildungen;
  List<UrlaubskontoJahr> get urlaubskontoJahre => _urlaubskontoJahre;
  List<Urlaubsanpassung> get urlaubsanpassungen => _urlaubsanpassungen;

  /// Alle Lohnarten des Org-Katalogs (inkl. deaktivierter, für Alt-Abrechnungen).
  List<PayLineType> get payLineTypes => _payLineTypes;

  /// Nur **aktive** Lohnarten — die für neue Lohnzeilen wählbar sind.
  List<PayLineType> get activePayLineTypes =>
      _payLineTypes.where((t) => !t.deaktiviert).toList(growable: false);

  List<AbsenceRequest> get absences => _absences;
  List<AppUserProfile> get members => _members;
  List<EmploymentContract> get contracts => _contracts;
  List<SiteDefinition> get sites => _sites;

  /// Effektive Lohn-Sätze für das **laufende** Kalenderjahr (org-Override aus
  /// `payrollConfig` oder gesetzliche Richtwert-Defaults). **Nur** für
  /// jahr-unabhängige Anzeigen (z. B. Mindestlohn-Hinweis). Für periodengebundene
  /// Berechnungen IMMER [effectivePayrollSettings] mit dem Periodenjahr nutzen.
  PayrollSettings get payrollSettings =>
      effectivePayrollSettings(DateTime.now().year);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  String? get _orgId => _currentUser?.orgId;

  String get _storageModeKey => usesLocalStorage
      ? 'local'
      : (_hybridStorageEnabled ? 'hybrid' : 'cloud');

  LocalStorageScope? get _localScope {
    final user = _currentUser;
    if (user == null) return null;
    return LocalStorageScope.fromUser(user);
  }

  // --- Abgeleitete Sichten -------------------------------------------------

  List<WorkTask> tasksForUser(String userId) =>
      _tasks.where((task) => task.assignedUserId == userId).toList();

  int openTaskCountForUser(String userId) =>
      _tasks.where((task) => task.assignedUserId == userId && !task.isDone).length;

  int get openTaskCount => _tasks.where((task) => !task.isDone).length;

  List<PayrollRecord> payrollForUser(String userId) =>
      _payrollRecords.where((record) => record.userId == userId).toList();

  /// Lohn-Stammdaten eines Mitarbeiters (für die Vorbefüllung der Abrechnung).
  PayrollProfile? profileForUser(String userId) {
    for (final profile in _payrollProfiles) {
      if (profile.userId == userId) return profile;
    }
    return null;
  }

  /// Personal-Stammakte eines Mitarbeiters (HR-Stammdaten), falls vorhanden.
  EmployeeProfile? employeeProfileForUser(String userId) {
    for (final profile in _employeeProfiles) {
      if (profile.userId == userId) return profile;
    }
    return null;
  }

  /// Kinder eines Mitarbeiters (gepflegte Sub-Entitäten), nach Geburtstag.
  List<EmployeeChild> childrenForUser(String userId) {
    final list = _children.where((c) => c.userId == userId).toList();
    list.sort((a, b) {
      final ad = a.geburtstag, bd = b.geburtstag;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return list;
  }

  List<EmployeeQualification> qualificationsForUser(String userId) =>
      _qualifications.where((q) => q.userId == userId).toList(growable: false);

  List<EmployeeAusbildung> ausbildungenForUser(String userId) =>
      _ausbildungen.where((a) => a.userId == userId).toList(growable: false);

  /// **Kinderzähler-Einzelquelle (§4.4):** sobald ≥ 1 [EmployeeChild] gepflegt
  /// ist, zählt `count(zaehltFuerFreibetrag)`; sonst das Altfeld
  /// `EmployeeProfile.childrenCount` (rückwärtskompatibel) – nie beide parallel.
  /// Speist `german_tax.childCount`.
  int effektiveKinderzahl(String userId) {
    final kinder = childrenForUser(userId);
    if (kinder.isNotEmpty) {
      return kinder.where((c) => c.zaehltFuerFreibetrag).length;
    }
    return employeeProfileForUser(userId)?.childrenCount ?? 0;
  }

  /// Ob für den Mitarbeiter bereits Kinder-Sub-Entitäten gepflegt sind (dann ist
  /// `childrenCount` abgeleitet/read-only).
  bool hatGepflegteKinder(String userId) =>
      _children.any((c) => c.userId == userId);

  /// Alle Sollzeit-Profile eines Mitarbeiters, **absteigend** nach `gueltigAb`
  /// (neuestes zuerst) – clientseitig sortiert (kein Composite-Index).
  List<SollzeitProfile> sollzeitProfilesForUser(String userId) {
    final list =
        _sollzeitProfiles.where((p) => p.userId == userId).toList();
    // Deterministische Reihenfolge auch bei gleichem gueltigAb (die Auswahl
    // bestimmt Lohn + Urlaub): gueltigAb desc, dann updatedAt desc, dann id desc.
    list.sort((a, b) {
      final byDate = b.gueltigAb.compareTo(a.gueltigAb);
      if (byDate != 0) return byDate;
      final au = a.updatedAt;
      final bu = b.updatedAt;
      if (au != null && bu != null) {
        final byUpd = bu.compareTo(au);
        if (byUpd != 0) return byUpd;
      } else if (au != null) {
        return -1;
      } else if (bu != null) {
        return 1;
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    return list;
  }

  /// Das zum [date] gültige Sollzeit-Profil eines Mitarbeiters (jüngstes mit
  /// `gueltigAb <= date`), oder null.
  SollzeitProfile? activeSollzeitFor(String userId, DateTime date) {
    for (final profile in sollzeitProfilesForUser(userId)) {
      if (profile.isEffectiveOn(date)) return profile;
    }
    return null;
  }

  /// Soll/Ist-Zeitkonto eines Mitarbeiters für einen Monat (H-B2). Soll aus dem
  /// (gültig-ab-versionierten) [SollzeitProfile], Ist aus den übergebenen
  /// [WorkEntry]s (einzige Ist-Quelle — keine Mantelzeit, s. [computeZeitkonto]).
  ZeitkontoResult zeitkontoFor(
    String userId,
    int year,
    int month,
    List<WorkEntry> entries,
  ) {
    return computeZeitkonto(
      year: year,
      month: month,
      profiles: sollzeitProfilesForUser(userId),
      entries: entries.where((e) => e.userId == userId).toList(),
    );
  }

  /// Abgerechnete **Ist-Minuten** (geleistete Zeit + soll-angerechnete bezahlte
  /// Abwesenheit) für [userId] im Monat [year]/[month] — dieselbe SSoT wie der
  /// Lohnlauf ([buildZeitkontoSnapshot], M5). [monthEntries] = Zeiteinträge des
  /// Monats. L2: speist den Brutto-Vorschlag im Lohn-Editor identisch zum
  /// erzeugten Lohnentwurf (nicht mehr rohe `workedHours`-Summe).
  int abgerechnetesIstMinutesFor(
    String userId,
    int year,
    int month,
    List<WorkEntry> monthEntries,
  ) {
    final snapshot = buildZeitkontoSnapshot(
      orgId: '',
      userId: userId,
      jahr: year,
      monat: month,
      profiles: sollzeitProfilesForUser(userId),
      entries: monthEntries.where((e) => e.userId == userId).toList(),
      approvedAbsences: _absences
          .where((a) =>
              a.userId == userId && a.status == AbsenceStatus.approved)
          .toList(),
    );
    return snapshot.istMinutes;
  }

  /// Kanonischer Jahresurlaubsanspruch (Basis-Tage) nach Vorrangregel §5.1:
  /// aktives `SollzeitProfile.urlaubstageJahr` → `EmployeeProfile.annualVacationDays`
  /// → `EmploymentContract.vacationDays` → gesetzlicher Mindesturlaub. Liefert
  /// neben dem Wert auch die [UrlaubstageQuelle] (für UI-Transparenz/Migration).
  UrlaubstageErgebnis effektiveUrlaubstage(String userId, {DateTime? at}) {
    final date = at ?? DateTime.now();
    return resolveUrlaubstageJahr(
      sollzeit: activeSollzeitFor(userId, date),
      annualVacationDays: employeeProfileForUser(userId)?.annualVacationDays,
      vertragVacationDays: contractForUser(userId)?.vacationDays,
    );
  }

  /// Jahres-Vortragsdoc eines Mitarbeiters (oder null).
  UrlaubskontoJahr? urlaubskontoFor(String userId, int jahr) {
    for (final k in _urlaubskontoJahre) {
      if (k.userId == userId && k.jahr == jahr) return k;
    }
    return null;
  }

  /// Urlaubs-Korrekturen eines Mitarbeiters (optional auf [jahr] eingeschränkt).
  List<Urlaubsanpassung> urlaubsanpassungenForUser(String userId, {int? jahr}) =>
      _urlaubsanpassungen
          .where((a) => a.userId == userId && (jahr == null || a.jahr == jahr))
          .toList(growable: false);

  /// **Urlaubskonto-Aufstellung** (Plan §5.2) eines Mitarbeiters für ein Jahr –
  /// komponiert Sollzeit (Teilzeit), Ein-/Austritt, Vortrag/Verfall, Anpassungen
  /// und genehmigte/offene Urlaubsanträge (Werktage je Bundesland-Feiertage).
  UrlaubsReport urlaubsReportFor(String userId, int jahr, {DateTime? stichtag}) {
    final profile = employeeProfileForUser(userId);
    final vacationAbsences = _absences
        .where((a) =>
            a.userId == userId &&
            a.type == AbsenceType.vacation &&
            a.status != AbsenceStatus.rejected &&
            (a.startDate.year == jahr || a.endDate.year == jahr))
        .toList(growable: false);
    return berechneUrlaubsReport(
      jahr: jahr,
      sollzeit: activeSollzeitFor(userId, DateTime(jahr, 12, 31)),
      annualVacationDays: profile?.annualVacationDays,
      vertragVacationDays: contractForUser(userId)?.vacationDays,
      hireDate: profile?.hireDate,
      exitDate: profile?.exitDate,
      konto: urlaubskontoFor(userId, jahr),
      anpassungen: urlaubsanpassungenForUser(userId, jahr: jahr),
      vacationAbsences: vacationAbsences,
      bundesland: federalStateForUserPrimarySite(userId) ?? 'Schleswig-Holstein',
      stichtag: stichtag,
    );
  }

  /// §9-BUrlG-Hinweise eines Mitarbeiters für ein Jahr: Krankheit, die in einen
  /// **genehmigten** Urlaub fällt (überlappende Werktage sind gutzuschreiben).
  /// Reine Anzeige – die Gutschrift bucht der Admin als [Urlaubsanpassung],
  /// damit sie nachvollziehbar im Ledger steht.
  List<KrankheitImUrlaub> krankheitImUrlaubFor(String userId, int jahr) {
    final absences = _absences
        .where((a) =>
            a.userId == userId &&
            (a.type == AbsenceType.vacation ||
                a.type == AbsenceType.sickness) &&
            a.status != AbsenceStatus.rejected &&
            (a.startDate.year == jahr || a.endDate.year == jahr))
        .toList(growable: false);
    return findeKrankheitImUrlaub(
      absences,
      jahr: jahr,
      sollzeit: activeSollzeitFor(userId, DateTime(jahr, 12, 31)),
      bundesland: federalStateForUserPrimarySite(userId) ?? 'Schleswig-Holstein',
    );
  }

  /// Mitarbeiter mit **deliberatem** Urlaub nur in Altfeldern (kein
  /// `SollzeitProfile`) – die offene M0-Migrationsmenge. Steuert die
  /// Sichtbarkeit der Migrations-UI. Nutzt dieselbe No-op-Logik wie die
  /// Migration ([buildUrlaubMigrationProfile]), damit Anzeige und Aktion exakt
  /// übereinstimmen (insb. Default-30-Verträge zählen nicht).
  List<AppUserProfile> get mitarbeiterMitOffenerUrlaubsMigration {
    final orgId = _orgId;
    if (orgId == null) return const [];
    return _members.where((member) {
      final hatProfil =
          _sollzeitProfiles.any((p) => p.userId == member.uid);
      final profile = employeeProfileForUser(member.uid);
      final contract = contractForUser(member.uid);
      return buildUrlaubMigrationProfile(
            orgId: orgId,
            userId: member.uid,
            hasSollzeitProfile: hatProfil,
            annualVacationDays: profile?.annualVacationDays,
            vertragVacationDays: contract?.vacationDays,
          ) !=
          null;
    }).toList(growable: false);
  }

  /// Hinterlegte org-Lohn-Konfiguration für ein Jahr (oder null = Defaults).
  OrgPayrollSettings? orgPayrollSettingsForYear(int jahr) {
    for (final config in _orgPayrollSettings) {
      if (config.jahr == jahr) return config;
    }
    return null;
  }

  /// Effektive Lohn-Sätze für [jahr]: org-Override aus `payrollConfig`, sonst
  /// gesetzliche Richtwert-Defaults ([OrgPayrollSettings.defaultSettingsForYear]).
  PayrollSettings effectivePayrollSettings(int jahr) =>
      orgPayrollSettingsForYear(jahr)?.settings ??
      OrgPayrollSettings.defaultSettingsForYear(jahr);

  /// Jüngste Abrechnung eines Mitarbeiters (nach Periode).
  PayrollRecord? latestPayrollForUser(String userId) {
    final records = payrollForUser(userId);
    if (records.isEmpty) return null;
    records.sort((a, b) {
      final y = b.periodYear.compareTo(a.periodYear);
      if (y != 0) return y;
      return b.periodMonth.compareTo(a.periodMonth);
    });
    return records.first;
  }

  PayrollRecord? payrollForUserPeriod(String userId, int year, int month) {
    for (final record in _payrollRecords) {
      if (record.userId == userId &&
          record.periodYear == year &&
          record.periodMonth == month) {
        return record;
      }
    }
    return null;
  }

  /// Alle Abrechnungen eines Abrechnungsmonats (für den Lohnlauf).
  List<PayrollRecord> payrollForPeriod(int year, int month) => _payrollRecords
      .where((r) => r.periodYear == year && r.periodMonth == month)
      .toList(growable: false);

  /// **F2**-Brutto-Ableitung (Cent) pro Mitarbeiter — salaryKind-bewusst über
  /// [LohnHerleitung.grundlohnCents] + F1-Vertrag (Festgehalt vs. Stundenlohn,
  /// Vertrag → PayrollProfile-Cache). [istMinutes] = abgerechnete Ist-Zeit
  /// (relevant nur für Stundenlöhner). Einzige Brutto-Ableitungsstelle.
  int deriveGrossCentsFor(String userId, {required int istMinutes}) {
    final contract = contractForUser(userId);
    final profile = profileForUser(userId);
    final salaryKind = contract?.salaryKind ?? SalaryKind.monthly;
    final festgehalt =
        contract?.monthlyGrossCents ?? profile?.monthlyGrossCents;
    final hourlyRateCents = ((contract?.hourlyRate ?? 0) * 100).round();
    return LohnHerleitung.grundlohnCents(
      salaryKind: salaryKind,
      festgehaltCents: festgehalt,
      istMinutes: istMinutes,
      hourlyRateCents: hourlyRateCents,
    );
  }

  /// **F2**-Personalkosten-Resolver: einheitliche Brutto-/AG-Kosten pro
  /// Mitarbeiter/Monat. Bevorzugt einen **freigegebenen** [PayrollRecord]
  /// (eingefrorener Snapshot inkl. AG-Anteil), sonst eine als solche
  /// gekennzeichnete Schätzung aus [deriveGrossCentsFor] (Festgehalt vs.
  /// Stunden×Satz). So rechnen alle Kennzahl-Leser (Personalkosten je MA/
  /// Standort, MA-Selbstschätzung) mit derselben Quelle und die Festgehalt-Lücke
  /// (stilles 0 bei `salaryKind==monthly`) ist geschlossen.
  ({int grossCents, int employerTotalCents, bool isEstimate}) personnelCostFor(
    String userId,
    int year,
    int month, {
    required int istMinutes,
  }) {
    final record = payrollForUserPeriod(userId, year, month);
    if (record != null &&
        record.status != PayrollStatus.storniert &&
        record.grossCents > 0) {
      // Echte Abrechnung (Entwurf oder freigegeben) ist autoritativer als eine
      // Stunden×Satz-Schätzung — inkl. korrektem AG-Anteil.
      return (
        grossCents: record.grossCents,
        employerTotalCents: record.employerTotalCents,
        isEstimate: false,
      );
    }
    return (
      grossCents: deriveGrossCentsFor(userId, istMinutes: istMinutes),
      employerTotalCents: 0,
      isEstimate: true,
    );
  }

  /// Baut einen **Entwurfs-Lohndatensatz** (Richtwert) für [userId] im Monat
  /// [year]/[month] aus dem abgerechneten Ist [istMinutes] (inkl. bezahlter,
  /// soll-angerechneter Abwesenheit aus dem Stundenkonto). Reuse für den
  /// **Monatsabschluss** (M5) und den **Lohnlauf** (M6) — KEINE Dublette des
  /// Lohnrechners.
  ///
  /// - **Brutto** via [LohnHerleitung.grundlohnCents]: Festgehalt (Vertrag →
  ///   PayrollProfile-Cache) bei [SalaryKind.monthly], sonst Stunden × Lohn.
  /// - **Steuer-/SV-Parameter** aus dem [PayrollProfile]-Cache (Steuerklasse,
  ///   Beschäftigungsart, Kirchensteuer), Bundesland aus dem Primärstandort.
  /// - **Kinder/PV-Kinderlos/KV-Zusatz** aus der Stammakte (gleiche Quellen wie
  ///   der Lohn-Editor → identischer Richtwert).
  ///
  /// Gibt `null` zurück, wenn kein Brutto ermittelbar ist (kein Festgehalt und
  /// keine erfassten Stunden bzw. kein Stundenlohn).
  PayrollRecord? buildDraftPayrollForMonth({
    required String userId,
    required int year,
    required int month,
    required int istMinutes,
  }) {
    final profile = profileForUser(userId);
    final employee = employeeProfileForUser(userId);

    final grossCents = deriveGrossCentsFor(userId, istMinutes: istMinutes);
    if (grossCents <= 0) return null;

    final taxClass = profile?.taxClass ?? TaxClass.i;
    final kind = profile?.kind ?? PayrollEmploymentKind.standard;
    final churchTax = profile?.churchTax ?? false;
    final federalState =
        profile?.federalState ?? federalStateForUserPrimarySite(userId);
    final hatKinder =
        hatGepflegteKinder(userId) || (employee?.childrenCount ?? 0) > 0;

    final result = PayrollCalculator.calculate(
      grossCents: grossCents,
      taxClass: taxClass,
      churchTax: churchTax,
      federalState: federalState,
      kind: kind,
      settings: effectivePayrollSettings(year),
      childCount: effektiveKinderzahl(userId),
      pvChildless: _pvKinderlos(employee, hatKinder),
      healthAdditionalRateOverride: _kvZusatzOverride(employee),
    );
    return result.buildRecord(
      orgId: '',
      userId: userId,
      periodYear: year,
      periodMonth: month,
      taxClass: taxClass,
      churchTax: churchTax,
      federalState: federalState,
      note: 'Automatisch beim Monatsabschluss erzeugt (Richtwert).',
    );
  }

  /// PV-Kinderlosenzuschlag (§ 55 Abs. 3 SGB XI): nur kinderlos UND nachweislich
  /// ab 23 Jahren. Ohne Stammakte/Geburtsdatum konservativ kein Zuschlag (gleiche
  /// Logik wie der Lohn-Editor in `personal_screen`).
  bool _pvKinderlos(EmployeeProfile? employee, bool hatKinder) {
    if (employee == null || hatKinder) return false;
    final birth = employee.birthDate;
    if (birth == null) return false;
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age >= 23;
  }

  /// Kassenindividueller KV-Zusatzbeitrag aus der Stammakte als Bruchteil.
  double? _kvZusatzOverride(EmployeeProfile? employee) {
    final percent = employee?.healthInsuranceSurchargePercent;
    if (percent == null) return null;
    return percent / 100.0;
  }

  List<AbsenceRequest> absencesForUser(String userId) =>
      _absences.where((absence) => absence.userId == userId).toList();

  /// Aktiver (oder jüngster) Arbeitsvertrag eines Mitarbeiters.
  /// Am heutigen Tag gültiger Vertrag des Mitarbeiters; fällt auf den jüngsten
  /// Vertrag zurück, wenn keiner aktiv ist (zentraler **F1**-Resolver, identisch
  /// zum Zeit-/Lohn-Modul — keine divergierende Implementierung mehr).
  EmploymentContract? contractForUser(String userId) =>
      EmploymentContractResolver.activeOn(_contracts, userId, DateTime.now());

  AppUserProfile? memberById(String userId) {
    for (final member in _members) {
      if (member.uid == userId) return member;
    }
    return null;
  }

  /// Zählt Abwesenheiten (Anzahl + Tage) je Typ; ignoriert abgelehnte Anträge.
  /// Optional auf ein Kalenderjahr eingeschränkt.
  AbsenceStats absenceStatsForUser(String userId, {int? year}) {
    var sicknessCount = 0, sicknessDays = 0;
    var unavailableCount = 0, unavailableDays = 0;
    var vacationCount = 0, vacationDays = 0;
    for (final absence in _absences) {
      if (absence.userId != userId) continue;
      if (absence.status == AbsenceStatus.rejected) continue;
      if (year != null && absence.startDate.year != year) continue;
      final days = absence.endDate.difference(absence.startDate).inDays + 1;
      final span = days < 1 ? 1 : days;
      switch (absence.type) {
        case AbsenceType.sickness:
        case AbsenceType.childSick:
          sicknessCount++;
          sicknessDays += span;
        case AbsenceType.vacation:
          vacationCount++;
          vacationDays += span;
        // Übrige Abwesenheitsarten (Sonderurlaub, unbezahlt, Elternzeit, …)
        // zählen in dieser groben Statistik als „nicht verfügbar".
        default:
          unavailableCount++;
          unavailableDays += span;
      }
    }
    return AbsenceStats(
      sicknessCount: sicknessCount,
      sicknessDays: sicknessDays,
      unavailableCount: unavailableCount,
      unavailableDays: unavailableDays,
      vacationCount: vacationCount,
      vacationDays: vacationDays,
    );
  }

  /// Lädt org-weit alle Zeiteinträge eines Monats (für Personalkosten/Finanz).
  /// Cloud/Hybrid über Firestore, local aus SharedPreferences.
  Future<List<WorkEntry>> loadOrgWorkEntriesForMonth(DateTime month) async {
    final orgId = _orgId;
    if (orgId == null) return const [];
    if (_usesFirestore) {
      try {
        return await _firestore.getOrgWorkEntriesForMonth(
          orgId: orgId,
          month: month,
        );
      } catch (error) {
        if (!usesHybridStorage) rethrow;
        AppLogger.warning(
          'Personal: loadOrgWorkEntriesForMonth offline – lokaler Fallback',
          error: error,
        );
      }
    }
    final all = await DatabaseService.loadLocalEntries(scope: _localScope);
    return all
        .where((entry) =>
            entry.date.year == month.year && entry.date.month == month.month)
        .toList(growable: false);
  }

  // --- Session / Reference Data -------------------------------------------

  AuditSink? _audit;

  /// Senke fürs Änderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  /// Anzeigename eines Mitarbeiters aus den Stammdaten (sonst die userId).
  String _memberLabel(String userId) =>
      memberById(userId)?.displayName ?? userId;

  /// Cent-Betrag als deutscher Euro-String (z.B. 250000 -> "2500,00").
  String _euro(int cents) => (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

  /// Datum als `TT.MM.JJJJ` (für Audit-Summaries; keine Locale-Abhängigkeit).
  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';

  void updateReferenceData({
    List<AppUserProfile> members = const [],
    List<EmploymentContract> contracts = const [],
    List<SiteDefinition> sites = const [],
    List<EmployeeSiteAssignment> siteAssignments = const [],
  }) {
    _members = members;
    _contracts = contracts;
    _sites = sites;
    _siteAssignments = siteAssignments;
    // Bewusst kein notifyListeners (Setter wird im Rebuild aufgerufen ->
    // sonst Rebuild-Loop, vgl. TeamProvider-Konvention).
  }

  /// Primär-Standortzuordnung eines Mitarbeiters (oder die erste vorhandene).
  EmployeeSiteAssignment? _primaryAssignmentForUser(String userId) {
    final assignments =
        _siteAssignments.where((a) => a.userId == userId).toList();
    if (assignments.isEmpty) return null;
    return assignments.firstWhere(
      (a) => a.isPrimary,
      orElse: () => assignments.first,
    );
  }

  /// `siteId` des Primärstandorts eines Mitarbeiters (für Kostenstellen-
  /// Auflösung der Personalkosten-Buchung, H-A1/H-C1).
  String? primarySiteIdForUser(String userId) =>
      _primaryAssignmentForUser(userId)?.siteId;

  /// Bundesland (Kirchensteuer) des **Primärstandorts** eines Mitarbeiters,
  /// abgeleitet über `EmployeeSiteAssignment(primary).siteId → SiteDefinition.
  /// federalState` (H-C3). Nur als **Vorbefüllung** für eine *neue* Abrechnung
  /// gedacht; `PayrollRecord.federalState` bleibt ein eingefrorener Snapshot.
  /// Auflösung über die stabile `siteId`, nie über den (driftenden) siteName.
  String? federalStateForUserPrimarySite(String userId) {
    final primary = _primaryAssignmentForUser(userId);
    if (primary == null) return null;
    for (final site in _sites) {
      if (site.id == primary.siteId) {
        final state = site.federalState?.trim();
        return (state == null || state.isEmpty) ? null : state;
      }
    }
    return null;
  }

  // --- Auto-Buchung Personalkosten → Finanzen (H-A1) -----------------------

  PayrollJournalPoster? _journalPoster;

  /// Verbindet die Personalkosten-Buchung mit der lebenden FinanceProvider-
  /// Instanz (aus `main.dart`). Idempotenter Setter (wie `setAuditSink`).
  void setPayrollJournalPoster(PayrollJournalPoster? poster) {
    _journalPoster = poster;
  }

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey) {
      _currentUser = user;
      return;
    }
    _lastSessionKey = sessionKey;
    _currentUser = user;

    await _cancelSubscriptions();

    if (user == null) {
      _resetData();
      _safeNotify();
      return;
    }

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      _safeNotify();
    }
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _tasksSubscription = _firestore.watchWorkTasks(orgId).listen((items) {
      _tasks = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _absencesSubscription =
        _firestore.watchAllAbsenceRequests(orgId: orgId).listen((items) {
      _absences = items;
      _safeNotify();
    }, onError: _setError);

    // Lohndaten (payrollRecords/payrollProfiles) und die HR-Stammakte
    // (employeeProfiles) sind laut firestore.rules admin-only. Fuer
    // Nicht-Admins werden diese Streams gar nicht erst aufgebaut, sonst
    // erzeugt jeder regulaere Login zuverlaessig permission-denied-Fehler
    // (Fehler-Rauschen) und der Ladespinner bliebe haengen (probleme #18).
    if (!isAdmin) {
      // M7-Self-Read: reguläre Mitarbeiter laden ihr EIGENES Sollzeit-Profil
      // (self-scoped, firestore.rules erlauben `userId == uid`), damit
      // Stundenkonto/Mein-Monatsabschluss das Soll berechnen statt zu degradieren.
      // Lohn/Stammakte bleiben admin-only (kein Konsument in der Self-Sicht).
      final uid = _currentUser?.uid;
      if (uid != null) {
        _sollzeitProfilesSubscription = _firestore
            .watchSollzeitProfilesForUser(orgId: orgId, userId: uid)
            .listen((items) {
          _sollzeitProfiles = items;
          _loading = false;
          _safeNotify();
        }, onError: _setError);
      }
      return;
    }

    _payrollSubscription =
        _firestore.watchPayrollRecords(orgId).listen((items) {
      _payrollRecords = items;
      _safeNotify();
    }, onError: _setError);

    _profilesSubscription =
        _firestore.watchPayrollProfiles(orgId).listen((items) {
      _payrollProfiles = items;
      _safeNotify();
    }, onError: _setError);

    _employeeProfilesSubscription =
        _firestore.watchEmployeeProfiles(orgId).listen((items) {
      _employeeProfiles = items;
      _safeNotify();
    }, onError: _setError);

    _sollzeitProfilesSubscription =
        _firestore.watchSollzeitProfiles(orgId).listen((items) {
      _sollzeitProfiles = items;
      _safeNotify();
    }, onError: _setError);

    _payrollConfigSubscription =
        _firestore.watchOrgPayrollSettings(orgId).listen((items) {
      _orgPayrollSettings = items;
      _safeNotify();
    }, onError: _setError);

    _childrenSubscription =
        _firestore.watchEmployeeChildren(orgId).listen((items) {
      _children = items;
      _safeNotify();
    }, onError: _setError);

    _qualificationsSubscription =
        _firestore.watchEmployeeQualifications(orgId).listen((items) {
      _qualifications = items;
      _safeNotify();
    }, onError: _setError);

    _ausbildungenSubscription =
        _firestore.watchEmployeeAusbildungen(orgId).listen((items) {
      _ausbildungen = items;
      _safeNotify();
    }, onError: _setError);

    _urlaubskontoSubscription =
        _firestore.watchUrlaubskontoJahre(orgId).listen((items) {
      _urlaubskontoJahre = items;
      _safeNotify();
    }, onError: _setError);

    _urlaubsanpassungSubscription =
        _firestore.watchUrlaubsanpassungen(orgId).listen((items) {
      _urlaubsanpassungen = items;
      _safeNotify();
    }, onError: _setError);

    _payLineTypesSubscription =
        _firestore.watchPayLineTypes(orgId).listen((items) {
      _payLineTypes = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _loadLocalData() async {
    final scope = _localScope;
    _tasks = await DatabaseService.loadLocalWorkTasks(scope: scope);
    _payrollRecords =
        await DatabaseService.loadLocalPayrollRecords(scope: scope);
    _payrollProfiles =
        await DatabaseService.loadLocalPayrollProfiles(scope: scope);
    _employeeProfiles =
        await DatabaseService.loadLocalEmployeeProfiles(scope: scope);
    _sollzeitProfiles =
        await DatabaseService.loadLocalSollzeitProfiles(scope: scope);
    _orgPayrollSettings =
        await DatabaseService.loadLocalOrgPayrollSettings(scope: scope);
    _children = await DatabaseService.loadLocalEmployeeChildren(scope: scope);
    _qualifications =
        await DatabaseService.loadLocalEmployeeQualifications(scope: scope);
    _ausbildungen =
        await DatabaseService.loadLocalEmployeeAusbildungen(scope: scope);
    _urlaubskontoJahre =
        await DatabaseService.loadLocalUrlaubskontoJahre(scope: scope);
    _urlaubsanpassungen =
        await DatabaseService.loadLocalUrlaubsanpassungen(scope: scope);
    _payLineTypes = await DatabaseService.loadLocalPayLineTypes(scope: scope);
    _absences = await DatabaseService.loadLocalAbsenceRequests(scope: scope);
  }

  Future<void> _cancelSubscriptions() async {
    await _tasksSubscription?.cancel();
    await _payrollSubscription?.cancel();
    await _profilesSubscription?.cancel();
    await _employeeProfilesSubscription?.cancel();
    await _sollzeitProfilesSubscription?.cancel();
    await _payrollConfigSubscription?.cancel();
    await _childrenSubscription?.cancel();
    await _qualificationsSubscription?.cancel();
    await _ausbildungenSubscription?.cancel();
    await _urlaubskontoSubscription?.cancel();
    await _urlaubsanpassungSubscription?.cancel();
    await _payLineTypesSubscription?.cancel();
    await _absencesSubscription?.cancel();
    _tasksSubscription = null;
    _payrollSubscription = null;
    _profilesSubscription = null;
    _employeeProfilesSubscription = null;
    _sollzeitProfilesSubscription = null;
    _payrollConfigSubscription = null;
    _childrenSubscription = null;
    _qualificationsSubscription = null;
    _ausbildungenSubscription = null;
    _urlaubskontoSubscription = null;
    _urlaubsanpassungSubscription = null;
    _payLineTypesSubscription = null;
    _absencesSubscription = null;
  }

  void _resetData() {
    _tasks = [];
    _payrollRecords = [];
    _payrollProfiles = [];
    _employeeProfiles = [];
    _sollzeitProfiles = [];
    _orgPayrollSettings = [];
    _children = [];
    _qualifications = [];
    _ausbildungen = [];
    _urlaubskontoJahre = [];
    _urlaubsanpassungen = [];
    _payLineTypes = [];
    _absences = [];
    _loading = false;
  }

  // --- Arbeitsaufträge -----------------------------------------------------

  Future<void> saveWorkTask(WorkTask task) async {
    _assertAdmin();
    final orgId = _requireOrg();
    // Vor der ggf. neuen ID-Vergabe ermitteln, ob der Auftrag neu ist.
    final isNew = task.id == null || task.id!.isEmpty;
    final prepared = task.copyWith(
      orgId: orgId,
      createdByUid: task.createdByUid ?? _currentUser?.uid,
    );
    if (_usesFirestore &&
        await _tryFirestore(
          'saveWorkTask',
          () => _firestore.saveWorkTask(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Auftrag',
        entityId: prepared.id,
        summary: 'Auftrag „${task.title}" '
            '${isNew ? 'angelegt' : 'aktualisiert'}',
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('task'))
        : prepared;
    _upsertLocal(_tasks, withId, (item) => item.id);
    _tasks = [..._tasks];
    await _persistTasks();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Auftrag',
      entityId: withId.id,
      summary: 'Auftrag „${task.title}" '
          '${isNew ? 'angelegt' : 'aktualisiert'}',
    );
  }

  Future<void> setTaskStatus(WorkTask task, TaskStatus status) =>
      saveWorkTask(task.copyWith(status: status));

  Future<void> deleteWorkTask(String taskId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    // Titel vor dem Entfernen aus der In-Memory-Liste merken (für das Protokoll).
    final title = _taskTitleById(taskId);
    final summary =
        title == null ? 'Auftrag gelöscht' : 'Auftrag „$title" gelöscht';
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteWorkTask',
          () => _firestore.deleteWorkTask(orgId: orgId, taskId: taskId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Auftrag',
        entityId: taskId,
        summary: summary,
      );
      return;
    }
    _tasks = _tasks.where((task) => task.id != taskId).toList(growable: false);
    await _persistTasks();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Auftrag',
      entityId: taskId,
      summary: summary,
    );
  }

  /// Titel eines Auftrags aus der In-Memory-Liste (oder null, wenn unbekannt).
  String? _taskTitleById(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task.title;
    }
    return null;
  }

  Future<void> _persistTasks() =>
      DatabaseService.saveLocalWorkTasks(_tasks, scope: _localScope);

  // --- Speichermodus-Migration (H-H1) -------------------------------------

  /// Snapshot des aktuellen (Cloud-)Personal-Stands in den lokalen Speicher
  /// (cloud/hybrid → local). Abwesenheiten besitzt der ScheduleProvider und
  /// migriert sie selbst — hier bewusst ausgelassen.
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    await _persistTasks();
    await _persistPayroll();
    await _persistProfiles();
    await _persistEmployeeProfiles();
    await _persistSollzeitProfiles();
    await _persistOrgPayrollSettings();
    await _persistChildren();
    await _persistQualifications();
    await _persistAusbildungen();
    await _persistUrlaubskontoJahre();
    await _persistUrlaubsanpassungen();
    await _persistPayLineTypes();
  }

  /// Lädt die lokalen Personal-Daten beim Wechsel local→Cloud/Hybrid hoch
  /// (Upsert über deterministische Doc-IDs → idempotent).
  Future<void> syncLocalStateToCloud() async {
    if (_orgId == null) return;
    Future<void> push(String label, Future<void> Function() write) async {
      try {
        await write();
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud(personal:$label): $error');
      }
    }

    for (final t in List<WorkTask>.from(_tasks)) {
      await push('task', () => _firestore.saveWorkTask(t));
    }
    for (final r in List<PayrollRecord>.from(_payrollRecords)) {
      await push('payroll', () => _firestore.savePayrollRecord(r));
    }
    for (final p in List<PayrollProfile>.from(_payrollProfiles)) {
      await push('payrollProfile', () => _firestore.savePayrollProfile(p));
    }
    for (final e in List<EmployeeProfile>.from(_employeeProfiles)) {
      await push('employeeProfile', () => _firestore.saveEmployeeProfile(e));
    }
    for (final s in List<SollzeitProfile>.from(_sollzeitProfiles)) {
      await push('sollzeit', () => _firestore.saveSollzeitProfile(s));
    }
    for (final o in List<OrgPayrollSettings>.from(_orgPayrollSettings)) {
      await push('orgPayroll', () => _firestore.saveOrgPayrollSettings(o));
    }
    for (final c in List<EmployeeChild>.from(_children)) {
      await push('child', () => _firestore.saveEmployeeChild(c));
    }
    for (final q in List<EmployeeQualification>.from(_qualifications)) {
      await push('qualification', () => _firestore.saveEmployeeQualification(q));
    }
    for (final a in List<EmployeeAusbildung>.from(_ausbildungen)) {
      await push('ausbildung', () => _firestore.saveEmployeeAusbildung(a));
    }
    for (final k in List<UrlaubskontoJahr>.from(_urlaubskontoJahre)) {
      await push('urlaubskonto', () => _firestore.saveUrlaubskontoJahr(k));
    }
    for (final a in List<Urlaubsanpassung>.from(_urlaubsanpassungen)) {
      await push('urlaubsanpassung', () => _firestore.saveUrlaubsanpassung(a));
    }
    for (final t in List<PayLineType>.from(_payLineTypes)) {
      await push('payLineType', () => _firestore.savePayLineType(t));
    }
  }

  // --- Lohnabrechnungen ----------------------------------------------------

  Future<void> savePayrollRecord(PayrollRecord record) async {
    _assertAdmin();
    final orgId = _requireOrg();
    // Vor der ID-Vergabe ermitteln, ob die Abrechnung neu ist.
    final isNew = record.id == null || record.id!.isEmpty;
    // Deterministische ID (pro Mitarbeiter/Monat) für stabilen Upsert.
    final withMeta = record.copyWith(
      orgId: orgId,
      createdByUid: record.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    final summary =
        '${_memberLabel(prepared.userId)} '
        '${prepared.periodMonth.toString().padLeft(2, '0')}/${prepared.periodYear}: '
        'Brutto ${_euro(prepared.grossCents)} €, '
        'Netto ${_euro(prepared.netCents)} €';
    if (_usesFirestore &&
        await _tryFirestore(
          'savePayrollRecord',
          () => _firestore.savePayrollRecord(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Lohnabrechnung',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    _upsertLocal(_payrollRecords, prepared, (item) => item.id);
    _payrollRecords = [..._payrollRecords];
    await _persistPayroll();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Lohnabrechnung',
      entityId: prepared.id,
      summary: summary,
    );
  }

  Future<void> deletePayrollRecord(String recordId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePayrollRecord',
          () =>
              _firestore.deletePayrollRecord(orgId: orgId, recordId: recordId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Lohnabrechnung',
        entityId: recordId,
        summary: 'Lohnabrechnung gelöscht',
      );
      return;
    }
    _payrollRecords = _payrollRecords
        .where((record) => record.id != recordId)
        .toList(growable: false);
    await _persistPayroll();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Lohnabrechnung',
      entityId: recordId,
      summary: 'Lohnabrechnung gelöscht',
    );
  }

  /// Setzt den Freigabe-Status einer Abrechnung (Entwurf → Freigegeben →
  /// Bezahlt, oder Storniert). Bei Freigegeben/Bezahlt werden Freigeber + Zeit
  /// gestempelt; sonst geleert. Protokolliert die Statusänderung im Audit-Trail.
  Future<void> setPayrollStatus(
    PayrollRecord record,
    PayrollStatus status,
  ) async {
    _assertAdmin();
    final orgId = _requireOrg();
    // Übergang merken: nur Entwurf→final löst die Personalkosten-Buchung aus.
    final wasFinalized = record.status.isFinalized;
    final updated = status.isFinalized
        ? record.copyWith(
            orgId: orgId,
            status: status,
            finalizedByUid: _currentUser?.uid,
            finalizedAt: DateTime.now(),
          )
        : record.copyWith(
            orgId: orgId,
            status: status,
            clearFinalizedBy: true,
            clearFinalizedAt: true,
          );
    final prepared = updated.id == null
        ? updated.copyWith(id: updated.documentId)
        : updated;
    final summary = '${_memberLabel(prepared.userId)} '
        '${prepared.periodMonth.toString().padLeft(2, '0')}/${prepared.periodYear}: '
        'Status → ${status.label}';
    if (_usesFirestore &&
        await _tryFirestore(
          'setPayrollStatus',
          () => _firestore.savePayrollRecord(prepared),
        )) {
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Lohnabrechnung',
        entityId: prepared.id,
        summary: summary,
      );
      await _bookPersonnelCostIfNeeded(prepared, wasFinalized: wasFinalized);
      return;
    }
    _upsertLocal(_payrollRecords, prepared, (item) => item.id);
    _payrollRecords = [..._payrollRecords];
    await _persistPayroll();
    _safeNotify();
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Lohnabrechnung',
      entityId: prepared.id,
      summary: summary,
    );
    await _bookPersonnelCostIfNeeded(prepared, wasFinalized: wasFinalized);
  }

  /// Bucht die Personalkosten beim Übergang Entwurf→freigegeben/bezahlt genau
  /// einmal (H-A1). Idempotenz dreifach abgesichert: (1) nur beim Übergang
  /// (`!wasFinalized`), (2) nur wenn noch kein `journalEntryId` gesetzt ist,
  /// (3) deterministische Journal-Doc-ID im FinanceProvider. Best-effort —
  /// ein Fehler darf die Freigabe nie zurückrollen.
  Future<void> _bookPersonnelCostIfNeeded(
    PayrollRecord record, {
    required bool wasFinalized,
  }) async {
    final poster = _journalPoster;
    if (poster == null) return;
    if (!record.status.isFinalized || wasFinalized) return;
    if (record.journalEntryId != null) return;
    if (record.employerTotalCents <= 0) return;
    try {
      final journalId = await poster(
        record,
        primarySiteId: primarySiteIdForUser(record.userId),
        employeeLabel: _memberLabel(record.userId),
      );
      if (journalId == null) return;
      await _attachJournalEntryId(record, journalId);
    } catch (error) {
      AppLogger.warning('Personalkosten-Buchung fehlgeschlagen', error: error);
    }
  }

  /// Schreibt den Journal-Rückverweis auf den bereits gespeicherten Datensatz
  /// zurück (deterministische Doc-ID → idempotenter Upsert). KEIN erneutes
  /// Status-Audit — die Buchung selbst auditiert der FinanceProvider.
  Future<void> _attachJournalEntryId(
    PayrollRecord record,
    String journalId,
  ) async {
    final updated = record.copyWith(journalEntryId: journalId);
    final prepared = updated.id == null
        ? updated.copyWith(id: updated.documentId)
        : updated;
    if (_usesFirestore &&
        await _tryFirestore(
          'attachJournalEntryId',
          () => _firestore.savePayrollRecord(prepared),
        )) {
      return;
    }
    _upsertLocal(_payrollRecords, prepared, (item) => item.id);
    _payrollRecords = [..._payrollRecords];
    await _persistPayroll();
    _safeNotify();
  }

  /// Lohnlauf: gibt alle Entwurf-Abrechnungen eines Monats frei (Batch).
  Future<void> finalizeAllDrafts(int year, int month) async {
    _assertAdmin();
    final drafts = payrollForPeriod(year, month)
        .where((record) => record.status == PayrollStatus.entwurf)
        .toList(growable: false);
    for (final record in drafts) {
      await setPayrollStatus(record, PayrollStatus.freigegeben);
    }
  }

  Future<void> _persistPayroll() =>
      DatabaseService.saveLocalPayrollRecords(_payrollRecords,
          scope: _localScope);

  // --- Lohn-Stammdaten (PayrollProfile) ------------------------------------

  Future<void> savePayrollProfile(PayrollProfile profile) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final withMeta = profile.copyWith(
      orgId: orgId,
      createdByUid: profile.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    if (_usesFirestore &&
        await _tryFirestore(
          'savePayrollProfile',
          () => _firestore.savePayrollProfile(prepared),
        )) {
      return;
    }
    _upsertLocal(_payrollProfiles, prepared, (item) => item.id);
    _payrollProfiles = [..._payrollProfiles];
    await _persistProfiles();
    _safeNotify();
  }

  /// Merkt sich die Lohn-Stammdaten eines Mitarbeiters aus einer Abrechnung,
  /// damit die nächste Abrechnung vorbefüllt wird. Schreibt nur, wenn sich die
  /// relevanten Felder geändert haben (spart Firestore-Writes im Spark-Free-Tier).
  Future<void> rememberPayrollProfile({
    required String userId,
    required TaxClass taxClass,
    required PayrollEmploymentKind kind,
    required bool churchTax,
    String? federalState,
    int? monthlyGrossCents,
  }) async {
    if (!isAdmin) return;
    final orgId = _orgId;
    if (orgId == null) return;
    final existing = profileForUser(userId);
    final candidate = PayrollProfile(
      id: existing?.id,
      orgId: orgId,
      userId: userId,
      taxClass: taxClass,
      kind: kind,
      churchTax: churchTax,
      federalState: federalState,
      monthlyGrossCents: monthlyGrossCents,
      createdByUid: existing?.createdByUid,
      createdAt: existing?.createdAt,
    );
    if (existing != null && existing.sameMasterData(candidate)) {
      return; // unverändert -> kein Write
    }
    await savePayrollProfile(candidate);
  }

  Future<void> deletePayrollProfile(String userId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePayrollProfile',
          () => _firestore.deletePayrollProfile(orgId: orgId, userId: userId),
        )) {
      return;
    }
    _payrollProfiles = _payrollProfiles
        .where((profile) => profile.userId != userId)
        .toList(growable: false);
    await _persistProfiles();
    _safeNotify();
  }

  Future<void> _persistProfiles() =>
      DatabaseService.saveLocalPayrollProfiles(_payrollProfiles,
          scope: _localScope);

  // --- Personal-Stammakte (EmployeeProfile) --------------------------------

  Future<void> saveEmployeeProfile(EmployeeProfile profile) async {
    _assertAdmin();
    final orgId = _requireOrg();
    // Vor der ID-Vergabe ermitteln, ob die Stammakte neu ist.
    final isNew = profile.id == null || profile.id!.isEmpty;
    final withMeta = profile.copyWith(
      orgId: orgId,
      createdByUid: profile.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    final summary =
        'Mitarbeiterprofil ${_memberLabel(prepared.userId)} gespeichert';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveEmployeeProfile',
          () => _firestore.saveEmployeeProfile(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Mitarbeiterprofil',
        entityId: prepared.userId,
        summary: summary,
      );
      return;
    }
    _upsertLocal(_employeeProfiles, prepared, (item) => item.id);
    _employeeProfiles = [..._employeeProfiles];
    await _persistEmployeeProfiles();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Mitarbeiterprofil',
      entityId: prepared.userId,
      summary: summary,
    );
  }

  Future<void> deleteEmployeeProfile(String userId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteEmployeeProfile',
          () => _firestore.deleteEmployeeProfile(orgId: orgId, userId: userId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Mitarbeiterprofil',
        entityId: userId,
        summary: 'Mitarbeiterprofil gelöscht',
      );
      return;
    }
    _employeeProfiles = _employeeProfiles
        .where((profile) => profile.userId != userId)
        .toList(growable: false);
    await _persistEmployeeProfiles();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Mitarbeiterprofil',
      entityId: userId,
      summary: 'Mitarbeiterprofil gelöscht',
    );
  }

  Future<void> _persistEmployeeProfiles() =>
      DatabaseService.saveLocalEmployeeProfiles(_employeeProfiles,
          scope: _localScope);

  // --- Sollzeit-Profile (Arbeitszeitmodelle, gültig-ab) --------------------

  Future<void> saveSollzeitProfile(SollzeitProfile profile) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = profile.id == null || profile.id!.isEmpty;
    final prepared = profile.copyWith(
      orgId: orgId,
      createdByUid: profile.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Sollzeit-Modell ${_memberLabel(prepared.userId)} '
        '(ab ${_formatDate(prepared.gueltigAb)}) '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveSollzeitProfile',
          () => _firestore.saveSollzeitProfile(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Sollzeit',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('sollzeit'))
        : prepared;
    _upsertLocal(_sollzeitProfiles, withId, (item) => item.id);
    _sollzeitProfiles = [..._sollzeitProfiles];
    await _persistSollzeitProfiles();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Sollzeit',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deleteSollzeitProfile(String profileId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteSollzeitProfile',
          () => _firestore.deleteSollzeitProfile(
              orgId: orgId, profileId: profileId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Sollzeit',
        entityId: profileId,
        summary: 'Sollzeit-Modell gelöscht',
      );
      return;
    }
    _sollzeitProfiles = _sollzeitProfiles
        .where((profile) => profile.id != profileId)
        .toList(growable: false);
    await _persistSollzeitProfiles();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Sollzeit',
      entityId: profileId,
      summary: 'Sollzeit-Modell gelöscht',
    );
  }

  Future<void> _persistSollzeitProfiles() =>
      DatabaseService.saveLocalSollzeitProfiles(_sollzeitProfiles,
          scope: _localScope);

  /// **M0-Migration:** überträgt den Jahresurlaub aus den deprecaten Altfeldern
  /// (`EmployeeProfile.annualVacationDays` / `EmploymentContract.vacationDays`)
  /// **verbatim** in je ein `SollzeitProfile.urlaubstageJahr` (Vorrangregel §5.1,
  /// keine Skalierung – B1). **Idempotent**: Mitarbeiter mit bereits vorhandenem
  /// `SollzeitProfile` werden übersprungen (dort ist der Wert schon kanonisch).
  /// Gibt die Anzahl tatsächlich angelegter Profile zurück. Jede Anlage wird
  /// einzeln über [saveSollzeitProfile] auditiert.
  Future<int> migriereUrlaubstageInSollzeit() async {
    _assertAdmin();
    final orgId = _requireOrg();
    final now = DateTime.now();
    var migriert = 0;
    for (final member in _members) {
      final hatProfil =
          _sollzeitProfiles.any((p) => p.userId == member.uid);
      final profile = employeeProfileForUser(member.uid);
      final contract = contractForUser(member.uid);
      // Zukünftiges Eintrittsdatum NICHT als gueltigAb nehmen, sonst wäre das
      // Backfill-Profil für „heute" inaktiv und der Resolver fiele still aufs
      // Altfeld zurück (Review-Fund). null → Default 2020 im Mapper.
      final hire = profile?.hireDate;
      final gueltigAb = (hire != null && hire.isAfter(now)) ? null : hire;
      final mapped = buildUrlaubMigrationProfile(
        orgId: orgId,
        userId: member.uid,
        hasSollzeitProfile: hatProfil,
        annualVacationDays: profile?.annualVacationDays,
        vertragVacationDays: contract?.vacationDays,
        gueltigAb: gueltigAb,
      );
      if (mapped == null) continue;
      await saveSollzeitProfile(mapped);
      migriert++;
    }
    return migriert;
  }

  // --- HR-Sub-Entitäten: Kinder / Qualifikationen / Ausbildung (M-H) -------

  Future<void> saveEmployeeChild(EmployeeChild child) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = child.id == null || child.id!.isEmpty;
    final prepared = child.copyWith(
      orgId: orgId,
      createdByUid: child.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Kind ${prepared.anzeigeName} '
        '(${_memberLabel(prepared.userId)}) '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveEmployeeChild',
          () => _firestore.saveEmployeeChild(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Kind',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('child'))
        : prepared;
    _upsertLocal(_children, withId, (item) => item.id);
    _children = [..._children];
    await _persistChildren();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Kind',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deleteEmployeeChild(String childId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteEmployeeChild',
          () => _firestore.deleteEmployeeChild(orgId: orgId, childId: childId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Kind',
        entityId: childId,
        summary: 'Kind gelöscht',
      );
      return;
    }
    _children =
        _children.where((c) => c.id != childId).toList(growable: false);
    await _persistChildren();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Kind',
      entityId: childId,
      summary: 'Kind gelöscht',
    );
  }

  Future<void> _persistChildren() =>
      DatabaseService.saveLocalEmployeeChildren(_children, scope: _localScope);

  Future<void> saveEmployeeQualification(EmployeeQualification quali) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = quali.id == null || quali.id!.isEmpty;
    final prepared = quali.copyWith(
      orgId: orgId,
      createdByUid: quali.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Qualifikation ${prepared.qualificationName} '
        '(${_memberLabel(prepared.userId)}) '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveEmployeeQualification',
          () => _firestore.saveEmployeeQualification(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Qualifikation',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('quali'))
        : prepared;
    _upsertLocal(_qualifications, withId, (item) => item.id);
    _qualifications = [..._qualifications];
    await _persistQualifications();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Qualifikation',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deleteEmployeeQualification(String qualificationId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteEmployeeQualification',
          () => _firestore.deleteEmployeeQualification(
              orgId: orgId, qualificationId: qualificationId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Qualifikation',
        entityId: qualificationId,
        summary: 'Qualifikation gelöscht',
      );
      return;
    }
    _qualifications = _qualifications
        .where((q) => q.id != qualificationId)
        .toList(growable: false);
    await _persistQualifications();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Qualifikation',
      entityId: qualificationId,
      summary: 'Qualifikation gelöscht',
    );
  }

  Future<void> _persistQualifications() =>
      DatabaseService.saveLocalEmployeeQualifications(_qualifications,
          scope: _localScope);

  Future<void> saveEmployeeAusbildung(EmployeeAusbildung ausbildung) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = ausbildung.id == null || ausbildung.id!.isEmpty;
    final prepared = ausbildung.copyWith(
      orgId: orgId,
      createdByUid: ausbildung.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Ausbildung ${prepared.bezeichnung} '
        '(${_memberLabel(prepared.userId)}) '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveEmployeeAusbildung',
          () => _firestore.saveEmployeeAusbildung(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Ausbildung',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('ausbildung'))
        : prepared;
    _upsertLocal(_ausbildungen, withId, (item) => item.id);
    _ausbildungen = [..._ausbildungen];
    await _persistAusbildungen();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Ausbildung',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deleteEmployeeAusbildung(String ausbildungId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteEmployeeAusbildung',
          () => _firestore.deleteEmployeeAusbildung(
              orgId: orgId, ausbildungId: ausbildungId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Ausbildung',
        entityId: ausbildungId,
        summary: 'Ausbildung gelöscht',
      );
      return;
    }
    _ausbildungen = _ausbildungen
        .where((a) => a.id != ausbildungId)
        .toList(growable: false);
    await _persistAusbildungen();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Ausbildung',
      entityId: ausbildungId,
      summary: 'Ausbildung gelöscht',
    );
  }

  Future<void> _persistAusbildungen() =>
      DatabaseService.saveLocalEmployeeAusbildungen(_ausbildungen,
          scope: _localScope);

  // --- Urlaubskonto: Jahres-Vortrag + Korrektur-Ledger (M-U) ---------------

  /// Legt das Jahres-Vortragsdoc an/aktualisiert es (deterministische Doc-ID
  /// `{userId}-{jahr}`). Admin-only, urlaubsrechtlich relevant → Audit.
  Future<void> saveUrlaubskontoJahr(UrlaubskontoJahr konto) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = urlaubskontoFor(konto.userId, konto.jahr) == null;
    final prepared = konto.copyWith(
      id: konto.documentId,
      orgId: orgId,
      createdByUid: konto.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Urlaubskonto ${prepared.jahr} '
        '${_memberLabel(prepared.userId)} '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveUrlaubskontoJahr',
          () => _firestore.saveUrlaubskontoJahr(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Urlaubskonto',
        entityId: prepared.documentId,
        summary: summary,
      );
      return;
    }
    _upsertLocal(_urlaubskontoJahre, prepared, (item) => item.id);
    _urlaubskontoJahre = [..._urlaubskontoJahre];
    await _persistUrlaubskontoJahre();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Urlaubskonto',
      entityId: prepared.documentId,
      summary: summary,
    );
  }

  Future<void> _persistUrlaubskontoJahre() =>
      DatabaseService.saveLocalUrlaubskontoJahre(_urlaubskontoJahre,
          scope: _localScope);

  Future<void> saveUrlaubsanpassung(Urlaubsanpassung anpassung) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = anpassung.id == null || anpassung.id!.isEmpty;
    final prepared = anpassung.copyWith(
      orgId: orgId,
      createdByUid: anpassung.createdByUid ?? _currentUser?.uid,
    );
    final vorzeichen = prepared.tage >= 0 ? '+' : '';
    final summary = 'Urlaubs-Anpassung $vorzeichen${prepared.tage} Tage '
        '(${_memberLabel(prepared.userId)}, ${prepared.jahr}) '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveUrlaubsanpassung',
          () => _firestore.saveUrlaubsanpassung(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Urlaubs-Anpassung',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('urlaubsanpassung'))
        : prepared;
    _upsertLocal(_urlaubsanpassungen, withId, (item) => item.id);
    _urlaubsanpassungen = [..._urlaubsanpassungen];
    await _persistUrlaubsanpassungen();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Urlaubs-Anpassung',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deleteUrlaubsanpassung(String anpassungId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteUrlaubsanpassung',
          () => _firestore.deleteUrlaubsanpassung(
              orgId: orgId, anpassungId: anpassungId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Urlaubs-Anpassung',
        entityId: anpassungId,
        summary: 'Urlaubs-Anpassung gelöscht',
      );
      return;
    }
    _urlaubsanpassungen = _urlaubsanpassungen
        .where((a) => a.id != anpassungId)
        .toList(growable: false);
    await _persistUrlaubsanpassungen();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Urlaubs-Anpassung',
      entityId: anpassungId,
      summary: 'Urlaubs-Anpassung gelöscht',
    );
  }

  Future<void> _persistUrlaubsanpassungen() =>
      DatabaseService.saveLocalUrlaubsanpassungen(_urlaubsanpassungen,
          scope: _localScope);

  // --- Lohnarten-Katalog (M-L, org-weite Vorlagen) -------------------------

  /// Legt eine Lohnart an oder aktualisiert sie (Auto-ID). Admin-only, fachlich
  /// relevant → Audit auf dem Erfolgspfad.
  Future<void> savePayLineType(PayLineType type) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = type.id == null || type.id!.isEmpty;
    final prepared = type.copyWith(
      orgId: orgId,
      createdByUid: type.createdByUid ?? _currentUser?.uid,
    );
    final summary =
        'Lohnart „${prepared.name}" ${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'savePayLineType',
          () => _firestore.savePayLineType(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Lohnart',
        entityId: prepared.id,
        summary: summary,
      );
      return;
    }
    final withId = prepared.id == null
        ? prepared.copyWith(id: _nextLocalId('payLineType'))
        : prepared;
    _upsertLocal(_payLineTypes, withId, (item) => item.id);
    _payLineTypes = [..._payLineTypes];
    await _persistPayLineTypes();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Lohnart',
      entityId: withId.id,
      summary: summary,
    );
  }

  Future<void> deletePayLineType(String typeId) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    final name = _payLineTypes
        .firstWhere(
          (t) => t.id == typeId,
          orElse: () => const PayLineType(orgId: '', name: ''),
        )
        .name;
    final summary =
        name.isEmpty ? 'Lohnart gelöscht' : 'Lohnart „$name" gelöscht';
    if (_usesFirestore &&
        await _tryFirestore(
          'deletePayLineType',
          () => _firestore.deletePayLineType(orgId: orgId, typeId: typeId),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Lohnart',
        entityId: typeId,
        summary: summary,
      );
      return;
    }
    _payLineTypes =
        _payLineTypes.where((t) => t.id != typeId).toList(growable: false);
    await _persistPayLineTypes();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Lohnart',
      entityId: typeId,
      summary: summary,
    );
  }

  Future<void> _persistPayLineTypes() =>
      DatabaseService.saveLocalPayLineTypes(_payLineTypes, scope: _localScope);

  // --- Lohn-Konfiguration (org-/jahr-spezifisch, AG-Sätze/Umlagen) ---------

  /// Legt die org-Lohn-Konfiguration für ein Jahr an oder aktualisiert sie
  /// (deterministische Doc-ID = Jahr). Admin-only, fachlich relevant → Audit.
  Future<void> saveOrgPayrollSettings(OrgPayrollSettings config) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = orgPayrollSettingsForYear(config.jahr) == null;
    final prepared = config.copyWith(
      id: config.documentId, // deterministisch = Bezugsjahr
      orgId: orgId,
      createdByUid: config.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Lohn-Einstellungen ${prepared.jahr} '
        '${isNew ? 'angelegt' : 'aktualisiert'}';
    if (_usesFirestore &&
        await _tryFirestore(
          'saveOrgPayrollSettings',
          () => _firestore.saveOrgPayrollSettings(prepared),
        )) {
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Lohn-Einstellungen',
        entityId: prepared.documentId,
        summary: summary,
      );
      return;
    }
    _upsertLocal(_orgPayrollSettings, prepared, (item) => item.id);
    _orgPayrollSettings = [..._orgPayrollSettings];
    await _persistOrgPayrollSettings();
    _safeNotify();
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Lohn-Einstellungen',
      entityId: prepared.documentId,
      summary: summary,
    );
  }

  /// Setzt die org-Lohn-Konfiguration eines Jahres zurück (→ wieder Defaults).
  Future<void> deleteOrgPayrollSettings(int jahr) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    if (_usesFirestore &&
        await _tryFirestore(
          'deleteOrgPayrollSettings',
          () => _firestore.deleteOrgPayrollSettings(orgId: orgId, jahr: jahr),
        )) {
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Lohn-Einstellungen',
        entityId: jahr.toString(),
        summary: 'Lohn-Einstellungen $jahr zurückgesetzt',
      );
      return;
    }
    _orgPayrollSettings = _orgPayrollSettings
        .where((config) => config.jahr != jahr)
        .toList(growable: false);
    await _persistOrgPayrollSettings();
    _safeNotify();
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Lohn-Einstellungen',
      entityId: jahr.toString(),
      summary: 'Lohn-Einstellungen $jahr zurückgesetzt',
    );
  }

  Future<void> _persistOrgPayrollSettings() =>
      DatabaseService.saveLocalOrgPayrollSettings(_orgPayrollSettings,
          scope: _localScope);

  // --- Infrastruktur -------------------------------------------------------

  /// Versucht eine Firestore-Mutation. Erfolg -> true. Im Hybrid-Modus bei
  /// Fehler -> false (lokaler Fallback), sonst rethrow.
  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!usesHybridStorage) rethrow;
      AppLogger.warning(
        'Personal: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  void _assertAdmin() {
    if (!isAdmin) {
      throw StateError('Nur Admins dürfen den Personal-Bereich bearbeiten.');
    }
  }

  String _requireOrg() {
    final orgId = _orgId;
    if (orgId == null) {
      throw StateError('Keine Organisation aktiv.');
    }
    return orgId;
  }

  String _nextLocalId(String prefix) {
    _localSeq += 1;
    return 'local-$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localSeq';
  }

  void _upsertLocal<T>(List<T> list, T item, String? Function(T) idOf) {
    final id = idOf(item);
    final index = list.indexWhere((existing) => idOf(existing) == id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _setError(Object error) {
    _loading = false;
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  /// Macht Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar.
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Personaldaten konnten nicht geladen werden. Bitte später erneut versuchen.';
    _safeNotify();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}
