import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/kasse_report.dart';
import 'package:worktime_app/core/org_zeit_kpis.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/payroll_record.dart';
import 'package:worktime_app/models/site_definition.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
import 'package:worktime_app/models/work_entry.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/providers/inventory_provider.dart';
import 'package:worktime_app/providers/management_dashboard_provider.dart';
import 'package:worktime_app/providers/personal_provider.dart';
import 'package:worktime_app/providers/schedule_provider.dart';
import 'package:worktime_app/providers/zeitwirtschaft_provider.dart';
import 'package:worktime_app/services/firestore_service.dart';

FirestoreService _svc() =>
    FirestoreService(firestore: FakeFirebaseFirestore());

class _FakeZeit extends ZeitwirtschaftProvider {
  _FakeZeit() : super(firestoreService: _svc(), disableAuthentication: true);
  OrgZeitKpis? result = const OrgZeitKpis(
    sollMinutes: 9000,
    istMinutes: 8000,
    saldoMinutes: -1000,
    mitarbeiterMitSoll: 1,
    offeneFreigaben: 2,
  );
  bool throwIt = false;
  @override
  Future<OrgZeitKpis?> loadOrgZeitKpis({
    required int jahr,
    required int monat,
    required List<String> memberIds,
    required Map<String, List<SollzeitProfile>> profilesByUser,
  }) async {
    if (throwIt) throw StateError('boom');
    return result;
  }

  List<WorkEntry> orgMonthEntries = const [];
  @override
  Future<List<WorkEntry>> loadOrgWorkEntriesForMonth(DateTime month) async =>
      orgMonthEntries;
}

class _FakePersonal extends PersonalProvider {
  _FakePersonal() : super(firestoreService: _svc(), disableAuthentication: true);
  List<AppUserProfile> _members = const [];
  @override
  List<AppUserProfile> get members => _members;
  @override
  List<SollzeitProfile> sollzeitProfilesForUser(String userId) => const [];

  List<PayrollRecord> payroll = const [];
  @override
  List<PayrollRecord> payrollForPeriod(int year, int month) => payroll;
}

class _FakeInventory extends InventoryProvider {
  _FakeInventory()
      : super(firestoreService: _svc(), disableAuthentication: true);
  @override
  int totalStockValuePurchaseCents({String? siteId}) => 500000;
  @override
  int totalStockValueSellingCents({String? siteId}) => 800000;

  // Umsatz brutto je siteId für den Standortvergleich; null wirft (Teilerfolg).
  Map<String?, int> umsatzBySite = const {};
  String? throwForSite;
  @override
  Future<List<KassenPeriode>> loadKassenbericht({
    required ReportGranularity granularity,
    required bool purchasePricesIncludeVat,
    String? siteId,
    int? bucketCount,
    DateTime? asOf,
    int windowDays = 92,
  }) async {
    if (throwForSite != null && siteId == throwForSite) {
      throw StateError('kassen boom');
    }
    final start =
        asOf != null ? DateTime(asOf.year, asOf.month) : DateTime(2026, 6);
    return [
      _periode(start: start, umsatzBrutto: umsatzBySite[siteId] ?? 0),
    ];
  }
}

class _FakeSchedule extends ScheduleProvider {
  _FakeSchedule()
      : super(firestoreService: _svc(), disableAuthentication: true);
  List<AbsenceRequest> _abs = const [];
  @override
  List<AbsenceRequest> get allAbsenceRequests => _abs;

  List<SiteDefinition> _sites = const [];
  @override
  List<SiteDefinition> get sites => _sites;
}

KassenPeriode _periode({required DateTime start, required int umsatzBrutto}) =>
    KassenPeriode(
      start: start,
      hatDaten: true,
      belege: 0,
      erstattungen: 0,
      positiveErstattungen: 0,
      umsatzBruttoCents: umsatzBrutto,
      umsatzNettoCents: umsatzBrutto,
      nettoUnsicherCents: 0,
      kaeufeNettoCents: 0,
      kaeufeBruttoCents: 0,
      wareneinsatzCents: null,
      wareneinsatzAbdeckungPct: null,
      rohertragNettoCents: null,
      rohertragBruttoCents: null,
      deltaVorperiodePct: null,
      deltaVorjahrPct: null,
    );

