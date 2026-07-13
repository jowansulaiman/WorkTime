import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/hybrid_write_fallback.dart';
import '../core/retry.dart';
import '../core/cash_difference_posting.dart';
import '../core/daily_closing.dart';
import '../core/daily_closing_posting.dart';
import '../core/datev_export.dart';
import '../core/datev_lohn_export.dart';
import '../models/datev_export_run.dart';
import '../core/finance_analytics.dart';
import '../core/local_demo_backoffice_data.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/cash_closing.dart';
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
class FinanceProvider extends ChangeNotifier with HybridWriteFallback {
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
  DatevLohnConfig _datevLohnConfig = const DatevLohnConfig();
  List<DatevExportRun> _localDemoDatevExportRuns = [];
  final StreamController<int> _localDemoExportRunsChanged =
      StreamController<int>.broadcast();
  int _localDemoExportRunsRevision = 0;

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
  DatevLohnConfig get datevLohnConfig => _datevLohnConfig;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get _usesFirestore => !usesLocalStorage;
  @override
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get _supportsLocalDemoExportHistory =>
      usesLocalStorage && LocalDemoData.isDemoUser(_currentUser);

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

    // DATEV-1/PERSONAL-2: Configs zuerst aus dem lokalen Spiegel (Fallback +
    // local-Modus).
    _datevConfig =
        await DatabaseService.loadLocalDatevConfig(scope: _localScope) ??
            const DatevExportConfig();
    _datevLohnConfig =
        await DatabaseService.loadLocalDatevLohnConfig(scope: _localScope) ??
            const DatevLohnConfig();

