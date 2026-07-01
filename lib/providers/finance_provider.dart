import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/daily_closing.dart';
import '../core/daily_closing_posting.dart';
import '../core/datev_export.dart';
import '../core/finance_analytics.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/customer_order.dart';
import '../models/finance_models.dart';
import '../models/payroll_record.dart';
import '../models/purchase_order.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import 'audit_sink.dart';

/// Zustand des Finanzbereichs (nur Admin): Kosten-Allokationsmodell mit
/// Kostenstellen, Kostenarten, Buchungsjournal und Plan-Budgets. Das Ist wird
/// stets aus den Buchungen abgeleitet ([FinanceAnalytics]), nie gespeichert.
///
/// Speicher-Verhalten wie [PersonalProvider]/[InventoryProvider]: Cloud/Hybrid
/// über Firestore-Streams (Offline-Cache), local über SharedPreferences;
/// schreibende Operationen fallen im Hybrid-Modus offline lokal zurück.
class FinanceProvider extends ChangeNotifier {
  FinanceProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestore = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestore;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  AuditSink? _audit;

  /// Verbindet das Änderungsprotokoll (best-effort). Wird in main.dart gesetzt.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  StreamSubscription<List<CostCenter>>? _costCentersSub;
  StreamSubscription<List<CostType>>? _costTypesSub;
  StreamSubscription<List<JournalEntry>>? _journalSub;
  StreamSubscription<List<Budget>>? _budgetsSub;

  AppUserProfile? _currentUser;
  List<CostCenter> _costCenters = [];
  List<CostType> _costTypes = [];
  List<JournalEntry> _journalEntries = [];
  List<Budget> _budgets = [];
  DatevExportConfig _datevConfig = const DatevExportConfig();

  bool _loading = false;
  String? _errorMessage;
  bool _disposed = false;
  int _localSeq = 0;
  String? _lastSessionKey;

  // --- Getter --------------------------------------------------------------

  List<CostCenter> get costCenters => _costCenters;
  List<CostType> get costTypes => _costTypes;
  List<JournalEntry> get journalEntries => _journalEntries;
  List<Budget> get budgets => _budgets;
  DatevExportConfig get datevConfig => _datevConfig;
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

  // --- Abgeleitete Sichten / Analytik --------------------------------------

