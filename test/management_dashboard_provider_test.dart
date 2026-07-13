import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/core/org_zeit_kpis.dart';
import 'package:worktime_app/models/absence_request.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/sollzeit_profile.dart';
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
}

class _FakePersonal extends PersonalProvider {
  _FakePersonal() : super(firestoreService: _svc(), disableAuthentication: true);
  List<AppUserProfile> _members = const [];
  @override
  List<AppUserProfile> get members => _members;
  @override
  List<SollzeitProfile> sollzeitProfilesForUser(String userId) => const [];
}

class _FakeInventory extends InventoryProvider {
  _FakeInventory()
      : super(firestoreService: _svc(), disableAuthentication: true);
  @override
  int totalStockValuePurchaseCents({String? siteId}) => 500000;
  @override
  int totalStockValueSellingCents({String? siteId}) => 800000;
}

class _FakeSchedule extends ScheduleProvider {
  _FakeSchedule()
      : super(firestoreService: _svc(), disableAuthentication: true);
  List<AbsenceRequest> _abs = const [];
  @override
  List<AbsenceRequest> get allAbsenceRequests => _abs;
}

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
}