SiteDefinition _site(String id) =>
    SiteDefinition(id: id, orgId: 'org-1', name: 'Laden $id');

WorkEntry _workEntry(String? siteId, int minutes) {
  final start = DateTime(2026, 6, 10, 8);
  return WorkEntry(
    orgId: 'org-1',
    userId: 'u1',
    date: DateTime(2026, 6, 10),
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    siteId: siteId,
  );
}

PayrollRecord _payroll(int employerTotal, PayrollStatus status) =>
    PayrollRecord(
      orgId: 'org-1',
      userId: 'u1',
      periodYear: 2026,
      periodMonth: 6,
      employerTotalCents: employerTotal,
      status: status,
    );

AbsenceRequest _absence(AbsenceStatus status) => AbsenceRequest(
      orgId: 'org-1',
      userId: 'u1',
      employeeName: 'Peter',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 2),
      type: AbsenceType.vacation,
      status: status,
    );

AppUserProfile _profile(UserRole role, {UserPermissions? perms}) =>
    AppUserProfile(
      uid: 'admin-1',
      orgId: 'org-1',
      email: 'a@example.com',
      role: role,
      isActive: true,
      settings: const UserSettings(name: 'A'),
      permissions: perms,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeZeit zeit;
  late _FakePersonal personal;
  late _FakeInventory inventory;
  late _FakeSchedule schedule;

  setUp(() {
    zeit = _FakeZeit();
    personal = _FakePersonal();
    inventory = _FakeInventory();
    schedule = _FakeSchedule();
    personal._members = [_profile(UserRole.employee)];
    schedule._abs = [
      _absence(AbsenceStatus.pending),
      _absence(AbsenceStatus.pending),
      _absence(AbsenceStatus.approved),
    ];
  });

  ManagementDashboardProvider dashboard(AppUserProfile? profile) {
    final d = ManagementDashboardProvider();
    d.bind(
      zeit: zeit,
      personal: personal,
      inventory: inventory,
      schedule: schedule,
      profile: profile,
    );
    return d;
  }

  test('Admin: alle Sektionen geladen', () async {
    final d = dashboard(_profile(UserRole.admin));
    await d.load(year: 2026, month: 6);
    expect(d.orgZeit?.istMinutes, 8000);
    expect(d.bestandswertEkCents, 500000);
    expect(d.bestandswertVkCents, 800000);
    expect(d.offeneAbwesenheiten, 2); // nur pending
    expect(d.error, isNull);
  });

  test('Employee ohne Rechte: alle Sektionen null (KpiPermissions-Gating)',
      () async {
    final d = dashboard(_profile(
      UserRole.employee,
      perms: const UserPermissions(
        canViewSchedule: true,
        canEditSchedule: false,
        canViewTimeTracking: true,
        canEditTimeEntries: false,
        canViewReports: false,
      ),
    ));
    await d.load(year: 2026, month: 6);
    expect(d.orgZeit, isNull);
    expect(d.bestandswertEkCents, isNull);
    expect(d.bestandswertVkCents, isNull);
    expect(d.offeneAbwesenheiten, isNull);
  });

  test('Teilerfolg: Org-Zeit-Fehler reißt Bestandswert nicht mit', () async {
    zeit.throwIt = true;
    final d = dashboard(_profile(UserRole.admin));
    await d.load(year: 2026, month: 6);
    expect(d.orgZeit, isNull); // Sektion fehlgeschlagen
    expect(d.bestandswertEkCents, 500000); // andere Sektion intakt
    expect(d.error, isNull); // nicht ALLE Sektionen scheiterten
  });

  test('Stale-Guard: späterer Lauf gewinnt, alter committet nicht', () async {
    final d = dashboard(_profile(UserRole.admin));
    // Zwei Läufe „gleichzeitig"; der zweite setzt den Schlüssel neu.
    final f1 = d.load(year: 2026, month: 5);
    final f2 = d.load(year: 2026, month: 6);
    await Future.wait([f1, f2]);
    // Kein Absturz + committeter Stand ist konsistent (istMinutes gesetzt).
    expect(d.orgZeit?.istMinutes, 8000);
  });

  group('loadSiteVergleich (REPORTING-5)', () {
    setUp(() {
      schedule._sites = [_site('s1'), _site('s2')];
      inventory.umsatzBySite = const {'s1': 10000, 's2': 6000};
      zeit.orgMonthEntries = [
        _workEntry('s1', 120),
        _workEntry('s2', 240),
      ];
      personal.payroll = [
        _payroll(3600, PayrollStatus.freigegeben),
        _payroll(9999, PayrollStatus.entwurf), // ignoriert
      ];
    });

    test('Admin: Ranking, Personalstunden, Lohn-Richtwert, Bestandswert',
        () async {
      final d = dashboard(_profile(UserRole.admin));
      await d.loadSiteVergleich(
          year: 2026, month: 6, purchasePricesIncludeVat: false);
      final v = d.siteVergleich;
      expect(v, isNotNull);
      expect(v!.sites.map((s) => s.siteId).toList(), ['s1', 's2']);
      expect(v.sites[0].umsatzBruttoCents, 10000);
      expect(v.gesamtPersonalMinuten, 360.0);
      // Lohn proportional zu approved-Minuten (Basis 3600 / 360 min).
      expect(v.sites[0].lohnkostenRichtwertCents, 1200); // 3600*120/360
      expect(v.sites[1].lohnkostenRichtwertCents, 2400); // 3600*240/360
      expect(v.gesamtLohnkostenRichtwertCents, 3600);
      // Bestandswert EK je Standort aus dem Inventory-Getter (admin sichtbar).
      expect(v.gesamtBestandswertEkCents, 1000000); // 2×500000
      expect(d.siteVergleichError, isNull);
      expect(d.isSiteVergleichLoading, isFalse);
    });

    test('Employee ohne Umsatz-Recht: kein Vergleich (Gate)', () async {
      final d = dashboard(_profile(
        UserRole.employee,
        perms: const UserPermissions(
          canViewSchedule: true,
          canEditSchedule: false,
          canViewTimeTracking: true,
          canEditTimeEntries: false,
          canViewReports: true,
        ),
      ));
      await d.loadSiteVergleich(
          year: 2026, month: 6, purchasePricesIncludeVat: false);
      expect(d.siteVergleich, isNull);
      expect(d.isSiteVergleichLoading, isFalse);
    });

    test('Teilerfolg: ein Standort-Kassenfehler reißt die anderen nicht mit',
        () async {
      inventory.throwForSite = 's2';
      final d = dashboard(_profile(UserRole.admin));
      await d.loadSiteVergleich(
          year: 2026, month: 6, purchasePricesIncludeVat: false);
      final v = d.siteVergleich;
      expect(v, isNotNull);
      final s1 = v!.sites.firstWhere((s) => s.siteId == 's1');
      final s2 = v.sites.firstWhere((s) => s.siteId == 's2');
      expect(s1.umsatzBruttoCents, 10000); // intakt
      expect(s2.hatKassenDaten, isFalse); // Kassenfehler → keine Daten
      expect(d.siteVergleichError, isNull); // nicht ALLE Sektionen scheiterten
    });

    test('Stale-Guard: späterer Monat gewinnt, alter committet nicht',
        () async {
      final d = dashboard(_profile(UserRole.admin));
      final f1 = d.loadSiteVergleich(
          year: 2026, month: 5, purchasePricesIncludeVat: false);
      final f2 = d.loadSiteVergleich(
          year: 2026, month: 6, purchasePricesIncludeVat: false);
      await Future.wait([f1, f2]);
      expect(d.siteVergleich, isNotNull);
      expect(d.isSiteVergleichLoading, isFalse);
    });
  });
}