    if (_usesFirestore) {
      _replaceLocalDemoExportRuns(const []);
      // Cloud-first laden — ABER admin-gated: die financeConfig-Rules sind
      // admin-only, ein Mitarbeiter-Read gäbe garantiert permission-denied.
      if (user.isAdmin) {
        await _loadDatevConfigFromCloud(user.orgId);
        await _loadDatevLohnConfigFromCloud(user.orgId);
      }
      _startFirestoreSubscriptions(user.orgId);
    } else {
      await _loadLocalData();
      _loadLocalDemoExportRuns(user);
      _safeNotify();
    }
  }

  /// DATEV-1: Lädt das org-weite Config-Singleton `financeConfig/datev`. Fehlt
  /// es (Erstmigration), wird der bestehende lokale Stand einmalig als
  /// Initial-Doc in die Cloud gehoben (mit Audit `created`). Fehler beim Laden
  /// verschlucken wir NICHT still in den Datenbestand — sie bleiben der lokale
  /// Fallback-Stand, werden aber geloggt.
  Future<void> _loadDatevConfigFromCloud(String orgId) async {
    try {
      final cloud = await _firestore.fetchDatevConfig(orgId);
      if (cloud != null) {
        // Adoptieren — ABER einen bereits konfigurierten lokalen Stand NICHT
        // durch ein (leeres) Default-Cloud-Singleton still überschreiben
        // (Review-Befund: sonst geht die gerätelokal gepflegte Berater-/
        // Mandantennummer bei Mehr-Geräte-Login verloren). Ist die Cloud
        // unkonfiguriert, aber lokal konfiguriert, schieben wir den lokalen
        // Stand nach oben statt ihn zu verlieren.
        if (!cloud.isConfigured && _datevConfig.isConfigured) {
          await _firestore.saveDatevConfig(orgId: orgId, config: _datevConfig);
          _audit?.call(
            action: AuditAction.updated,
            entityType: 'datevConfig',
            entityId: DatevExportConfig.firestoreDocId,
            summary: 'DATEV-Export-Konfiguration aus lokalem Stand ergänzt',
          );
          return;
        }
        _datevConfig = cloud;
        await DatabaseService.saveLocalDatevConfig(cloud, scope: _localScope);
        _safeNotify();
        return;
      }
      // Kein Cloud-Doc: Einmal-Migration NUR eines wirklich konfigurierten
      // lokalen Stands (ein unkonfiguriertes Gerät legt kein leeres Singleton
      // an, das später konfigurierte Geräte adoptieren würden).
      if (!_datevConfig.isConfigured) return;
      await _firestore.saveDatevConfig(orgId: orgId, config: _datevConfig);
      _audit?.call(
        action: AuditAction.created,
        entityType: 'datevConfig',
        entityId: DatevExportConfig.firestoreDocId,
        summary: 'DATEV-Export-Konfiguration angelegt',
      );
    } catch (error) {
      AppLogger.warning(
        'FinanceProvider: DATEV-Config Cloud-Load fehlgeschlagen – '
        'lokaler Stand bleibt aktiv',
        error: error,
      );
    }
  }

  /// PERSONAL-2/3: Lädt `financeConfig/datevLohn` cloud-first (Spiegel-Logik +
  /// isConfigured-Guard exakt wie [_loadDatevConfigFromCloud]).
  Future<void> _loadDatevLohnConfigFromCloud(String orgId) async {
    try {
      final cloud = await _firestore.fetchDatevLohnConfig(orgId);
      if (cloud != null) {
        if (!cloud.isConfigured && _datevLohnConfig.isConfigured) {
          await _firestore.saveDatevLohnConfig(
              orgId: orgId, config: _datevLohnConfig);
          _audit?.call(
            action: AuditAction.updated,
            entityType: 'datevLohnConfig',
            entityId: DatevLohnConfig.firestoreDocId,
            summary: 'DATEV-Lohn-Konfiguration aus lokalem Stand ergänzt',
          );
          return;
        }
        _datevLohnConfig = cloud;
        await DatabaseService.saveLocalDatevLohnConfig(cloud, scope: _localScope);
        _safeNotify();
        return;
      }
      if (!_datevLohnConfig.isConfigured) return;
      await _firestore.saveDatevLohnConfig(
          orgId: orgId, config: _datevLohnConfig);
      _audit?.call(
        action: AuditAction.created,
        entityType: 'datevLohnConfig',
        entityId: DatevLohnConfig.firestoreDocId,
        summary: 'DATEV-Lohn-Konfiguration angelegt',
      );
    } catch (error) {
      AppLogger.warning(
        'FinanceProvider: DATEV-Lohn-Config Cloud-Load fehlgeschlagen – '
        'lokaler Stand bleibt aktiv',
        error: error,
      );
    }
  }

  /// Speichert die DATEV-Export-Konfiguration (admin-only). Drei-Modi-Muster:
  /// im local-Modus nur lokal; sonst Cloud-Singleton schreiben und lokal
  /// spiegeln (hybrid-Cache). Audit `updated` auf jedem Erfolgs-Zweig.
  Future<void> saveDatevConfig(DatevExportConfig config) async {
    _assertAdmin();
    void logUpdate() => _audit?.call(
          action: AuditAction.updated,
          entityType: 'datevConfig',
          entityId: DatevExportConfig.firestoreDocId,
          summary: 'DATEV-Export-Konfiguration geändert',
        );

    if (usesLocalStorage) {
      _datevConfig = config;
      await DatabaseService.saveLocalDatevConfig(config, scope: _localScope);
      logUpdate();
      _safeNotify();
      return;
    }

    final orgId = _requireOrg();
    try {
      await _firestore.saveDatevConfig(orgId: orgId, config: config);
    } catch (error) {
      // Q1-Positivliste (via isTransientError): nur echte Offline-Fehler
      // (unavailable/deadline-exceeded/Timeout) fallbacken lokal; Rules-Deny
      // (permission-denied) & Co. scheitern sichtbar (rethrow, kein Audit).
      if (_hybridStorageEnabled && isTransientError(error)) {
        _datevConfig = config;
        await DatabaseService.saveLocalDatevConfig(config, scope: _localScope);
        logUpdate();
        _safeNotify();
        return;
      }
      rethrow;
    }
    _datevConfig = config;
    await DatabaseService.saveLocalDatevConfig(config, scope: _localScope);
    logUpdate();
    _safeNotify();
  }

  /// Speichert die DATEV-Lohn-Konfiguration (admin-only). Drei-Modi-Muster +
  /// Audit `updated`, exakt wie [saveDatevConfig].
  Future<void> saveDatevLohnConfig(DatevLohnConfig config) async {
    _assertAdmin();
    void logUpdate() => _audit?.call(
          action: AuditAction.updated,
          entityType: 'datevLohnConfig',
          entityId: DatevLohnConfig.firestoreDocId,
          summary: 'DATEV-Lohn-Konfiguration geändert',
        );

    if (usesLocalStorage) {
      _datevLohnConfig = config;
      await DatabaseService.saveLocalDatevLohnConfig(config, scope: _localScope);
      logUpdate();
      _safeNotify();
      return;
    }

    final orgId = _requireOrg();
    try {
      await _firestore.saveDatevLohnConfig(orgId: orgId, config: config);
    } catch (error) {
      if (_hybridStorageEnabled && isTransientError(error)) {
        _datevLohnConfig = config;
        await DatabaseService.saveLocalDatevLohnConfig(config,
            scope: _localScope);
        logUpdate();
        _safeNotify();
        return;
      }
      rethrow;
    }
    _datevLohnConfig = config;
    await DatabaseService.saveLocalDatevLohnConfig(config, scope: _localScope);
    logUpdate();
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

  void _loadLocalDemoExportRuns(AppUserProfile user) {
    if (!LocalDemoData.isDemoUser(user)) {
      _replaceLocalDemoExportRuns(const []);
      return;
    }
    _replaceLocalDemoExportRuns(
      LocalDemoBackofficeData.datevExportRunsForOrg(orgId: user.orgId),
    );
  }

  void _replaceLocalDemoExportRuns(List<DatevExportRun> runs) {
    _localDemoDatevExportRuns = List<DatevExportRun>.unmodifiable(runs);
    if (!_localDemoExportRunsChanged.isClosed) {
      _localDemoExportRunsChanged.add(++_localDemoExportRunsRevision);
    }
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
    _datevLohnConfig = const DatevLohnConfig();
    _replaceLocalDemoExportRuns(const []);
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

  /// H11: `true`, wenn die Buchung im autoritativen Speicher liegt (Cloud
  /// bzw. reiner local-Modus); `false` beim hybriden Offline-Fallback.
  Future<bool> saveJournalEntry(JournalEntry entry) async {
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
    return _persist<JournalEntry>(
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
  // Bewusst SPEZIFISCH: das breite 'differenz'/'manko' würde 'Inventur-/Preis-/
  // Bestandsdifferenz' fälschlich treffen (Falschbuchung statt sauberem Skip).
  static const List<String> _cashDiffNeedles = [
    'kassendifferenz',
    'kassenmanko',
  ];

  /// Bucht den **Wareneinsatz** einer vollständig gelieferten Bestellung
  /// (H-A2). Kosten → positiver Betrag. Idempotent über `po-<id>`.
  Future<String?> postPurchaseOrderCost(PurchaseOrder order) async {
    final effectiveTotalCents = order.closedAt != null
        ? order.deliveredTotalCents
        : order.totalCents;
    if (order.id == null || effectiveTotalCents <= 0) return null;
    return _postOrderJournal(
      journalId: 'po-${order.id}',
      siteId: order.siteId,
      date: order.closedAt ?? order.receivedAt ?? order.createdAt,
      amountCents: effectiveTotalCents,
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
  /// H11: `cloudComplete` ist nur `true`, wenn ALLE Journalzeilen im
  /// autoritativen Speicher gelandet sind — landete auch nur eine Zeile im
  /// hybriden Offline-Fallback, darf der Kassenabschluss NICHT cloud-seitig
  /// als `bookedToFinance` markiert werden (sonst gilt er als gebucht,
  /// obwohl das Journal nur lokal auf diesem Geraet existiert).
  Future<({int entries, bool cloudComplete, List<int> skippedRates})>
      postDailyClosing(
    DailyClosing closing, {
    required Map<int, String> revenueCostTypeIdByRate,
  }) async {
    if (!isAdmin || _orgId == null) {
      return (entries: 0, cloudComplete: false, skippedRates: const <int>[]);
    }
    final costCenter = _resolveSiteCostCenter(closing.siteId);
    if (costCenter?.id == null) {
      AppLogger.warning(
        'Tagesabschluss übersprungen: keine eindeutige Kostenstelle für '
        'Standort ${closing.siteId}.',
      );
      return (entries: 0, cloudComplete: false, skippedRates: const <int>[]);
    }
    final built = buildDailyClosingEntries(
      closing,
      orgId: _orgId!,
      costCenterId: costCenter!.id!,
      revenueCostTypeIdByRate: revenueCostTypeIdByRate,
      createdByUid: _currentUser?.uid,
    );
    if (built.skippedRates.isNotEmpty) {
      AppLogger.warning(
        'Tagesabschluss: USt-Sätze ohne Erlöskonto übersprungen: '
        '${built.skippedRates.join(', ')} %.',
      );
    }
    var cloudComplete = true;
    for (final entry in built.entries) {
      final persisted = await saveJournalEntry(entry);
      cloudComplete = cloudComplete && persisted;
    }
    return (
      entries: built.entries.length,
      cloudComplete: cloudComplete,
      skippedRates: built.skippedRates,
    );
  }

  /// **Kassen-Modul M6 — Kassendifferenz buchen** (Plan §8a). Bucht die
  /// festgeschriebene Differenz (gezählt − Soll) auf eine Kostenart
  /// „Kassendifferenz" (Namens-Heuristik [_cashDiffNeedles]). Fehlbetrag →
  /// Kosten, Überschuss → Gutschrift. Idempotent über `pos-diff-<day>-<site>`.
  /// `true`, wenn gebucht; `false`, wenn keine Differenz oder kein Konto/
  /// keine Kostenstelle zugeordnet (dann still übersprungen, keine Falschbuchung).
  Future<bool> postCashDifference(CashClosing closing) async {
    if (!isAdmin || _orgId == null) return false;
    if (closing.cashDifferenceCents == null ||
        closing.cashDifferenceCents == 0) {
      return false;
    }
    final costCenter = _resolveSiteCostCenter(closing.siteId);
    final costType = _resolveCostTypeByNeedles(_cashDiffNeedles);
    if (costCenter?.id == null || costType?.id == null) {
      AppLogger.warning(
        'Kassendifferenz übersprungen: keine eindeutige Kostenstelle/-art '
        '(„Kassendifferenz") für Standort ${closing.siteId}.',
      );
      return false;
    }
    final entry = buildCashDifferenceEntry(
      closing,
      orgId: _orgId!,
      costCenterId: costCenter!.id!,
      costTypeId: costType!.id!,
      createdByUid: _currentUser?.uid,
    );
    if (entry == null) return false;
    await saveJournalEntry(entry);
    return true;
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
  /// Liefert `true`, wenn der Write im fuer den Modus AUTORITATIVEN Speicher
  /// gelandet ist (Cloud-Write ok ODER reiner local-Modus). `false` nur beim
  /// hybriden Offline-Fallback (Cloud beabsichtigt, aber nur lokal gespiegelt)
  /// — H11: Aufrufer wie der Tagesabschluss duerfen dann NICHT cloud-seitig
  /// "gebucht" markieren.
  Future<bool> _persist<T>({
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
      return true;
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
    return !_usesFirestore;
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

  // Q1: delegiert an die zentrale Offline-Positivliste (HybridWriteFallback) —
  // fällt NUR bei echten Offline-Fehlern lokal zurück, rethrowt permission-denied
  // & Co. sichtbar.
  @override
  String get hybridFallbackLabel => 'Finance';

  Future<bool> _tryFirestore(
    String label,
    Future<void> Function() action,
  ) =>
      tryFirestoreWrite(label, action);

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

  // ── DATEV-Export-Historie (Q2/DATEV-3) ───────────────────────────────────
  /// Cloud-Historie oder flüchtige Historie im lokalen Demo-Modus verfügbar?
  /// Normale lokale Nutzer bleiben bei der bisherigen Degradation ohne
  /// Historie; Demo-Runs werden nie persistiert.
  bool get supportsExportHistory =>
      _usesFirestore || _supportsLocalDemoExportHistory;

  /// Streamt die Export-Historie einer Art (neueste zuerst). Im normalen
  /// local-Modus ein leerer Stream; nur die lokale Demo hat In-Memory-Runs.
  Stream<List<DatevExportRun>> watchDatevExportRuns(DatevExportArt art) {
    final orgId = _orgId;
    if (_supportsLocalDemoExportHistory) {
      return _watchLocalDemoExportRuns(art);
    }
    if (!_usesFirestore || orgId == null) {
      return Stream<List<DatevExportRun>>.value(const []);
    }
    return _firestore.watchDatevExportRuns(orgId, art);
  }

  Stream<List<DatevExportRun>> _watchLocalDemoExportRuns(
    DatevExportArt art,
  ) async* {
    yield _localDemoExportRunsFor(art);
    yield* _localDemoExportRunsChanged.stream.map(
      (_) => _localDemoExportRunsFor(art),
    );
  }

  List<DatevExportRun> _localDemoExportRunsFor(DatevExportArt art) {
    final runs = _localDemoDatevExportRuns
        .where((run) => run.exportArt == art)
        .toList(growable: false);
    runs.sort((a, b) {
      final byCreatedAt = (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0));
      if (byCreatedAt != 0) return byCreatedAt;
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    return List<DatevExportRun>.unmodifiable(runs);
  }

  /// **DATEV-3/Q2:** Schreibt einen Export-Lauf in die gemeinsame Historie
  /// (admin-only; Cloud immutabel, lokale Demo rein in-memory).
  /// `orgId`/`createdByUid` werden hier gefüllt. **Kein Hybrid-Fallback** — die
  /// Cloud-Historie ist append-only und darf nicht lokal divergieren: bei
  /// Offline (`unavailable`) wirft die Methode und der Aufrufer blockiert den
  /// Export (Q2-Offline-Semantik). Reihenfolge im Aufrufer: **Run schreiben,
  /// DANN Download.** Gibt die Run-ID zurück.
  Future<String> logDatevExportRun(DatevExportRun run) async {
    _assertAdmin();
    final orgId = _requireOrg();
    if (_supportsLocalDemoExportHistory) {
      final id = _nextLocalId('datev-run');
      final localRun = DatevExportRun(
        id: id,
        orgId: orgId,
        schemaVersion: run.schemaVersion,
        exportArt: run.exportArt,
        kind: run.kind,
        periodYear: run.periodYear,
        periodMonth: run.periodMonth,
        createdByUid: _currentUser?.uid ?? run.createdByUid,
        createdAt: DateTime.now(),
        entryCount: run.entryCount,
        sollCents: run.sollCents,
        habenCents: run.habenCents,
        summeCents: run.summeCents,
        fileName: run.fileName,
        fileSha256: run.fileSha256,
        generatedAtMillis: run.generatedAtMillis,
        configSnapshot: run.configSnapshot,
        rowsSnapshot: run.rowsSnapshot,
        entriesSnapshot: run.entriesSnapshot,
        snapshotTruncated: run.snapshotTruncated,
        snapshotRowCount: run.snapshotRowCount,
        subjectUserIds: run.subjectUserIds,
        acceptedWarningCodes: run.acceptedWarningCodes,
        problemeAnzahl: run.problemeAnzahl,
        monatFestgeschrieben: run.monatFestgeschrieben,
        overrideBestaetigt: run.overrideBestaetigt,
        note: run.note,
      );
      _replaceLocalDemoExportRuns([
        localRun,
        ..._localDemoDatevExportRuns,
      ]);
      // Demo-Historie bleibt vollständig flüchtig: weder Datenbank-Write noch
      // Audit-Persistenz für diesen synthetischen Lauf.
      _safeNotify();
      return id;
    }
    final prepared = DatevExportRun(
      orgId: orgId,
      schemaVersion: run.schemaVersion,
      exportArt: run.exportArt,
      kind: run.kind,
      periodYear: run.periodYear,
      periodMonth: run.periodMonth,
      createdByUid: _currentUser?.uid ?? run.createdByUid,
      entryCount: run.entryCount,
      sollCents: run.sollCents,
      habenCents: run.habenCents,
      summeCents: run.summeCents,
      fileName: run.fileName,
      fileSha256: run.fileSha256,
      generatedAtMillis: run.generatedAtMillis,
      configSnapshot: run.configSnapshot,
      rowsSnapshot: run.rowsSnapshot,
      entriesSnapshot: run.entriesSnapshot,
      snapshotTruncated: run.snapshotTruncated,
      snapshotRowCount: run.snapshotRowCount,
      subjectUserIds: run.subjectUserIds,
      acceptedWarningCodes: run.acceptedWarningCodes,
      problemeAnzahl: run.problemeAnzahl,
      monatFestgeschrieben: run.monatFestgeschrieben,
      overrideBestaetigt: run.overrideBestaetigt,
      note: run.note,
    );
    final id = await _firestore.createDatevExportRun(prepared);
    _audit?.call(
      action: AuditAction.created,
      entityType: 'datevExportRun',
      entityId: id,
      summary: '${run.exportArt.label} erstellt (${run.periodYear}, '
          '${run.entryCount} Zeilen)',
    );
    return id;
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
    _localDemoExportRunsChanged.close();
    super.dispose();
  }
}