  CostCenter? costCenterById(String id) {
    for (final c in _costCenters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Aktive Kostenstelle, die einem Standort zugeordnet ist (H-C1). Liefert nur
  /// eine **Vorbelegung** für die automatische Kostenstellen-Auflösung
  /// (Personalkosten-/Wareneinsatz-Buchung); bei mehreren Treffern gewinnt die
  /// mit der kleinsten [CostCenter.number] (deterministisch, nicht 1:1-Annahme).
  CostCenter? costCenterForSite(String? siteId) {
    if (siteId == null || siteId.isEmpty) return null;
    final matches = _costCenters
        .where((c) => c.isActive && c.siteId == siteId)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return matches.isEmpty ? null : matches.first;
  }

  CostType? costTypeById(String id) {
    for (final t in _costTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Buchungen eines Jahres, nach Datum absteigend.
  List<JournalEntry> journalForYear(int year) {
    final list = _journalEntries.where((e) => e.date.year == year).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Jahre mit Buchungen (absteigend) – für den Jahresfilter.
  List<int> get yearsWithEntries {
    final years = _journalEntries.map((e) => e.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<CostCenterReport> costCenterReports(int year) =>
      FinanceAnalytics.costCenterReports(
          _costCenters, _budgets, _journalEntries, year);

  List<MonthBucket> monthlyBreakdown(int year) =>
      FinanceAnalytics.monthlyBreakdown(_journalEntries, year);

  int totalExpenses(int year) =>
      FinanceAnalytics.totalExpenses(_journalEntries, year);
  int totalCredits(int year) =>
      FinanceAnalytics.totalCredits(_journalEntries, year);
  int totalActual(int year) =>
      FinanceAnalytics.totalActual(_journalEntries, year);
  int totalPlanned(int year) =>
      FinanceAnalytics.totalPlanned(_costCenters, _budgets, year);

  // --- Session -------------------------------------------------------------

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

    // DATEV-Export-Konfiguration ist lokal/gerätegebunden – in jedem
    // Speichermodus aus den SharedPreferences laden.
    _datevConfig = await DatabaseService.loadLocalDatevConfig(scope: _localScope) ??
        const DatevExportConfig();

    if (_usesFirestore) {
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      _safeNotify();
    }
  }

  /// Speichert die DATEV-Export-Konfiguration (lokal, admin-only).
  Future<void> saveDatevConfig(DatevExportConfig config) async {
    _assertAdmin();
    _datevConfig = config;
    await DatabaseService.saveLocalDatevConfig(config, scope: _localScope);
    _safeNotify();
  }

  void _startFirestoreSubscriptions(String orgId) {
    _loading = true;
    _safeNotify();

    _costCentersSub = _firestore.watchCostCenters(orgId).listen((items) {
      _costCenters = items;
      _loading = false;
      _safeNotify();
    }, onError: _setError);

    _costTypesSub = _firestore.watchCostTypes(orgId).listen((items) {
      _costTypes = items;
      _safeNotify();
    }, onError: _setError);

    _journalSub = _firestore.watchJournalEntries(orgId).listen((items) {
      _journalEntries = items;
      _safeNotify();
    }, onError: _setError);

    _budgetsSub = _firestore.watchBudgets(orgId).listen((items) {
      _budgets = items;
      _safeNotify();
    }, onError: _setError);
  }

  Future<void> _loadLocalData() async {
    final scope = _localScope;
    _costCenters = await DatabaseService.loadLocalCostCenters(scope: scope);
    _costTypes = await DatabaseService.loadLocalCostTypes(scope: scope);
    _journalEntries =
        await DatabaseService.loadLocalJournalEntries(scope: scope);
    _budgets = await DatabaseService.loadLocalBudgets(scope: scope);
  }

  Future<void> _cancelSubscriptions() async {
    await _costCentersSub?.cancel();
    await _costTypesSub?.cancel();
    await _journalSub?.cancel();
    await _budgetsSub?.cancel();
    _costCentersSub = null;
    _costTypesSub = null;
    _journalSub = null;
    _budgetsSub = null;
  }

  void _resetData() {
    _costCenters = [];
    _costTypes = [];
    _journalEntries = [];
    _budgets = [];
    _datevConfig = const DatevExportConfig();
    _loading = false;
  }

  // --- Kostenstellen -------------------------------------------------------

  Future<void> saveCostCenter(CostCenter center) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = center.id == null || center.id!.isEmpty;
    final prepared = center.copyWith(
      orgId: orgId,
      createdByUid: center.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Kostenstelle ${prepared.number} ${prepared.name}';
    await _persist<CostCenter>(
      label: 'saveCostCenter',
      cloud: () => _firestore.saveCostCenter(prepared),
      localList: () => _costCenters,
      assignId: () => prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('cc'))
          : prepared,
      setList: (list) => _costCenters = list,
      persist: _persistCostCenters,
      audit: () => _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Kostenstelle',
        entityId: prepared.id,
        summary: summary,
      ),
      idOf: (c) => c.id,
    );
  }

  Future<void> deleteCostCenter(String id) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    await _persistDelete(
      label: 'deleteCostCenter',
      cloud: () => _firestore.deleteCostCenter(orgId: orgId, id: id),
      removeLocal: () =>
          _costCenters = _costCenters.where((c) => c.id != id).toList(),
      persist: _persistCostCenters,
      audit: () => _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Kostenstelle',
        entityId: id,
        summary: 'Kostenstelle gelöscht',
      ),
    );
  }

  // --- Kostenarten ---------------------------------------------------------

  Future<void> saveCostType(CostType type) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = type.id == null || type.id!.isEmpty;
    final prepared = type.copyWith(
      orgId: orgId,
      createdByUid: type.createdByUid ?? _currentUser?.uid,
    );
    final summary = 'Kostenart ${prepared.number} ${prepared.name}';
    await _persist<CostType>(
      label: 'saveCostType',
      cloud: () => _firestore.saveCostType(prepared),
      localList: () => _costTypes,
      assignId: () => prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('ct'))
          : prepared,
      setList: (list) => _costTypes = list,
      persist: _persistCostTypes,
      audit: () => _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Kostenart',
        entityId: prepared.id,
        summary: summary,
      ),
      idOf: (t) => t.id,
    );
  }

  Future<void> deleteCostType(String id) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    await _persistDelete(
      label: 'deleteCostType',
      cloud: () => _firestore.deleteCostType(orgId: orgId, id: id),
      removeLocal: () =>
          _costTypes = _costTypes.where((t) => t.id != id).toList(),
      persist: _persistCostTypes,
      audit: () => _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Kostenart',
        entityId: id,
        summary: 'Kostenart gelöscht',
      ),
    );
  }

  // --- Buchungsjournal -----------------------------------------------------

  Future<void> saveJournalEntry(JournalEntry entry) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = entry.id == null || entry.id!.isEmpty;
    final prepared = entry.copyWith(
      orgId: orgId,
      createdByUid: entry.createdByUid ?? _currentUser?.uid,
    );
    final summary =
        '${prepared.description}: ${_euro(prepared.amountCents)} € '
        '(${costCenterById(prepared.costCenterId)?.name ?? 'Kostenstelle'})';
    await _persist<JournalEntry>(
      label: 'saveJournalEntry',
      cloud: () => _firestore.saveJournalEntry(prepared),
      localList: () => _journalEntries,
      assignId: () => prepared.id == null
          ? prepared.copyWith(id: _nextLocalId('je'))
          : prepared,
      setList: (list) => _journalEntries = list,
      persist: _persistJournal,
      audit: () => _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Buchung',
        entityId: prepared.id,
        summary: summary,
      ),
      idOf: (e) => e.id,
    );
  }

  Future<void> deleteJournalEntry(String id) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    await _persistDelete(
      label: 'deleteJournalEntry',
      cloud: () => _firestore.deleteJournalEntry(orgId: orgId, id: id),
      removeLocal: () =>
          _journalEntries = _journalEntries.where((e) => e.id != id).toList(),
      persist: _persistJournal,
      audit: () => _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Buchung',
        entityId: id,
        summary: 'Buchung gelöscht',
      ),
    );
  }

  // --- Auto-Buchung Personalkosten (H-A1) ---------------------------------

  /// Bucht die Personalkosten eines freigegebenen [PayrollRecord] automatisch
  /// als [JournalEntry]. **Idempotent**: deterministische Doc-ID
  /// `pay-<documentId>` → erneutes Buchen überschreibt denselben Beleg statt zu
  /// duplizieren (kein Doppelbuchungs-Risiko, auch im hybrid-Fallback). Liefert
  /// die Journal-ID oder `null`, wenn **nicht** gebucht wurde (kein Recht/Org,
  /// Betrag 0, oder Kostenstelle/-art nicht eindeutig auflösbar) — in dem Fall
  /// bewusst KEINE stille Falschbuchung; der Admin bucht dann manuell.
  Future<String?> postPersonnelCostJournal(
    PayrollRecord record, {
    String? primarySiteId,
    String employeeLabel = 'Mitarbeiter',
  }) async {
    if (!isAdmin || _orgId == null) return null;
    if (record.employerTotalCents <= 0) return null;
    final costCenter = _resolveSiteCostCenter(primarySiteId);
    final costType = _resolveCostTypeByNeedles(_personnelNeedles);
    if (costCenter?.id == null || costType?.id == null) {
      AppLogger.warning(
        'Personalkosten-Buchung übersprungen: Kostenstelle/-art nicht '
        'eindeutig (Standort-Kostenstelle via siteId hinterlegen oder eine '
        '„Personalkosten"-Kostenart anlegen).',
      );
      return null;
    }
    final journalId = 'pay-${record.documentId}';
    // Buchungsdatum = Monatsletzter der Abrechnungsperiode (Tag 0 des Folgemonats).
    final monthEnd = DateTime(record.periodYear, record.periodMonth + 1, 0);
    final period =
        '${record.periodMonth.toString().padLeft(2, '0')}/${record.periodYear}';
    await saveJournalEntry(JournalEntry(
      id: journalId,
      orgId: _orgId!,
      date: monthEnd,
      costCenterId: costCenter!.id!,
      costTypeId: costType!.id!,
      description: 'Personalkosten $employeeLabel $period',
      amountCents: record.employerTotalCents,
      reference: record.documentId,
    ));
    return journalId;
  }

  /// Kostenstelle für eine Auto-Buchung: bevorzugt die dem Standort zugeordnete
  /// (H-C1), sonst die einzige aktive (eindeutig), sonst null.
  CostCenter? _resolveSiteCostCenter(String? siteId) {
    final bySite = costCenterForSite(siteId);
    if (bySite != null) return bySite;
    final active = _costCenters.where((c) => c.isActive).toList();
    return active.length == 1 ? active.first : null;
  }

  /// Erste aktive Kostenart, deren Name eines der [needles] enthält. Kein
  /// Treffer → null (keine Falschbuchung mit beliebiger Kostenart).
  CostType? _resolveCostTypeByNeedles(List<String> needles) {
    for (final type in _costTypes) {
      if (!type.isActive) continue;
      final name = type.name.toLowerCase();
      if (needles.any(name.contains)) return type;
    }
    return null;
  }

  static const List<String> _personnelNeedles = [
    'personal',
    'lohn',
    'löhne',
    'gehäl',
  ];
  static const List<String> _goodsNeedles = [
    'wareneinsatz',
    'wareneingang',
    'einkauf',
    'waren',
  ];
  static const List<String> _revenueNeedles = [
    'umsatz',
    'erlös',
    'erlos',
    'verkauf',
  ];

  /// Bucht den **Wareneinsatz** einer vollständig gelieferten Bestellung
  /// (H-A2). Kosten → positiver Betrag. Idempotent über `po-<id>`.
  Future<String?> postPurchaseOrderCost(PurchaseOrder order) async {
    if (order.id == null || order.totalCents <= 0) return null;
    return _postOrderJournal(
      journalId: 'po-${order.id}',
      siteId: order.siteId,
      date: order.receivedAt ?? order.createdAt,
      amountCents: order.totalCents,
      description: 'Wareneinkauf ${order.orderNumber ?? order.id}',
      reference: order.id!,
      costType: _resolveCostTypeByNeedles(_goodsNeedles),
    );
  }

  /// Bucht den **Umsatz** einer abgeholten Kundenbestellung (H-A2). Erlös →
  /// negativer Betrag (Gutschrift-Konvention). Idempotent über `co-<id>`.
  Future<String?> postCustomerOrderRevenue(CustomerOrder order) async {
    if (order.id == null || order.totalCents <= 0) return null;
    return _postOrderJournal(
      journalId: 'co-${order.id}',
      siteId: order.siteId,
      date: order.pickupDate ?? order.createdAt,
      amountCents: -order.totalCents,
      description: 'Umsatz Kundenbestellung ${order.orderNumber ?? order.id}',
      reference: order.id!,
      costType: _resolveCostTypeByNeedles(_revenueNeedles),
    );
  }

  /// **P2.0 — Tagesabschluss buchen** (admin-explizite Aktion, KEINE Automatik).
  /// Bucht je USt-Satz eine Erlös-Zeile (netto, negativ) auf das via
  /// [revenueCostTypeIdByRate] **explizit** zugeordnete Erlöskonto (Satz →
  /// CostType-ID). Idempotent über die deterministischen `pos-`-IDs
  /// (Re-Buchung überschreibt). Sätze ohne zugeordnetes Konto werden
  /// übersprungen + geloggt. Liefert die Anzahl gebuchter Zeilen.
  ///
  /// **Richtwert** (Steuerberater prüft; Kassendaten Swagger-unverifiziert).
  Future<int> postDailyClosing(
    DailyClosing closing, {
    required Map<int, String> revenueCostTypeIdByRate,
  }) async {
    if (!isAdmin || _orgId == null) return 0;
    final costCenter = _resolveSiteCostCenter(closing.siteId);
    if (costCenter?.id == null) {
      AppLogger.warning(
        'Tagesabschluss übersprungen: keine eindeutige Kostenstelle für '
        'Standort ${closing.siteId}.',
      );
      return 0;
    }
    final entries = buildDailyClosingEntries(
      closing,
      orgId: _orgId!,
      costCenterId: costCenter!.id!,
      revenueCostTypeIdByRate: revenueCostTypeIdByRate,
      createdByUid: _currentUser?.uid,
    );
    for (final entry in entries) {
      await saveJournalEntry(entry);
    }
    return entries.length;
  }

  Future<String?> _postOrderJournal({
    required String journalId,
    required String siteId,
    required DateTime? date,
    required int amountCents,
    required String description,
    required String reference,
    required CostType? costType,
  }) async {
    if (!isAdmin || _orgId == null) return null;
    final costCenter = _resolveSiteCostCenter(siteId);
    if (costCenter?.id == null || costType?.id == null) {
      AppLogger.warning(
        'Auto-Buchung übersprungen: Kostenstelle/-art nicht eindeutig '
        '($description).',
      );
      return null;
    }
    await saveJournalEntry(JournalEntry(
      id: journalId,
      orgId: _orgId!,
      date: date ?? DateTime.now(),
      costCenterId: costCenter!.id!,
      costTypeId: costType!.id!,
      description: description,
      amountCents: amountCents,
      reference: reference,
    ));
    return journalId;
  }

  // --- Budgets -------------------------------------------------------------

  Future<void> saveBudget(Budget budget) async {
    _assertAdmin();
    final orgId = _requireOrg();
    final isNew = budget.id == null || budget.id!.isEmpty;
    final withMeta = budget.copyWith(
      orgId: orgId,
      createdByUid: budget.createdByUid ?? _currentUser?.uid,
    );
    final prepared = withMeta.id == null
        ? withMeta.copyWith(id: withMeta.documentId)
        : withMeta;
    final summary = 'Budget ${costCenterById(prepared.costCenterId)?.name ?? ''}'
        ' ${prepared.year}: ${_euro(prepared.plannedAmountCents)} €';
    await _persist<Budget>(
      label: 'saveBudget',
      cloud: () => _firestore.saveBudget(prepared),
      localList: () => _budgets,
      assignId: () => prepared,
      setList: (list) => _budgets = list,
      persist: _persistBudgets,
      audit: () => _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Budget',
        entityId: prepared.id,
        summary: summary,
      ),
      idOf: (b) => b.id,
    );
  }

  Future<void> deleteBudget(String id) async {
    _assertAdmin();
    final orgId = _orgId;
    if (orgId == null) return;
    await _persistDelete(
      label: 'deleteBudget',
      cloud: () => _firestore.deleteBudget(orgId: orgId, id: id),
      removeLocal: () => _budgets = _budgets.where((b) => b.id != id).toList(),
      persist: _persistBudgets,
      audit: () => _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Budget',
        entityId: id,
        summary: 'Budget gelöscht',
      ),
    );
  }

  // --- Persistenz-Helfer ---------------------------------------------------

  Future<void> _persistCostCenters() =>
      DatabaseService.saveLocalCostCenters(_costCenters, scope: _localScope);
  Future<void> _persistCostTypes() =>
      DatabaseService.saveLocalCostTypes(_costTypes, scope: _localScope);
  Future<void> _persistJournal() =>
      DatabaseService.saveLocalJournalEntries(_journalEntries,
          scope: _localScope);
  Future<void> _persistBudgets() =>
      DatabaseService.saveLocalBudgets(_budgets, scope: _localScope);

  // --- Speichermodus-Migration (H-H1) -------------------------------------

  /// Snapshot des aktuellen (Cloud-)Finanz-Stands in den lokalen Speicher
  /// (cloud/hybrid → local). Die DATEV-Konfiguration ist bereits lokal-skopiert.
  Future<void> cacheCloudStateLocally() async {
    if (usesLocalStorage) return;
    await _persistCostCenters();
    await _persistCostTypes();
    await _persistJournal();
    await _persistBudgets();
  }

  /// Lädt die lokalen Finanz-Daten beim Wechsel local→Cloud/Hybrid hoch. Das
  /// append-only Journal nutzt seine (deterministischen) Doc-IDs beim Upsert →
  /// **keine** Doppelbuchung bei Re-Sync.
  Future<void> syncLocalStateToCloud() async {
    if (_orgId == null) return;
    Future<void> push(String label, Future<void> Function() write) async {
      try {
        await write();
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud(finance:$label): $error');
      }
    }

    for (final c in List<CostCenter>.from(_costCenters)) {
      await push('costCenter', () => _firestore.saveCostCenter(c));
    }
    for (final t in List<CostType>.from(_costTypes)) {
      await push('costType', () => _firestore.saveCostType(t));
    }
    for (final j in List<JournalEntry>.from(_journalEntries)) {
      await push('journal', () => _firestore.saveJournalEntry(j));
    }
    for (final b in List<Budget>.from(_budgets)) {
      await push('budget', () => _firestore.saveBudget(b));
    }
  }

  /// Gemeinsamer Save-Pfad: Cloud versuchen (mit Hybrid-Fallback), sonst lokal
  /// upserten + persistieren; in beiden Fällen Audit protokollieren.
  Future<void> _persist<T>({
    required String label,
    required Future<void> Function() cloud,
    required List<T> Function() localList,
    required T Function() assignId,
    required void Function(List<T>) setList,
    required Future<void> Function() persist,
    required void Function() audit,
    required String? Function(T) idOf,
  }) async {
    if (_usesFirestore && await _tryFirestore(label, cloud)) {
      audit();
      return;
    }
    final withId = assignId();
    final list = [...localList()];
    final index = list.indexWhere((existing) => idOf(existing) == idOf(withId));
    if (index >= 0) {
      list[index] = withId;
    } else {
      list.add(withId);
    }
    setList(list);
    await persist();
    _safeNotify();
    audit();
  }

  Future<void> _persistDelete({
    required String label,
    required Future<void> Function() cloud,
    required void Function() removeLocal,
    required Future<void> Function() persist,
    required void Function() audit,
  }) async {
    if (_usesFirestore && await _tryFirestore(label, cloud)) {
      audit();
      return;
    }
    removeLocal();
    await persist();
    _safeNotify();
    audit();
  }

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
        'Finance: $label offline – lokaler Fallback aktiv',
        error: error,
      );
      return false;
    }
  }

  void _assertAdmin() {
    if (!isAdmin) {
      throw StateError('Nur Admins dürfen den Finanzbereich bearbeiten.');
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

  static String _euro(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _setError(Object error) {
    _loading = false;
    _errorMessage = error is StateError ? error.message : error.toString();
    _safeNotify();
  }

  void surfaceSessionError(Object error) {
    _errorMessage =
        'Finanzdaten konnten nicht geladen werden. Bitte später erneut versuchen.';
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
