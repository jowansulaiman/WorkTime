import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/retry.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/clock_entry.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift_preference.dart';
import '../models/product.dart';
import '../models/customer_order.dart';
import '../models/customer_feedback.dart';
import '../models/customer_wish.dart';
import '../models/audit_log_entry.dart';
import '../models/employee_ausbildung.dart';
import '../models/employee_child.dart';
import '../models/employee_note.dart';
import '../models/employee_document.dart';
import '../models/employee_profile.dart';
import '../models/employee_qualification.dart';
import '../models/org_payroll_settings.dart';
import '../models/org_settings.dart';
import '../models/pay_line_type.dart';
import '../models/sollzeit_profile.dart';
import '../models/urlaubsanpassung.dart';
import '../models/urlaubskonto_jahr.dart';
import '../models/zeitkonto_snapshot.dart';
import '../models/finance_models.dart';
import '../models/payroll_profile.dart';
import '../models/password_entry.dart';
import '../models/payroll_record.dart';
import '../models/purchase_order.dart';
import '../models/qualification_definition.dart';
import '../models/shift.dart';
import '../models/shift_swap_request.dart';
import '../models/swap_credit.dart';
import '../models/shift_template.dart';
import '../models/site_definition.dart';
import '../models/stock_movement.dart';
import '../models/supplier.dart';
import '../models/team_definition.dart';
import '../models/third_party_cash.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../models/store_task.dart';
import '../models/user_settings.dart';
import '../models/work_entry.dart';
import '../models/work_task.dart';
import '../models/work_template.dart';
import '../repositories/contact_repository.dart';
import '../repositories/firestore_contact_repository.dart';
import '../repositories/firestore_inventory_repository.dart';
import '../repositories/firestore_signage_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/signage_repository.dart';
import 'compliance_rejected_exception.dart';
import 'database_service.dart';

typedef CloudFunctionInvoker = Future<dynamic> Function(
  String name,
  Map<String, dynamic> payload,
);

class FirestoreService {
  FirestoreService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    CloudFunctionInvoker? cloudFunctionInvoker,
    Uuid? uuid,
    Duration retryBaseDelay = const Duration(milliseconds: 200),
  })  : _providedFirestore = firestore,
        _functions = functions,
        _cloudFunctionInvoker = cloudFunctionInvoker,
        _uuid = uuid ?? const Uuid(),
        _retryBaseDelay = retryBaseDelay;

  final FirebaseFirestore? _providedFirestore;
  final Uuid _uuid;
  // Basiswartezeit fuer Retry-Backoff transienter, idempotenter Cloud-Writes.
  // Tests setzen Duration.zero fuer sofortige Wiederholungen.
  final Duration _retryBaseDelay;
  FirebaseFunctions? _functions;
  final CloudFunctionInvoker? _cloudFunctionInvoker;
  FirebaseFirestore? _firestoreInstance;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? (_firestoreInstance ??= FirebaseFirestore.instance);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('userInvites');

  DocumentReference<Map<String, dynamic>> _organizationDoc(String orgId) =>
      _firestore.collection('organizations').doc(orgId);

  /// Liest das org-skopierte Remote-Config-Doc (Feature-Flags + Mindest-Build,
  /// no-feature-flags-force-update). Gibt null zurueck, wenn das Doc fehlt
  /// (-> keine Einschraenkungen, fail-open).
  Future<Map<String, dynamic>?> fetchAppConfig(String orgId) async {
    final snapshot =
        await _organizationDoc(orgId).collection('config').doc('appFlags').get();
    return snapshot.data();
  }

  /// Liest die org-weiten operativen Einstellungen aus dem deterministischen
  /// Doc `config/orgSettings`. Gibt null zurueck, wenn es (noch) nicht
  /// existiert -> Aufrufer nutzt [OrgSettings.defaults].
  Future<OrgSettings?> fetchOrgSettings(String orgId) async {
    final snapshot = await _organizationDoc(orgId)
        .collection('config')
        .doc(OrgSettings.documentId)
        .get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return OrgSettings.fromFirestore(snapshot.id, data);
  }

  /// Speichert die org-weiten operativen Einstellungen unter der festen Doc-ID
  /// `orgSettings` (genau ein Datensatz je Org), merge-sicher.
  Future<void> saveOrgSettings(OrgSettings settings) async {
    await _organizationDoc(settings.orgId)
        .collection('config')
        .doc(OrgSettings.documentId)
        .set(settings.toFirestoreMap(), SetOptions(merge: true));
  }

  /// Liest das OktoPOS-Sync-Config-Doc `config/oktoposSync` (baseUrl,
  /// `enabled`, `sites[siteId].cashRegisterId` + serverseitiger Cursor).
  /// Null, wenn die Kasse noch nicht eingerichtet ist. Enthält **keinen**
  /// API-Key (der liegt im Secret Manager).
  Future<Map<String, dynamic>?> fetchOktoposConfig(String orgId) async {
    final snapshot = await _organizationDoc(orgId)
        .collection('config')
        .doc('oktoposSync')
        .get();
    return snapshot.data();
  }

  /// Schreibt die vom Admin gepflegten OktoPOS-Felder (baseUrl, enabled,
  /// defaultSize, cashRegisterId je Standort) **merge-sicher**: der
  /// serverseitig gepflegte Cursor (`sites[siteId].lastBusinessDay`/
  /// `lastSyncAt`) bleibt dank Nested-Merge erhalten. Der API-Key wird hier
  /// NICHT gespeichert (Secret Manager).
  Future<void> saveOktoposConfig({
    required String orgId,
    required String baseUrl,
    required bool enabled,
    required int defaultSize,
    required Map<String, int?> cashRegisterBySiteId,
    String? distributionChannel,
    String? defaultUnitToken,
    int? defaultTaxRate,
    bool? cashierCanChangePrice,
    String? customerGroupName,
  }) async {
    final sites = <String, dynamic>{
      for (final entry in cashRegisterBySiteId.entries)
        entry.key: {'cashRegisterId': entry.value},
    };
    // Push-Einstellungen (Artikel-Schreiben, M5) unter `push` — nur die
    // übergebenen Felder, merge-sicher (überschreibt Cursor/andere Felder nicht).
    final push = <String, dynamic>{
      if (distributionChannel != null)
        'distributionChannel': distributionChannel.trim(),
      if (defaultUnitToken != null) 'defaultUnitToken': defaultUnitToken.trim(),
      if (defaultTaxRate != null) 'defaultTaxRate': defaultTaxRate,
      if (cashierCanChangePrice != null)
        'cashierCanChangePrice': cashierCanChangePrice,
    };
    await _organizationDoc(orgId)
        .collection('config')
        .doc('oktoposSync')
        .set({
      'baseUrl': baseUrl.trim(),
      'enabled': enabled,
      'defaultSize': defaultSize,
      if (sites.isNotEmpty) 'sites': sites,
      if (push.isNotEmpty) 'push': push,
      if (customerGroupName != null && customerGroupName.trim().isNotEmpty)
        'customerGroupName': customerGroupName.trim(),
    }, SetOptions(merge: true));
  }

  CollectionReference<Map<String, dynamic>> _entryCollection(String orgId) =>
      _organizationDoc(orgId).collection('workEntries');

  // ── Zeitwirtschaft: Stempel-Sessions (ClockEntry, M3) ──────────────────────
  CollectionReference<Map<String, dynamic>> _clockEntryCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('clockEntries');

  Future<void> saveClockEntry(ClockEntry entry) async {
    final collection = _clockEntryCollection(entry.orgId);
    final docRef =
        entry.id == null ? collection.doc() : collection.doc(entry.id);
    await docRef.set(
      entry.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  /// Deterministische Doc-ID der **offenen** Stempel-Buchung eines Mitarbeiters
  /// (PA-4.1, `{userId}-open`): genau EIN mögliches offenes Doc je Nutzer —
  /// der harte Doppel-Stempel-Guard. Spiegel: `functions/index.js`
  /// (`kioskClockPunch`) + `firestore.rules` (kommen-Pin/self-delete).
  static String openClockDocId(String userId) => '$userId-open';

  /// Einstempeln unter der deterministischen `{userId}-open`-ID — als
  /// **Transaktion mit Existenz-Check** (create-only-Semantik): läuft bereits
  /// eine offene Buchung (dieses Doc ODER — Übergangsphase — eine Alt-Buchung
  /// mit zufälliger ID, die der Aufrufer via Stream kennt), wirft der zweite
  /// clockIn statt still zu überschreiben.
  Future<void> clockInOpen(ClockEntry entry) async {
    final docRef =
        _clockEntryCollection(entry.orgId).doc(openClockDocId(entry.userId));
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(docRef);
      if (existing.exists) {
        throw StateError(
            'Bereits eingestempelt — die laufende Buchung wurde auf einem '
            'anderen Gerät gestartet.');
      }
      tx.set(docRef, entry.copyWith(id: docRef.id).toFirestoreMap());
    });
  }

  /// Ausstempeln des `{userId}-open`-Docs (PA-4.1): kopiert die geschlossene
  /// Buchung transaktional unter ihre endgültige ID und löscht das open-Doc —
  /// die ID `{userId}-open` ist damit wieder frei für den nächsten clockIn.
  /// [closed] MUSS eine neue, endgültige `id` tragen (nicht die open-ID).
  Future<void> closeOpenClockEntry({
    required String orgId,
    required String userId,
    required ClockEntry closed,
  }) async {
    assert(closed.id != null && closed.id != openClockDocId(userId));
    final openRef = _clockEntryCollection(orgId).doc(openClockDocId(userId));
    final closedRef = _clockEntryCollection(orgId).doc(closed.id);
    await _firestore.runTransaction((tx) async {
      final open = await tx.get(openRef);
      if (!open.exists) {
        throw StateError('Keine laufende Buchung gefunden.');
      }
      tx.set(closedRef, closed.toFirestoreMap());
      tx.delete(openRef);
    });
  }

  Future<void> deleteClockEntry({
    required String orgId,
    required String clockEntryId,
  }) {
    return _clockEntryCollection(orgId).doc(clockEntryId).delete();
  }

  /// Die offene Buchung (`status == ongoing`) eines Nutzers (höchstens eine).
  /// Zwei Gleichheits-Filter → kein Composite-Index nötig.
  Stream<ClockEntry?> watchOpenClockEntry({
    required String orgId,
    required String userId,
  }) {
    return _clockEntryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'ongoing')
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isEmpty
            ? null
            : ClockEntry.fromFirestore(
                snapshot.docs.first.id, snapshot.docs.first.data()));
  }

  /// Wie [watchOpenClockEntry], aber inkl. Snapshot-Metadaten (`hasPendingWrites`
  /// / `isFromCache`) für die „ausstehend"-/„zuletzt aktualisiert"-Transparenz
  /// (ZV-1.2). Nutzt `includeMetadataChanges`, damit ein bestätigter Server-
  /// Schreibvorgang das Badge auch ohne Datenänderung wieder entfernt.
  Stream<({ClockEntry? entry, bool pending, bool fromCache})>
      watchOpenClockEntryMeta({
    required String orgId,
    required String userId,
  }) {
    return _clockEntryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'ongoing')
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final doc = snapshot.docs.isEmpty ? null : snapshot.docs.first;
      return (
        entry: doc == null ? null : ClockEntry.fromFirestore(doc.id, doc.data()),
        pending: snapshot.metadata.hasPendingWrites,
        fromCache: snapshot.metadata.isFromCache,
      );
    });
  }

  /// Alle aktuell laufenden Buchungen der Org („wer ist eingestempelt").
  /// Ein Gleichheits-Filter → kein Composite-Index nötig. Admin-/Manager-Read.
  Stream<List<ClockEntry>> watchOngoingClockEntries({required String orgId}) {
    return _clockEntryCollection(orgId)
        .where('status', isEqualTo: 'ongoing')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ClockEntry.fromFirestore(doc.id, doc.data()))
            .toList(growable: false));
  }

  /// Alle offenen Klärungsfälle der Org (`status == klaerung`) — Manager-Inbox
  /// (ZV-3.1). Ein Gleichheits-Filter → kein Composite-Index; die Sortierung
  /// (nach `kommen`) macht der Aufrufer client-seitig.
  Stream<List<ClockEntry>> watchKlaerungClockEntries({required String orgId}) {
    return _clockEntryCollection(orgId)
        .where('status', isEqualTo: 'klaerung')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ClockEntry.fromFirestore(doc.id, doc.data()))
            .toList(growable: false));
  }

  /// **Org-weite** Stempel-Buchungen eines Tages (ZV-2.2b „Dienst heute").
  /// Nur ein Bereichsfilter auf `kommen` → kein Composite-Index nötig.
  /// Manager-/Admin-Read (Rules: `canManageShifts`).
  Future<List<ClockEntry>> getOrgClockEntriesForDay({
    required String orgId,
    required DateTime day,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final snapshot = await _clockEntryCollection(orgId)
        .where('kommen', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('kommen', isLessThan: Timestamp.fromDate(end))
        .get();
    return snapshot.docs
        .map((doc) => ClockEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  /// Stempel-Buchungen eines Nutzers im Zeitraum (Composite-Index
  /// `clockEntries(userId ASC, kommen DESC)` — siehe firestore.indexes.json).
  Future<List<ClockEntry>> getClockEntriesInRange({
    required String orgId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final snapshot = await _clockEntryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('kommen', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('kommen', isLessThan: Timestamp.fromDate(end))
        .orderBy('kommen', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => ClockEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  // ── Zeitwirtschaft: Stundenkonto-Snapshots (ZeitkontoSnapshot, M4) ──────────
  CollectionReference<Map<String, dynamic>> _snapshotCollection(String orgId) =>
      _organizationDoc(orgId).collection('zeitkontoSnapshots');

  /// Upsert über die deterministische Doc-ID `{userId}-{jahr}-{mm}`.
  Future<void> saveZeitkontoSnapshot(ZeitkontoSnapshot snapshot) async {
    final id =
        ZeitkontoSnapshot.buildId(snapshot.userId, snapshot.jahr, snapshot.monat);
    await _snapshotCollection(snapshot.orgId).doc(id).set(
          snapshot.copyWith(id: id).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  /// Einzelner Monats-Snapshot (deterministische Doc-ID `{userId}-{jahr}-{mm}`)
  /// — Grundlage des Festschreibungs-Guards (PA-5): `null` = kein Snapshot =
  /// Monat nicht festgeschrieben.
  Future<ZeitkontoSnapshot?> getZeitkontoSnapshot({
    required String orgId,
    required String userId,
    required int jahr,
    required int monat,
  }) async {
    final doc = await _snapshotCollection(orgId)
        .doc(ZeitkontoSnapshot.buildId(userId, jahr, monat))
        .get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return ZeitkontoSnapshot.fromFirestore(doc.id, data);
  }

  /// Monats-Snapshots eines Nutzers für ein Jahr (zwei Gleichheits-Filter →
  /// kein Composite-Index nötig).
  Future<List<ZeitkontoSnapshot>> getZeitkontoSnapshotsForYear({
    required String orgId,
    required String userId,
    required int jahr,
  }) async {
    final snapshot = await _snapshotCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('jahr', isEqualTo: jahr)
        .get();
    return snapshot.docs
        .map((doc) => ZeitkontoSnapshot.fromFirestore(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => a.monat.compareTo(b.monat));
  }

  /// **Org-weite** Monats-Snapshots (alle Mitarbeiter) für den
  /// Mitarbeiterabschluss-Hub (M5). Zwei Gleichheits-Filter (`jahr`/`monat`) →
  /// kein Composite-Index nötig. Manager-Lesezugriff regeln die `firestore.rules`
  /// (`canManageShifts`).
  Future<List<ZeitkontoSnapshot>> getOrgZeitkontoSnapshotsForMonth({
    required String orgId,
    required int jahr,
    required int monat,
  }) async {
    final snapshot = await _snapshotCollection(orgId)
        .where('jahr', isEqualTo: jahr)
        .where('monat', isEqualTo: monat)
        .get();
    return snapshot.docs
        .map((doc) => ZeitkontoSnapshot.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  CollectionReference<Map<String, dynamic>> _templateCollection(String orgId) =>
      _organizationDoc(orgId).collection('workTemplates');

  CollectionReference<Map<String, dynamic>> _shiftCollection(String orgId) =>
      _organizationDoc(orgId).collection('shifts');

  CollectionReference<Map<String, dynamic>> _shiftTemplateCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('shiftTemplates');

  CollectionReference<Map<String, dynamic>> _absenceCollection(String orgId) =>
      _organizationDoc(orgId).collection('absenceRequests');

  CollectionReference<Map<String, dynamic>> _swapRequestCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('shiftSwapRequests');

  CollectionReference<Map<String, dynamic>> _swapCreditCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('swapCredits');

  CollectionReference<Map<String, dynamic>> _teamCollection(String orgId) =>
      _organizationDoc(orgId).collection('teams');

  CollectionReference<Map<String, dynamic>> _siteCollection(String orgId) =>
      _organizationDoc(orgId).collection('sites');

  CollectionReference<Map<String, dynamic>> _qualificationCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('qualifications');

  CollectionReference<Map<String, dynamic>> _employmentContractCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employmentContracts');

  CollectionReference<Map<String, dynamic>> _siteAssignmentCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeSiteAssignments');

  CollectionReference<Map<String, dynamic>> _shiftPreferenceCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('shiftPreferences');

  CollectionReference<Map<String, dynamic>> _ruleSetCollection(String orgId) =>
      _organizationDoc(orgId).collection('ruleSets');

  CollectionReference<Map<String, dynamic>> _travelTimeRuleCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('travelTimeRules');

  CollectionReference<Map<String, dynamic>> _workTaskCollection(String orgId) =>
      _organizationDoc(orgId).collection('workTasks');

  CollectionReference<Map<String, dynamic>> _payrollRecordCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('payrollRecords');

  CollectionReference<Map<String, dynamic>> _payrollProfileCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('payrollProfiles');

  CollectionReference<Map<String, dynamic>> _employeeProfileCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeProfiles');

  CollectionReference<Map<String, dynamic>> _employeeDocumentCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeDocuments');

  CollectionReference<Map<String, dynamic>> _sollzeitProfileCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('sollzeitProfiles');

  CollectionReference<Map<String, dynamic>> _payrollConfigCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('payrollConfig');

  CollectionReference<Map<String, dynamic>> _employeeChildCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeChildren');

  CollectionReference<Map<String, dynamic>> _employeeNoteCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeNotes');

  CollectionReference<Map<String, dynamic>> _employeeQualificationCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeQualifications');

  CollectionReference<Map<String, dynamic>> _employeeAusbildungCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('employeeAusbildungen');

  CollectionReference<Map<String, dynamic>> _urlaubskontoJahrCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('urlaubskontoJahre');

  CollectionReference<Map<String, dynamic>> _urlaubsanpassungCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('urlaubsanpassungen');

  CollectionReference<Map<String, dynamic>> _payLineTypeCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('payLineTypes');

  CollectionReference<Map<String, dynamic>> _costCenterCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('costCenters');

  CollectionReference<Map<String, dynamic>> _costTypeCollection(String orgId) =>
      _organizationDoc(orgId).collection('costTypes');

  CollectionReference<Map<String, dynamic>> _journalEntryCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('journalEntries');

  CollectionReference<Map<String, dynamic>> _budgetCollection(String orgId) =>
      _organizationDoc(orgId).collection('budgets');

  // Warenwirtschafts-Datenzugriff ist in eine eigene Repository-Klasse
  // ausgelagert (firestore-service-god-object); FirestoreService delegiert nur
  // noch. Ueber den Getter koennen Provider direkt an der Abstraktion haengen
  // (no-domain-repository-interfaces-dip).
  late final InventoryRepository _inventoryRepository =
      FirestoreInventoryRepository(firestore: _firestore);

  InventoryRepository get inventoryRepository => _inventoryRepository;

  late final ContactRepository _contactRepository =
      FirestoreContactRepository(firestore: _firestore);

  ContactRepository get contactRepository => _contactRepository;

  late final SignageRepository _signageRepository =
      FirestoreSignageRepository(firestore: _firestore);

  SignageRepository get signageRepository => _signageRepository;

  FirebaseFunctions get _firebaseFunctions =>
      _functions ??= FirebaseFunctions.instanceFor(
        region: AppConfig.firebaseFunctionsRegion,
      );

  Stream<AppUserProfile?> watchUserProfile(String uid) {
    return _users.doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return AppUserProfile.fromFirestore(snapshot.id, data);
    });
  }

  /// Schreibt nur die Push-Präferenzen ins eigene `users/{uid}`-Doc (Self-Update;
  /// alle anderen Felder bleiben unverändert → Rules erlauben es). Plan M5.
  Future<void> updateNotificationPrefs(
    String uid,
    Map<String, dynamic> notificationPrefs,
  ) {
    return _users.doc(uid).set(
      {
        'notificationPrefs': notificationPrefs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<AppUserProfile?> getUserProfile(String uid) async {
    final snapshot = await _users.doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }
    return AppUserProfile.fromFirestore(snapshot.id, data);
  }

  Stream<List<AppUserProfile>> watchOrganizationUsers(String orgId) {
    return _users.where('orgId', isEqualTo: orgId).snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) => AppUserProfile.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return [...users]..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
        );
    });
  }

  Stream<List<UserInvite>> watchInvites(String orgId) {
    return _invites
        .where('orgId', isEqualTo: orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserInvite.fromFirestore(doc.id, doc.data()))
            .where((invite) => invite.isActive && !invite.isAccepted)
            .toList(growable: false));
  }

  Stream<List<TeamDefinition>> watchTeams(String orgId) {
    return _teamCollection(orgId).orderBy('nameLower').snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => TeamDefinition.fromFirestore(doc.id, doc.data()))
            .toList(growable: false));
  }

  Stream<List<SiteDefinition>> watchSites(String orgId) {
    return _siteCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => SiteDefinition.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Stream<List<QualificationDefinition>> watchQualifications(String orgId) {
    return _qualificationCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => QualificationDefinition.fromFirestore(
                    doc.id,
                    doc.data(),
                  ))
              .toList(growable: false),
        );
  }

  Stream<List<EmploymentContract>> watchEmploymentContracts(String orgId) {
    return _employmentContractCollection(orgId)
        .orderBy('validFrom', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmploymentContract.fromFirestore(
                    doc.id,
                    doc.data(),
                  ))
              .toList(growable: false),
        );
  }

  /// Self-scoped Vertrags-Stream (PA-0.2): nur die eigenen Vertraege eines
  /// Mitarbeiters. Weil `employmentContracts` seit PA-0.2 nicht mehr org-weit
  /// lesbar ist (Verguetungs-Leck), abonnieren Nicht-Manager ausschliesslich
  /// diese Variante. Nutzt den Composite-Index employmentContracts(userId,
  /// validFrom DESC).
  Stream<List<EmploymentContract>> watchEmploymentContractsForUser(
    String orgId,
    String userId,
  ) {
    return _employmentContractCollection(orgId)
        .where('userId', isEqualTo: userId)
        .orderBy('validFrom', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmploymentContract.fromFirestore(
                    doc.id,
                    doc.data(),
                  ))
              .toList(growable: false),
        );
  }

  Stream<List<EmployeeShiftPreference>> watchShiftPreferences(String orgId) {
    return _shiftPreferenceCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeShiftPreference.fromFirestore(
                    doc.id,
                    doc.data(),
                  ))
              .toList(growable: false),
        );
  }

  Stream<List<EmployeeSiteAssignment>> watchSiteAssignments(String orgId) {
    return _siteAssignmentCollection(orgId).orderBy('siteName').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeSiteAssignment.fromFirestore(
                    doc.id,
                    doc.data(),
                  ))
              .toList(growable: false),
        );
  }

  Stream<List<ComplianceRuleSet>> watchRuleSets(String orgId) {
    return _ruleSetCollection(orgId).orderBy('nameLower').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ComplianceRuleSet.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Stream<List<TravelTimeRule>> watchTravelTimeRules(String orgId) {
    return _travelTimeRuleCollection(orgId).snapshots().map((snapshot) {
      final rules = snapshot.docs
          .map((doc) => TravelTimeRule.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return [...rules]..sort((a, b) {
          final fromCompare = a.fromSiteId.compareTo(b.fromSiteId);
          if (fromCompare != 0) {
            return fromCompare;
          }
          return a.toSiteId.compareTo(b.toSiteId);
        });
    });
  }

  Stream<List<Supplier>> watchSuppliers(String orgId) =>
      _inventoryRepository.watchSuppliers(orgId);

  Stream<List<Product>> watchProducts(String orgId) =>
      _inventoryRepository.watchProducts(orgId);

  Stream<List<PurchaseOrder>> watchPurchaseOrders(String orgId) =>
      _inventoryRepository.watchPurchaseOrders(orgId);

  Stream<List<CustomerOrder>> watchCustomerOrders(String orgId) =>
      _inventoryRepository.watchCustomerOrders(orgId);

  /// Letzte Bestandsbewegungen, optional auf einen Artikel gefiltert.
  Stream<List<StockMovement>> watchStockMovements(
    String orgId, {
    String? productId,
    int limit = 100,
  }) =>
      _inventoryRepository.watchStockMovements(
        orgId,
        productId: productId,
        limit: limit,
      );

  Stream<List<WorkEntry>> watchWorkEntries({
    required String orgId,
    required String userId,
    required DateTime month,
  }) {
    final range = _monthRange(month);
    return _entryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        )
        .where('date', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WorkEntry.fromFirestore(doc.id, doc.data()))
            .toList(growable: false));
  }

  Future<List<WorkEntry>> getWorkEntriesForMonth({
    required String orgId,
    required String userId,
    required DateTime month,
  }) async {
    final range = _monthRange(month);
    final snapshot = await _entryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        )
        .where('date', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => WorkEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  /// Liest die Zeiteinträge ALLER Mitarbeiter eines Monats (org-weit, ohne
  /// userId-Filter). Basis der Personalkosten-Auswertung im Personal-Bereich.
  /// Range + orderBy auf demselben Feld `date` → kein zusätzlicher Composite-Index.
  Future<List<WorkEntry>> getOrgWorkEntriesForMonth({
    required String orgId,
    required DateTime month,
  }) async {
    final range = _monthRange(month);
    final snapshot = await _entryCollection(orgId)
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        )
        .where('date', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => WorkEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WorkEntry>> getWorkEntriesInRange({
    required String orgId,
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rangeStart = DateTime(
      start.year,
      start.month,
      start.day,
    ).subtract(const Duration(days: 1));
    final rangeEnd = DateTime(
      end.year,
      end.month,
      end.day + 2,
    );

    final snapshot = await _entryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        )
        .where('date', isLessThan: Timestamp.fromDate(rangeEnd))
        .orderBy('date', descending: true)
        .get();

    final entries = snapshot.docs
        .map((doc) => WorkEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
    return [...entries]..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<WorkEntry>> getAllWorkEntries({
    required String orgId,
    required String userId,
  }) async {
    final snapshot = await _entryCollection(orgId)
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => WorkEntry.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  Stream<List<WorkTemplate>> watchWorkTemplates({
    required String orgId,
    required String userId,
  }) {
    return _templateCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final templates = snapshot.docs
          .map((doc) => WorkTemplate.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return [...templates]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  Future<List<WorkTemplate>> getWorkTemplates({
    required String orgId,
    required String userId,
  }) async {
    final snapshot = await _templateCollection(orgId)
        .where('userId', isEqualTo: userId)
        .get();

    final templates = snapshot.docs
        .map((doc) => WorkTemplate.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
    return [...templates]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Stream<List<Shift>> watchShifts({
    required String orgId,
    required DateTime start,
    required DateTime end,
    String? userId,
  }) {
    Query<Map<String, dynamic>> query = _shiftCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    query = query
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime');

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => Shift.fromFirestore(doc.id, doc.data()))
        .toList(growable: false));
  }

  Future<List<Shift>> getAllShifts({
    required String orgId,
    String? userId,
  }) async {
    Query<Map<String, dynamic>> query = _shiftCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    final snapshot = await query.orderBy('startTime').get();
    return snapshot.docs
        .map((doc) => Shift.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  Stream<List<ShiftTemplate>> watchShiftTemplates({
    required String orgId,
    required String userId,
  }) {
    return _shiftTemplateCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final templates = snapshot.docs
          .map((doc) => ShiftTemplate.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return [...templates]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  Future<List<ShiftTemplate>> getShiftTemplates({
    required String orgId,
    required String userId,
  }) async {
    final snapshot = await _shiftTemplateCollection(orgId)
        .where('userId', isEqualTo: userId)
        .get();

    final templates = snapshot.docs
        .map((doc) => ShiftTemplate.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
    return [...templates]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Stream<List<AbsenceRequest>> watchAbsenceRequests({
    required String orgId,
    required DateTime start,
    required DateTime end,
    String? userId,
  }) {
    Query<Map<String, dynamic>> query = _absenceCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    query = query
        .where(
          'startDate',
          isLessThanOrEqualTo: Timestamp.fromDate(end),
        )
        .orderBy('startDate', descending: false);

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
        .where(
          (request) => request.overlaps(start, end),
        )
        .toList(growable: false));
  }

  Stream<List<AbsenceRequest>> watchAllAbsenceRequests({
    required String orgId,
    String? userId,
  }) {
    Query<Map<String, dynamic>> query = _absenceCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    return query.snapshots().map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
      return [...requests]..sort(_compareAbsenceRequests);
    });
  }

  Future<List<AbsenceRequest>> getAllAbsenceRequests({
    required String orgId,
    String? userId,
  }) async {
    Query<Map<String, dynamic>> query = _absenceCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    final snapshot = await query.get();
    final requests = snapshot.docs
        .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
    return [...requests]..sort(_compareAbsenceRequests);
  }

  /// Gemeinsamer Sortiervergleich fuer Abwesenheitsantraege:
  /// aufsteigend nach Startdatum, bei Gleichstand absteigend nach
  /// updatedAt (Fallback createdAt, dann startDate). Wird von
  /// [watchAllAbsenceRequests] und [getAllAbsenceRequests] genutzt.
  static int _compareAbsenceRequests(AbsenceRequest a, AbsenceRequest b) {
    final byStart = a.startDate.compareTo(b.startDate);
    if (byStart != 0) {
      return byStart;
    }
    final aUpdated = a.updatedAt ?? a.createdAt ?? a.startDate;
    final bUpdated = b.updatedAt ?? b.createdAt ?? b.startDate;
    return bUpdated.compareTo(aUpdated);
  }

  Future<void> saveWorkEntry(WorkEntry entry) async {
    // Stabile Client-ID fuer Neuanlagen: Der Server schreibt unter
    // `entry.id ?? hash`, der direkte Fallback unter derselben ID. Geht das
    // Callable-Ack verloren (deadline-exceeded/unavailable NACH dem Commit),
    // schreibt der Fallback denselben Doc statt eines zufaelligen Duplikats
    // (probleme #3). Zwei fachlich identische Eintraege erhalten verschiedene
    // IDs und ueberschreiben sich nicht mehr (probleme #8).
    final isNew = entry.id == null;
    final stableEntry = isNew ? entry.copyWith(id: _uuid.v4()) : entry;
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertWorkEntry',
        {
          'entry': stableEntry.toMap(),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveWorkEntryDirect(stableEntry, isNew: isNew);
  }

  /// Max. Anzahl Elemente pro Callable-Aufruf (Server lehnt groessere Batches
  /// mit `resource-exhausted` ab). Grosse Batches werden clientseitig in
  /// Chunks aufgeteilt.
  static const int _maxCallableBatchSize = 50;

  List<List<T>> _chunked<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = i + size < items.length ? i + size : items.length;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  /// Stellt sicher, dass ein Batch nur Dokumente **einer** Org enthält — die
  /// Batch-Direktschreiber leiten Collection/orgId aus `first` ab; gemischte
  /// orgIds würden sonst in die falsche Org geschrieben (probleme services-firestore).
  void _assertSameOrg(Iterable<String> orgIds) {
    final first = orgIds.first;
    if (orgIds.any((id) => id != first)) {
      throw StateError(
        'Batch enthält gemischte Organisationen – nur ein Mandant pro Batch erlaubt.',
      );
    }
  }

  Future<void> saveWorkEntryBatch(List<WorkEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    _assertSameOrg(entries.map((e) => e.orgId));
    for (final chunk in _chunked(entries, _maxCallableBatchSize)) {
      await _saveWorkEntryBatchChunk(chunk);
    }
  }

  Future<void> _saveWorkEntryBatchChunk(List<WorkEntry> entries) async {
    // Stabile Client-IDs fuer Neuanlagen (siehe saveWorkEntry, probleme #3/#8).
    final stableEntries = entries
        .map((entry) =>
            entry.id == null ? entry.copyWith(id: _uuid.v4()) : entry)
        .toList(growable: false);
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertWorkEntryBatch',
        {
          'orgId': stableEntries.first.orgId,
          'entries': stableEntries
              .map((entry) => entry.toMap())
              .toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveWorkEntryBatchDirect(stableEntries);
  }

  Future<void> _saveWorkEntryDirect(
    WorkEntry entry, {
    required bool isNew,
  }) async {
    final collection = _entryCollection(entry.orgId);
    final docRef =
        entry.id == null ? collection.doc() : collection.doc(entry.id);
    await docRef.set({
      ...entry.copyWith(id: docRef.id).toFirestoreMap(),
      // createdAt nur fuer Neuanlagen stempeln (entry traegt jetzt eine
      // stabile ID, daher kann `id == null` das nicht mehr signalisieren).
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveWorkEntryBatchDirect(List<WorkEntry> entries) async {
    final collection = _entryCollection(entries.first.orgId);
    final batch = _firestore.batch();
    final refs = entries
        .map((entry) =>
            entry.id == null ? collection.doc() : collection.doc(entry.id))
        .toList(growable: false);
    // createdAt nur fuer noch nicht existierende Docs stempeln. Da Eintraege
    // jetzt stabile IDs tragen, signalisiert `id == null` keine Neuanlage mehr
    // — daher echter Existenz-Check (analog _saveShiftBatchDirect).
    final existingSnapshots = refs.isEmpty
        ? const <DocumentSnapshot<Map<String, dynamic>>>[]
        : await Future.wait(refs.map((ref) => ref.get()));
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final docRef = refs[index];
      batch.set(
        docRef,
        {
          ...entry.copyWith(id: docRef.id).toFirestoreMap(),
          if (!existingSnapshots[index].exists)
            'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await retryTransient(batch.commit, baseDelay: _retryBaseDelay);
  }

  Future<void> deleteWorkEntry({
    required String orgId,
    required String entryId,
  }) {
    return _entryCollection(orgId).doc(entryId).delete();
  }

  Future<void> saveWorkTemplate(WorkTemplate template) async {
    final collection = _templateCollection(template.orgId);
    final docRef =
        template.id == null ? collection.doc() : collection.doc(template.id);
    await docRef.set({
      ...template.copyWith(id: docRef.id).toFirestoreMap(),
      if (template.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveShiftTemplate(ShiftTemplate template) async {
    final collection = _shiftTemplateCollection(template.orgId);
    final docRef =
        template.id == null ? collection.doc() : collection.doc(template.id);
    await docRef.set({
      ...template.copyWith(id: docRef.id).toFirestoreMap(),
      if (template.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWorkTemplate({
    required String orgId,
    required String templateId,
  }) {
    return _templateCollection(orgId).doc(templateId).delete();
  }

  Future<void> deleteShiftTemplate({
    required String orgId,
    required String templateId,
  }) {
    return _shiftTemplateCollection(orgId).doc(templateId).delete();
  }

  Future<void> upsertUserProfile(
    AppUserProfile profile, {
    bool includeCreatedAt = false,
  }) async {
    await _users.doc(profile.uid).set({
      ...profile.toFirestoreMap(),
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setUserActive({
    required String uid,
    required bool isActive,
  }) {
    return _users.doc(uid).set({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createOrUpdateInvite(UserInvite invite) async {
    final docRef = _invites.doc(invite.id ?? _inviteDocId(invite.email));
    await docRef.set({
      ...invite.copyWith(id: docRef.id).toFirestoreMap(),
      if (invite.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteInvite(String inviteId) => _invites.doc(inviteId).delete();

  /// Speichert ein Team und liefert die (ggf. neu vergebene) Doc-ID zurück,
  /// damit Aufrufer das Audit-Log korrekt verknüpfen können.
  Future<String> saveTeam(TeamDefinition team) async {
    final collection = _teamCollection(team.orgId);
    final docRef = team.id == null ? collection.doc() : collection.doc(team.id);
    await docRef.set({
      ...team.copyWith(id: docRef.id).toFirestoreMap(),
      if (team.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteTeam({
    required String orgId,
    required String teamId,
  }) {
    return _teamCollection(orgId).doc(teamId).delete();
  }

  Future<String> saveSite(SiteDefinition site) async {
    final collection = _siteCollection(site.orgId);
    final docRef = site.id == null ? collection.doc() : collection.doc(site.id);
    await docRef.set({
      ...site.copyWith(id: docRef.id).toFirestoreMap(),
      if (site.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteSite({
    required String orgId,
    required String siteId,
  }) {
    return _siteCollection(orgId).doc(siteId).delete();
  }

  Future<String> saveQualification(
      QualificationDefinition qualification) async {
    final collection = _qualificationCollection(qualification.orgId);
    final docRef = qualification.id == null
        ? collection.doc()
        : collection.doc(qualification.id);
    await docRef.set({
      ...qualification.copyWith(id: docRef.id).toFirestoreMap(),
      if (qualification.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteQualification({
    required String orgId,
    required String qualificationId,
  }) {
    return _qualificationCollection(orgId).doc(qualificationId).delete();
  }

  Future<String> saveEmploymentContract(EmploymentContract contract) async {
    final collection = _employmentContractCollection(contract.orgId);
    final docRef =
        contract.id == null ? collection.doc() : collection.doc(contract.id);
    await docRef.set({
      ...contract.copyWith(id: docRef.id).toFirestoreMap(),
      if (contract.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  /// Speichert die Schicht-Vorgaben eines Mitarbeiters (Doc-ID = userId). Die
  /// `rules`-Liste wird vollständig ersetzt; `updatedAt` per Server-Zeitstempel.
  Future<void> saveShiftPreference(EmployeeShiftPreference preference) async {
    final docRef =
        _shiftPreferenceCollection(preference.orgId).doc(preference.userId);
    await docRef.set({
      ...preference.toFirestoreMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteShiftPreference({
    required String orgId,
    required String userId,
  }) {
    return _shiftPreferenceCollection(orgId).doc(userId).delete();
  }

  Future<void> deleteEmploymentContract({
    required String orgId,
    required String contractId,
  }) {
    return _employmentContractCollection(orgId).doc(contractId).delete();
  }

  // --- Personal-Bereich: Arbeitsaufträge & Lohn (nur Admin) ----------------
  // Bewusst ohne orderBy in der Query (kleine org-skopierte Collections):
  //   * `dueDate`/`note` dürfen null sein → orderBy würde solche Docs ausblenden,
  //   * keine zusätzlichen Composite-Indizes nötig.
  // Sortierung übernimmt der Provider clientseitig.

  Stream<List<WorkTask>> watchWorkTasks(String orgId) {
    return _workTaskCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => WorkTask.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveWorkTask(WorkTask task) async {
    final collection = _workTaskCollection(task.orgId);
    final docRef = task.id == null ? collection.doc() : collection.doc(task.id);
    await docRef.set({
      ...task.copyWith(id: docRef.id).toFirestoreMap(),
      if (task.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWorkTask({
    required String orgId,
    required String taskId,
  }) {
    return _workTaskCollection(orgId).doc(taskId).delete();
  }

  // --- Laden-To-Dos (Arbeitsmodus/Kiosk) -----------------------------------
  // Broadcast-Aufgaben je Laden (siteId) bzw. org-weit (siteId == null). Ohne
  // orderBy in der Query (kleine org-skopierte Collection, `dueDate` darf null
  // sein); die Sortierung übernimmt der Provider clientseitig.

  CollectionReference<Map<String, dynamic>> _storeTaskCollection(String orgId) =>
      _organizationDoc(orgId).collection('storeTasks');

  Stream<List<StoreTask>> watchStoreTasks(String orgId) {
    return _storeTaskCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => StoreTask.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveStoreTask(StoreTask task) async {
    final collection = _storeTaskCollection(task.orgId);
    final docRef = task.id == null ? collection.doc() : collection.doc(task.id);
    await docRef.set(
      task.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteStoreTask({
    required String orgId,
    required String taskId,
  }) {
    return _storeTaskCollection(orgId).doc(taskId).delete();
  }

  // --- Arbeitsmodus / Laden-Tablet (Kiosk): server-geprüfte PIN -------------
  // Callables (Increment 2). PIN-Hash liegt server-only in `userSecrets`; hier
  // nur die dünnen Client-Aufrufe. Fehler (falsche PIN etc.) kommen als
  // FirebaseFunctionsException zurück und werden vom KioskPinService gemappt.

  /// Setzt/ändert die Kiosk-PIN des ANGEMELDETEN Nutzers (auf dem eigenen Handy).
  Future<void> setKioskPin(String pin) async {
    await _callCloudFunction('setKioskPin', {'pin': pin});
  }

  /// Meldet am Kiosk-Gerät einen Mitarbeiter per PIN an und liefert die
  /// Session-ID (`sid`). Wirft bei falscher PIN/Sperre.
  Future<String> kioskBeginSession({
    required String employeeId,
    required String pin,
    String? deviceId,
  }) async {
    final raw = await _callCloudFunction('kioskBeginSession', {
      'employeeId': employeeId,
      'pin': pin,
      if (deviceId != null) 'deviceId': deviceId,
    });
    final sid = _callableResultData(raw)['sid']?.toString();
    if (sid == null || sid.isEmpty) {
      throw StateError('Kiosk-Anmeldung fehlgeschlagen.');
    }
    return sid;
  }

  /// Beendet eine Kiosk-Session serverseitig (Logout/„Fertig").
  Future<void> kioskEndSession(String sid) async {
    await _callCloudFunction('kioskEndSession', {'sid': sid});
  }

  /// Admin setzt die Kiosk-PIN eines Mitarbeiters zurück (löscht den Hash und
  /// hebt eine Sperre auf) — Teil des Offboarding-Flows (PA-7.3). Serverseitig
  /// admin-gegatet (`resetKioskPin`-Callable).
  Future<void> resetKioskPin(String employeeId) async {
    await _callCloudFunction('resetKioskPin', {'employeeId': employeeId});
  }

  /// Löscht ein Konto **komplett** (Plan `plan/account-loeschung.md`): entfernt
  /// den Firebase-Auth-Nutzer + persönliche Daten hart und anonymisiert die
  /// aufbewahrungspflichtigen Zeit-/Lohndaten. Läuft ausschließlich serverseitig
  /// (Admin SDK) — `users/{uid}` ist per Rules client-unlöschbar. Server prüft
  /// Self- vs. Admin-Berechtigung, gleiche Org und den Letzter-Admin-Schutz.
  ///
  /// [userId] == eigene uid ⇒ Selbst-Löschung; sonst Admin-Fremdlöschung.
  /// Es gibt **keinen** Direkt-Write-Fallback: ist die Callable nicht deployt,
  /// schlägt der Aufruf hart fehl (`not-found`/`unavailable`).
  Future<void> deleteUserAccount(String userId) async {
    await _callCloudFunction('deleteUserAccount', {'userId': userId});
  }

  /// „Wer ist gerade im Dienst" (PA-4.5b): live-Stream der server-gepflegten
  /// `kioskPresence`-Projektion (nur Name/Standort/Kommen). Für das
  /// Kiosk-Board — das Gerätekonto darf `clockEntries` nicht lesen.
  Stream<List<({String name, String? siteName, DateTime? kommen})>>
      watchKioskPresence(String orgId) {
    return _organizationDoc(orgId).collection('kioskPresence').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                final kommen = data['kommen'];
                return (
                  name: (data['name'] ?? '').toString(),
                  siteName: data['siteName'] as String?,
                  kommen: kommen is Timestamp ? kommen.toDate() : null,
                );
              })
              .where((e) => e.name.trim().isNotEmpty)
              .toList(growable: false),
        );
  }

  /// Kiosk-Anmelde-Roster (PA-4.4b): Datensparsamkeits-Projektion
  /// `kioskRoster/{uid}` (nur Name + aktiv, gepflegt vom
  /// `onUserWrittenKioskRoster`-Trigger) — das geteilte Tablet liest damit NIE
  /// die vollen `users`-Docs (Stundensatz etc.). Liefert synthetische, minimale
  /// [AppUserProfile]-Objekte (nur uid/orgId/Name/aktiv), die für Kiosk-Login
  /// und Stempel-Callables reichen.
  Future<List<AppUserProfile>> getKioskRoster(String orgId) async {
    final snapshot =
        await _organizationDoc(orgId).collection('kioskRoster').get();
    final list = snapshot.docs
        .map((doc) {
          final data = doc.data();
          return AppUserProfile(
            uid: doc.id,
            orgId: orgId,
            email: '',
            role: UserRole.employee,
            isActive: data['isActive'] != false,
            settings: UserSettings(name: (data['name'] ?? '').toString()),
          );
        })
        .where((p) => p.isActive && p.settings.name.trim().isNotEmpty)
        .toList();
    list.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// Stempeln am Kiosk für den Session-Mitarbeiter. [direction] = `'in'` |
  /// `'out'` | `'status'`. Liefert den resultierenden Zustand
  /// (`clockedIn == true` = eingestempelt). Schreibt server-seitig als der
  /// Mitarbeiter (Admin-SDK), autorisiert über die Session-`sid`.
  Future<bool> kioskClockPunch({
    required String sid,
    required String direction,
    String? siteId,
    String? siteName,
    String? shiftId,
    int? pauseMinuten,
  }) async {
    final raw = await _callCloudFunction('kioskClockPunch', {
      'sid': sid,
      'direction': direction,
      if (siteId != null) 'siteId': siteId,
      if (siteName != null) 'siteName': siteName,
      if (shiftId != null) 'shiftId': shiftId,
      if (pauseMinuten != null) 'pauseMinuten': pauseMinuten,
    });
    return _callableResultData(raw)['clockedIn'] == true;
  }

  /// **Kassen-Modul M6-E** — gehärtete Kiosk-Kassenzählung über die
  /// server-geprüfte Session (`kioskSaveCashCount`). Blind: nur Betrag + Notiz;
  /// Soll/Differenz setzt der Server bewusst NICHT. Liefert die CashCount-ID.
  Future<String?> kioskSaveCashCount({
    required String sid,
    required int countedCents,
    required String businessDay,
    String? note,
    String? siteId,
    int? cashRegisterId,
    List<ThirdPartyAmount> thirdParty = const [],
  }) async {
    final raw = await _callCloudFunction('kioskSaveCashCount', {
      'sid': sid,
      'countedCents': countedCents,
      'businessDay': businessDay,
      if (note != null) 'note': note,
      if (siteId != null) 'siteId': siteId,
      if (cashRegisterId != null) 'cashRegisterId': cashRegisterId,
      // Dritte-Hand-/Fremdgeld-Beträge (§8.7) — camelCase-Liste, der Server
      // validiert + erzwingt Blind (expectedCents null).
      if (thirdParty.isNotEmpty)
        'thirdParty':
            thirdParty.map((e) => e.toFirestoreMap()).toList(growable: false),
    });
    final id = _callableResultData(raw)['cashCountId'];
    return id is String ? id : null;
  }

  // === Passwortmanager (§9) — Callable-Bridge ==============================
  // Alle Pfade laufen über Callables (kein Direkt-Read/-Write). snake_case
  // Payloads; Metadaten kommen server-gefiltert über listPasswordEntries.

  /// Server-gefilterte, sichtbare Metadaten (kein Secret).
  Future<List<PasswordEntry>> listPasswordEntries(String orgId) async {
    final raw = await _callCloudFunction('listPasswordEntries', {'orgId': orgId});
    final list = _callableResultData(raw)['entries'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return PasswordEntry.fromFirestore((m['id'] ?? '').toString(), m);
    }).toList(growable: false);
  }

  /// Legt an/aktualisiert Metadaten (+ optional Klartext-Secret). Liefert die ID.
  Future<String?> upsertPasswordEntry({
    required PasswordEntry entry,
    String? plainUsername,
    String? plainPassword,
    String? plainNotes,
  }) async {
    final raw = await _callCloudFunction('upsertPasswordEntry', {
      if (entry.id != null) 'entry_id': entry.id,
      'entry': entry.toMap(),
      if (plainUsername != null) 'plain_username': plainUsername,
      if (plainPassword != null) 'plain_password': plainPassword,
      if (plainNotes != null) 'plain_notes': plainNotes,
    });
    final id = _callableResultData(raw)['entry_id'];
    return id is String ? id : null;
  }

  Future<void> deletePasswordEntry({
    required String orgId,
    required String entryId,
  }) async {
    await _callCloudFunction('deletePasswordEntry', {
      'org_id': orgId,
      'entry_id': entryId,
    });
  }

  /// Server-signierten Reauth-Nonce anfordern (Pflicht vor Reveal).
  Future<String?> beginPasswordReauth(String orgId) async {
    final raw =
        await _callCloudFunction('beginPasswordReauth', {'org_id': orgId});
    final t = _callableResultData(raw)['reauth_token'];
    return t is String ? t : null;
  }

  /// Einziger Klartext-Pfad — autorisiert + auditiert.
  Future<PasswordSecret> revealPasswordSecret({
    required String orgId,
    required String entryId,
    String? reauthToken,
    String? reason,
  }) async {
    final raw = await _callCloudFunction('revealPasswordSecret', {
      'org_id': orgId,
      'entry_id': entryId,
      if (reauthToken != null) 'reauth_token': reauthToken,
      if (reason != null) 'reason': reason,
    });
    final d = _callableResultData(raw);
    return PasswordSecret(
      username: (d['username'] ?? '').toString(),
      password: (d['password'] ?? '').toString(),
      notes: (d['notes'] ?? '').toString(),
    );
  }

  Future<void> logPasswordCopy({
    required String orgId,
    required String entryId,
    String? field,
  }) async {
    await _callCloudFunction('logPasswordCopy', {
      'org_id': orgId,
      'entry_id': entryId,
      if (field != null) 'field': field,
    });
  }

  Stream<List<PayrollRecord>> watchPayrollRecords(String orgId) {
    return _payrollRecordCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => PayrollRecord.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped** Lohnabrechnungen eines Mitarbeiters (PA-7.1): nur
  /// freigegebene/bezahlte (Entwürfe bleiben unsichtbar). Der `status`-whereIn
  /// muss exakt der Self-Read-Regel entsprechen (Rules sind kein Filter). Nutzt
  /// den Composite-Index payrollRecords(userId, status).
  Stream<List<PayrollRecord>> watchPayrollRecordsForUser({
    required String orgId,
    required String userId,
  }) {
    return _payrollRecordCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['freigegeben', 'bezahlt'])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PayrollRecord.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert eine Lohnabrechnung unter der deterministischen Doc-ID
  /// (`<userId>-<jahr>-<mm>`), damit eine erneute Abrechnung desselben Monats
  /// überschreibt statt zu duplizieren.
  Future<void> savePayrollRecord(PayrollRecord record) async {
    final collection = _payrollRecordCollection(record.orgId);
    final docId = record.id ?? record.documentId;
    await collection.doc(docId).set(
      record.copyWith(id: docId).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deletePayrollRecord({
    required String orgId,
    required String recordId,
  }) {
    return _payrollRecordCollection(orgId).doc(recordId).delete();
  }

  Stream<List<PayrollProfile>> watchPayrollProfiles(String orgId) {
    return _payrollProfileCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => PayrollProfile.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert ein Lohn-Stammdatenprofil unter der deterministischen Doc-ID
  /// (`userId`), damit es je Mitarbeiter genau einmal existiert.
  Future<void> savePayrollProfile(PayrollProfile profile) async {
    final collection = _payrollProfileCollection(profile.orgId);
    final docId = profile.id ?? profile.documentId;
    await collection.doc(docId).set(
          profile.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deletePayrollProfile({
    required String orgId,
    required String userId,
  }) {
    return _payrollProfileCollection(orgId).doc(userId).delete();
  }

  Stream<List<EmployeeProfile>> watchEmployeeProfiles(String orgId) {
    return _employeeProfileCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeProfile.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped** Personal-Stammakte eines Mitarbeiters (PA-2.3-Self-Read).
  /// Bewusst als Gleichheits-**Query** (`userId`) statt `.doc(userId)`: Ein
  /// direkter Doc-Read einer noch nicht existierenden Akte würde die Self-Read-
  /// Regel (`resource.data.userId == uid`) mit `resource == null` auswerten →
  /// permission-denied statt „leer"; die Query liefert bei fehlendem Profil
  /// sauber eine leere Liste. Doc-ID == userId → 0/1 Treffer, kein Index nötig.
  Stream<List<EmployeeProfile>> watchEmployeeProfileForUser({
    required String orgId,
    required String userId,
  }) {
    return _employeeProfileCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeProfile.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert die Personal-Stammakte unter der deterministischen Doc-ID
  /// (`userId`), damit sie je Mitarbeiter genau einmal existiert.
  Future<void> saveEmployeeProfile(EmployeeProfile profile) async {
    final collection = _employeeProfileCollection(profile.orgId);
    final docId = profile.id ?? profile.documentId;
    await collection.doc(docId).set(
          profile.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteEmployeeProfile({
    required String orgId,
    required String userId,
  }) {
    return _employeeProfileCollection(orgId).doc(userId).delete();
  }

  // --- Personalakte-Dokumente (PA-3, Metadaten) ----------------------------

  /// Frische Doc-ID für ein neues Dokument (= Storage-`docId`, damit Objektpfad
  /// und Metadaten-Doc dieselbe ID tragen).
  String newEmployeeDocumentId(String orgId) =>
      _employeeDocumentCollection(orgId).doc().id;

  /// Alle Dokumente (Admin-Sicht) – ohne `orderBy`, clientseitig sortiert
  /// (kein Composite-Index, Personal-Modul-Konvention).
  Stream<List<EmployeeDocument>> watchEmployeeDocuments(String orgId) {
    return _employeeDocumentCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeDocument.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped**: nur die dem Mitarbeiter SICHTBAREN eigenen Dokumente. Die
  /// zwei Gleichheitsfilter (`userId` + `visibleToEmployee`) müssen exakt der
  /// Self-Read-Regel entsprechen — Rules sind kein Filter, ein Mit-Abfragen
  /// interner Dokumente würde die ganze Query permission-denyen. Zwei
  /// Gleichheitsfilter brauchen keinen Composite-Index; Sortierung clientseitig.
  Stream<List<EmployeeDocument>> watchEmployeeDocumentsForUser({
    required String orgId,
    required String userId,
  }) {
    return _employeeDocumentCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('visibleToEmployee', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployeeDocument.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Legt/aktualisiert das Metadaten-Doc. Doc-ID = `document.id` (vom Aufrufer,
  /// passend zum Storage-Pfad).
  Future<void> saveEmployeeDocument(EmployeeDocument document) async {
    final collection = _employeeDocumentCollection(document.orgId);
    final docId = document.id ?? collection.doc().id;
    await collection.doc(docId).set(
          document.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteEmployeeDocument({
    required String orgId,
    required String docId,
  }) {
    return _employeeDocumentCollection(orgId).doc(docId).delete();
  }

  /// Lesebestätigung durch den Mitarbeiter (feldgranular — nur `acknowledgedAt`
  /// + `updatedAt`, passend zur Self-Update-Allowlist der Rules).
  Future<void> acknowledgeEmployeeDocument({
    required String orgId,
    required String docId,
  }) {
    return _employeeDocumentCollection(orgId).doc(docId).set(
      {
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Sollzeit-Profile (Arbeitszeitmodelle, gültig-ab-versioniert) – bewusst OHNE
  /// `orderBy` abgefragt (Sortierung clientseitig), damit kein Composite-Index
  /// nötig ist (Personal-Modul-Konvention).
  Stream<List<SollzeitProfile>> watchSollzeitProfiles(String orgId) {
    return _sollzeitProfileCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => SollzeitProfile.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped** Sollzeit-Profile eines Mitarbeiters (M7-Self-Read) — ein
  /// Gleichheitsfilter (`userId`), kein `orderBy` → kein Composite-Index. Damit
  /// laden reguläre Mitarbeiter ihr eigenes Soll (Stundenkonto/Mein-Monatsabschluss),
  /// abgesichert durch die `sollzeitProfiles`-Self-Read-Regel.
  Stream<List<SollzeitProfile>> watchSollzeitProfilesForUser({
    required String orgId,
    required String userId,
  }) {
    return _sollzeitProfileCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SollzeitProfile.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert ein Sollzeit-Profil. Mehrere je Mitarbeiter möglich (Auto-ID für
  /// neue Datensätze, wie bei [saveEmploymentContract]).
  Future<void> saveSollzeitProfile(SollzeitProfile profile) async {
    final collection = _sollzeitProfileCollection(profile.orgId);
    final docRef =
        profile.id == null ? collection.doc() : collection.doc(profile.id);
    await docRef.set(
      profile.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteSollzeitProfile({
    required String orgId,
    required String profileId,
  }) {
    return _sollzeitProfileCollection(orgId).doc(profileId).delete();
  }

  /// Org-/jahr-spezifische Lohn-Konfiguration (`payrollConfig/{jahr}`) – ohne
  /// `orderBy` (Sortierung clientseitig), damit kein Composite-Index nötig ist.
  Stream<List<OrgPayrollSettings>> watchOrgPayrollSettings(String orgId) {
    return _payrollConfigCollection(orgId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) =>
                  OrgPayrollSettings.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert die Lohn-Konfiguration unter der deterministischen Doc-ID
  /// (Bezugsjahr), damit je Org/Jahr genau ein Datensatz existiert.
  Future<void> saveOrgPayrollSettings(OrgPayrollSettings config) async {
    final collection = _payrollConfigCollection(config.orgId);
    final docId = config.id ?? config.documentId;
    await collection.doc(docId).set(
          config.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteOrgPayrollSettings({
    required String orgId,
    required int jahr,
  }) {
    return _payrollConfigCollection(orgId).doc(jahr.toString()).delete();
  }

  // --- HR-Sub-Entitäten: Kinder / Qualifikationen / Ausbildung (Admin) ------
  // Bewusst OHNE orderBy (clientseitig sortiert) → kein Composite-Index.

  Stream<List<EmployeeChild>> watchEmployeeChildren(String orgId) {
    return _employeeChildCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) => EmployeeChild.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveEmployeeChild(EmployeeChild child) async {
    final collection = _employeeChildCollection(child.orgId);
    final docRef = child.id == null ? collection.doc() : collection.doc(child.id);
    await docRef.set(
      child.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEmployeeChild({
    required String orgId,
    required String childId,
  }) {
    return _employeeChildCollection(orgId).doc(childId).delete();
  }

  Stream<List<EmployeeNote>> watchEmployeeNotes(String orgId) {
    return _employeeNoteCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) => EmployeeNote.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveEmployeeNote(EmployeeNote note) async {
    final collection = _employeeNoteCollection(note.orgId);
    final docRef = note.id == null ? collection.doc() : collection.doc(note.id);
    await docRef.set(
      note.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEmployeeNote({
    required String orgId,
    required String noteId,
  }) {
    return _employeeNoteCollection(orgId).doc(noteId).delete();
  }

  Stream<List<EmployeeQualification>> watchEmployeeQualifications(String orgId) {
    return _employeeQualificationCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) =>
                  EmployeeQualification.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveEmployeeQualification(EmployeeQualification quali) async {
    final collection = _employeeQualificationCollection(quali.orgId);
    final docRef = quali.id == null ? collection.doc() : collection.doc(quali.id);
    await docRef.set(
      quali.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEmployeeQualification({
    required String orgId,
    required String qualificationId,
  }) {
    return _employeeQualificationCollection(orgId)
        .doc(qualificationId)
        .delete();
  }

  Stream<List<EmployeeAusbildung>> watchEmployeeAusbildungen(String orgId) {
    return _employeeAusbildungCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) =>
                  EmployeeAusbildung.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveEmployeeAusbildung(EmployeeAusbildung ausbildung) async {
    final collection = _employeeAusbildungCollection(ausbildung.orgId);
    final docRef = ausbildung.id == null
        ? collection.doc()
        : collection.doc(ausbildung.id);
    await docRef.set(
      ausbildung.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEmployeeAusbildung({
    required String orgId,
    required String ausbildungId,
  }) {
    return _employeeAusbildungCollection(orgId).doc(ausbildungId).delete();
  }

  // --- Urlaubskonto: Jahres-Vortrag + Korrektur-Ledger (Admin) --------------

  Stream<List<UrlaubskontoJahr>> watchUrlaubskontoJahre(String orgId) {
    return _urlaubskontoJahrCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) => UrlaubskontoJahr.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped** Urlaubskonto-Jahre eines Mitarbeiters (PA-7.2).
  Stream<List<UrlaubskontoJahr>> watchUrlaubskontoJahreForUser({
    required String orgId,
    required String userId,
  }) {
    return _urlaubskontoJahrCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (s) => s.docs
              .map((doc) => UrlaubskontoJahr.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Speichert unter der deterministischen Doc-ID `{userId}-{jahr}` (ein
  /// Datensatz je Mitarbeiter/Jahr, Upsert).
  Future<void> saveUrlaubskontoJahr(UrlaubskontoJahr konto) async {
    final collection = _urlaubskontoJahrCollection(konto.orgId);
    final docId = konto.id ?? konto.documentId;
    await collection.doc(docId).set(
          konto.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteUrlaubskontoJahr({
    required String orgId,
    required String docId,
  }) {
    return _urlaubskontoJahrCollection(orgId).doc(docId).delete();
  }

  Stream<List<Urlaubsanpassung>> watchUrlaubsanpassungen(String orgId) {
    return _urlaubsanpassungCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) => Urlaubsanpassung.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// **Self-scoped** Urlaubs-Anpassungen eines Mitarbeiters (PA-7.2).
  Stream<List<Urlaubsanpassung>> watchUrlaubsanpassungenForUser({
    required String orgId,
    required String userId,
  }) {
    return _urlaubsanpassungCollection(orgId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (s) => s.docs
              .map((doc) => Urlaubsanpassung.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveUrlaubsanpassung(Urlaubsanpassung anpassung) async {
    final collection = _urlaubsanpassungCollection(anpassung.orgId);
    final docRef =
        anpassung.id == null ? collection.doc() : collection.doc(anpassung.id);
    await docRef.set(
      anpassung.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deleteUrlaubsanpassung({
    required String orgId,
    required String anpassungId,
  }) {
    return _urlaubsanpassungCollection(orgId).doc(anpassungId).delete();
  }

  // --- Lohnarten-Katalog (Admin) -------------------------------------------

  Stream<List<PayLineType>> watchPayLineTypes(String orgId) {
    return _payLineTypeCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((doc) => PayLineType.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> savePayLineType(PayLineType type) async {
    final collection = _payLineTypeCollection(type.orgId);
    final docRef = type.id == null ? collection.doc() : collection.doc(type.id);
    await docRef.set(
      type.copyWith(id: docRef.id).toFirestoreMap(),
      SetOptions(merge: true),
    );
  }

  Future<void> deletePayLineType({
    required String orgId,
    required String typeId,
  }) {
    return _payLineTypeCollection(orgId).doc(typeId).delete();
  }

  // --- Finanzen: Kostenstellen/Kostenarten/Journal/Budgets (nur Admin) ------

  Stream<List<CostCenter>> watchCostCenters(String orgId) {
    return _costCenterCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((d) => CostCenter.fromFirestore(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveCostCenter(CostCenter center) async {
    final collection = _costCenterCollection(center.orgId);
    final docRef =
        center.id == null ? collection.doc() : collection.doc(center.id);
    await docRef.set({
      ...center.copyWith(id: docRef.id).toFirestoreMap(),
      if (center.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCostCenter({
    required String orgId,
    required String id,
  }) {
    return _costCenterCollection(orgId).doc(id).delete();
  }

  Stream<List<CostType>> watchCostTypes(String orgId) {
    return _costTypeCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((d) => CostType.fromFirestore(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveCostType(CostType type) async {
    final collection = _costTypeCollection(type.orgId);
    final docRef = type.id == null ? collection.doc() : collection.doc(type.id);
    await docRef.set({
      ...type.copyWith(id: docRef.id).toFirestoreMap(),
      if (type.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCostType({required String orgId, required String id}) {
    return _costTypeCollection(orgId).doc(id).delete();
  }

  Stream<List<JournalEntry>> watchJournalEntries(String orgId) {
    return _journalEntryCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((d) => JournalEntry.fromFirestore(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> saveJournalEntry(JournalEntry entry) async {
    final collection = _journalEntryCollection(entry.orgId);
    final docRef =
        entry.id == null ? collection.doc() : collection.doc(entry.id);
    await docRef.set({
      ...entry.copyWith(id: docRef.id).toFirestoreMap(),
      if (entry.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteJournalEntry({
    required String orgId,
    required String id,
  }) {
    return _journalEntryCollection(orgId).doc(id).delete();
  }

  Stream<List<Budget>> watchBudgets(String orgId) {
    return _budgetCollection(orgId).snapshots().map(
          (s) => s.docs
              .map((d) => Budget.fromFirestore(d.id, d.data()))
              .toList(growable: false),
        );
  }

  /// Speichert ein Budget unter der deterministischen Doc-ID
  /// (`<costCenterId>-<costTypeId|all>-<year>`).
  Future<void> saveBudget(Budget budget) async {
    final collection = _budgetCollection(budget.orgId);
    final docId = budget.id ?? budget.documentId;
    await collection.doc(docId).set(
          budget.copyWith(id: docId).toFirestoreMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteBudget({required String orgId, required String id}) {
    return _budgetCollection(orgId).doc(id).delete();
  }

  CollectionReference<Map<String, dynamic>> _auditLogCollection(String orgId) =>
      _organizationDoc(orgId).collection('auditLog');

  /// Letzte Audit-Einträge (nach Zeit absteigend). Single-Field-orderBy →
  /// kein Composite-Index nötig.
  Stream<List<AuditLogEntry>> watchAuditLog(String orgId, {int limit = 200}) {
    return _auditLogCollection(orgId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AuditLogEntry.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Hängt einen Audit-Eintrag an (append-only, Auto-ID, serverTimestamp).
  Future<void> appendAuditLog(AuditLogEntry entry) async {
    await _auditLogCollection(entry.orgId).add(entry.toFirestoreMap());
  }

  Future<void> saveSiteAssignments({
    required String orgId,
    required String userId,
    required List<EmployeeSiteAssignment> assignments,
  }) async {
    final collection = _siteAssignmentCollection(orgId);
    final existing = await collection.where('userId', isEqualTo: userId).get();
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final assignment in assignments) {
      final docRef = assignment.id == null
          ? collection.doc()
          : collection.doc(assignment.id);
      batch.set(
        docRef,
        {
          ...assignment.copyWith(id: docRef.id).toFirestoreMap(),
          if (assignment.id == null) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<String> saveRuleSet(ComplianceRuleSet ruleSet) async {
    final collection = _ruleSetCollection(ruleSet.orgId);
    final docRef =
        ruleSet.id == null ? collection.doc() : collection.doc(ruleSet.id);
    await docRef.set({
      ...ruleSet.copyWith(id: docRef.id).toFirestoreMap(),
      if (ruleSet.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteRuleSet({
    required String orgId,
    required String ruleSetId,
  }) {
    return _ruleSetCollection(orgId).doc(ruleSetId).delete();
  }

  Future<String> saveTravelTimeRule(TravelTimeRule rule) async {
    final collection = _travelTimeRuleCollection(rule.orgId);
    final docRef = rule.id == null ? collection.doc() : collection.doc(rule.id);
    await docRef.set({
      ...rule.copyWith(id: docRef.id).toFirestoreMap(),
      if (rule.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteTravelTimeRule({
    required String orgId,
    required String ruleId,
  }) {
    return _travelTimeRuleCollection(orgId).doc(ruleId).delete();
  }

  // --- Warenwirtschaft (delegiert an InventoryRepository) ---------------

  Future<void> saveSupplier(Supplier supplier) =>
      _inventoryRepository.saveSupplier(supplier);

  Future<void> deleteSupplier({
    required String orgId,
    required String supplierId,
  }) =>
      _inventoryRepository.deleteSupplier(orgId: orgId, supplierId: supplierId);

  Future<void> saveProduct(Product product) =>
      _inventoryRepository.saveProduct(product);

  Future<void> deleteProduct({
    required String orgId,
    required String productId,
  }) =>
      _inventoryRepository.deleteProduct(orgId: orgId, productId: productId);

  /// Bucht eine Bestandsaenderung atomar. [delta] positiv = Zugang. Gibt den
  /// neuen Bestand zurueck.
  Future<int> adjustProductStock({
    required String orgId,
    required String productId,
    required int delta,
    required StockMovementType type,
    String? reason,
    String? relatedOrderId,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _inventoryRepository.adjustProductStock(
        orgId: orgId,
        productId: productId,
        delta: delta,
        type: type,
        reason: reason,
        relatedOrderId: relatedOrderId,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  Future<String> savePurchaseOrder(PurchaseOrder order) =>
      _inventoryRepository.savePurchaseOrder(order);

  Future<void> deletePurchaseOrder({
    required String orgId,
    required String orderId,
  }) =>
      _inventoryRepository.deletePurchaseOrder(orgId: orgId, orderId: orderId);

  Future<String> saveCustomerOrder(CustomerOrder order) =>
      _inventoryRepository.saveCustomerOrder(order);

  Future<void> deleteCustomerOrder({
    required String orgId,
    required String orderId,
  }) =>
      _inventoryRepository.deleteCustomerOrder(orgId: orgId, orderId: orderId);

  // --- Öffentliche Kundenwünsche (Webseite) ----------------------------
  // Kein InventoryRepository: Wünsche entstehen anonym über die öffentliche
  // Seite und sind reine Cloud-Daten (kein lokaler/Hybrid-Spiegel). Der
  // öffentliche Create-Pfad ist in firestore.rules streng allowlisted.

  CollectionReference<Map<String, dynamic>> _customerWishCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('customerWishes');

  /// Schreibt einen öffentlich abgegebenen Kundenwunsch (anonymer Aufrufer).
  /// Erwartet, dass der Aufrufer zuvor (anonym) authentifiziert ist —
  /// `firestore.rules` verlangt `request.auth != null`. `createdAt` wird als
  /// `serverTimestamp` gesetzt (Regel verlangt `== request.time`); es werden
  /// ausschließlich die allowlisteten Felder geschrieben.
  Future<String> submitCustomerWish(CustomerWish wish) async {
    final docRef = _customerWishCollection(wish.orgId).doc();
    await docRef.set({
      ...wish.toPublicSubmissionMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Eingang der Kundenwünsche (neueste zuerst). Single-Field-orderBy →
  /// kein Composite-Index nötig; Statusfilter macht der Client. [limit]
  /// begrenzt die geladene Menge (Schutz vor Flut über den öffentlichen
  /// Schreibpfad → Client-Speicher/Lesekosten).
  Stream<List<CustomerWish>> watchCustomerWishes(String orgId,
      {int limit = 300}) {
    return _customerWishCollection(orgId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CustomerWish.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Setzt den Bearbeitungsstatus eines Wunsches (interner, gegateter Pfad).
  Future<void> updateCustomerWishStatus({
    required String orgId,
    required String wishId,
    required CustomerWishStatus status,
    String? handledByUid,
    String? notes,
  }) {
    return _customerWishCollection(orgId).doc(wishId).set({
      'status': status.value,
      if (notes != null) 'notes': notes,
      'handledByUid': handledByUid,
      'handledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Verknüpft einen Wunsch mit einem [Contact] aus der Kontakte-Kartei (H-D2)
  /// bzw. löst die Verknüpfung (`contactId == null`) — interner, gegateter Pfad.
  /// `merge: true` lässt die übrigen Felder unangetastet; `contactId` ist NICHT
  /// Teil der öffentlichen Create-Allowlist (nur dieser interne Update-Pfad, in
  /// `firestore.rules` durch `canManageInventory()` + `sameOrg` gesichert).
  Future<void> updateCustomerWishContact({
    required String orgId,
    required String wishId,
    required String? contactId,
  }) {
    return _customerWishCollection(orgId).doc(wishId).set({
      'contactId': contactId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCustomerWish({
    required String orgId,
    required String wishId,
  }) =>
      _customerWishCollection(orgId).doc(wishId).delete();

  // --- Öffentliches Kundenfeedback (Webseite) --------------------------
  // Analog zu den Kundenwünschen: anonym über die öffentliche Seite (/feedback)
  // erzeugt, reine Cloud-Daten (kein lokaler/Hybrid-Spiegel). Der öffentliche
  // Create-Pfad ist in firestore.rules streng allowlisted; der Eingang ist —
  // anders als Wünsche — NUR für Manager lesbar (canManageFeedback).

  CollectionReference<Map<String, dynamic>> _customerFeedbackCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('customerFeedback');

  /// Schreibt eine öffentlich abgegebene Rückmeldung (anonymer Aufrufer).
  /// Erwartet, dass der Aufrufer zuvor (anonym) authentifiziert ist —
  /// `firestore.rules` verlangt `request.auth != null`. `createdAt` wird als
  /// `serverTimestamp` gesetzt (Regel verlangt `== request.time`); es werden
  /// ausschließlich die allowlisteten Felder geschrieben.
  Future<String> submitCustomerFeedback(CustomerFeedback feedback) async {
    final docRef = _customerFeedbackCollection(feedback.orgId).doc();
    await docRef.set({
      ...feedback.toPublicSubmissionMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Eingang der Rückmeldungen (neueste zuerst). Single-Field-orderBy →
  /// kein Composite-Index nötig; Statusfilter macht der Client. [limit]
  /// begrenzt die geladene Menge (Schutz vor Flut über den öffentlichen
  /// Schreibpfad → Client-Speicher/Lesekosten).
  Stream<List<CustomerFeedback>> watchCustomerFeedback(String orgId,
      {int limit = 300}) {
    return _customerFeedbackCollection(orgId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CustomerFeedback.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Setzt den Bearbeitungsstatus einer Rückmeldung (interner, gegateter Pfad).
  Future<void> updateCustomerFeedbackStatus({
    required String orgId,
    required String feedbackId,
    required FeedbackStatus status,
    String? handledByUid,
    String? notes,
  }) {
    return _customerFeedbackCollection(orgId).doc(feedbackId).set({
      'status': status.value,
      if (notes != null) 'notes': notes,
      'handledByUid': handledByUid,
      'handledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Verknüpft eine Rückmeldung mit einem [Contact] aus der Kontakte-Kartei
  /// (H-D2) bzw. löst die Verknüpfung (`contactId == null`) — interner, gegateter
  /// Pfad. `merge: true` lässt die übrigen Felder unangetastet; `contactId` ist
  /// NICHT Teil der öffentlichen Create-Allowlist (nur dieser interne
  /// Update-Pfad, in `firestore.rules` durch `canManageFeedback()` + `sameOrg`
  /// gesichert).
  Future<void> updateCustomerFeedbackContact({
    required String orgId,
    required String feedbackId,
    required String? contactId,
  }) {
    return _customerFeedbackCollection(orgId).doc(feedbackId).set({
      'contactId': contactId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCustomerFeedback({
    required String orgId,
    required String feedbackId,
  }) =>
      _customerFeedbackCollection(orgId).doc(feedbackId).delete();

  /// Bucht den Wareneingang fuer eine Bestellung atomar (delegiert).
  Future<void> receivePurchaseOrder({
    required String orgId,
    required String orderId,
    required Map<int, int> receivedByItemIndex,
    String? createdByUid,
    String? clientMutationId,
  }) =>
      _inventoryRepository.receivePurchaseOrder(
        orgId: orgId,
        orderId: orderId,
        receivedByItemIndex: receivedByItemIndex,
        createdByUid: createdByUid,
        clientMutationId: clientMutationId,
      );

  Future<bool> hasPendingAccessForEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (AppConfig.bootstrapAdminEmailList.contains(normalized)) {
      return true;
    }

    final snapshot = await _invites.doc(_inviteDocId(normalized)).get();
    return snapshot.exists && _isTruthy(snapshot.data()?['isActive']);
  }

  Future<AppUserProfile> ensureProfileForSignedInUser(User user) async {
    final existingSnapshot = await _users.doc(user.uid).get();
    final existingData = existingSnapshot.data();
    if (existingSnapshot.exists && existingData != null) {
      final existingProfile = AppUserProfile.fromFirestore(
        existingSnapshot.id,
        existingData,
      );
      await _normalizeExistingProfileDocument(
        existingProfile,
        rawData: existingData,
        authUser: user,
      );
      return existingProfile;
    }

    final email = (user.email ?? '').trim();
    final emailLower = email.toLowerCase();
    if (emailLower.isEmpty) {
      throw StateError(
        'Das angemeldete Konto liefert keine E-Mail-Adresse. Bitte verwende eine E-Mail-basierte Anmeldung.',
      );
    }

    final inviteDoc = await _invites.doc(_inviteDocId(emailLower)).get();

    if (inviteDoc.exists && _isTruthy(inviteDoc.data()?['isActive'])) {
      final invite = UserInvite.fromFirestore(inviteDoc.id, inviteDoc.data()!);
      final profile = AppUserProfile(
        uid: user.uid,
        orgId: invite.orgId,
        email: email,
        role: invite.role,
        isActive: invite.isActive,
        settings: invite.settings.copyWith(
          name: invite.settings.name.trim().isNotEmpty
              ? invite.settings.name
              : (user.displayName ?? ''),
        ),
        permissions: invite.effectivePermissions,
        photoUrl: user.photoURL,
      );

      await _users.doc(user.uid).set({
        ...profile.toFirestoreMap(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await inviteDoc.reference.set({
        'acceptedByUid': user.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        // M4: verbrauchte Einladung deaktivieren, damit sie nicht latent
        // re-provisionieren kann (das `users/{uid}`-Doc ist die Stammquelle).
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _ensureOrganizationIfAdmin(profile);
      return profile;
    }

    if (AppConfig.bootstrapAdminEmailList.contains(emailLower)) {
      final profile = AppUserProfile(
        uid: user.uid,
        orgId: AppConfig.defaultOrganizationId,
        email: email,
        role: UserRole.admin,
        isActive: true,
        settings: UserSettings(
          name: user.displayName ?? '',
        ),
        photoUrl: user.photoURL,
      );
      try {
        await upsertUserProfile(profile, includeCreatedAt: true);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          throw StateError(
            'Google-Anmeldung war erfolgreich, aber Firestore blockiert die Erstanlage des Admin-Profils. '
            'Lege in Firestore zuerst eine Admin-Einladung unter '
            'userInvites/$emailLower an und melde dich danach erneut an.',
          );
        }
        rethrow;
      }
      await _ensureOrganizationIfAdmin(profile);
      return profile;
    }

    throw StateError(
      'Fuer dieses Konto liegt keine Einladung vor. Bitte lasse den Account zuerst durch einen Admin freischalten.',
    );
  }

  Future<void> _normalizeExistingProfileDocument(
    AppUserProfile profile, {
    required Map<String, dynamic> rawData,
    required User authUser,
  }) async {
    final hasLegacyShape = rawData.containsKey('org_id') ||
        rawData.containsKey('is_active') ||
        rawData.containsKey('photo_url') ||
        rawData.containsKey('created_at') ||
        rawData.containsKey('updated_at') ||
        (rawData['role']?.toString().trim().toLowerCase() == 'teamleiter');
    if (!hasLegacyShape) {
      return;
    }

    final normalizedProfile = profile.copyWith(
      email: profile.email.trim().isNotEmpty
          ? profile.email
          : ((authUser.email ?? '').trim().isNotEmpty ? authUser.email : null),
      photoUrl: profile.photoUrl ?? authUser.photoURL,
      settings: profile.settings.copyWith(
        name: profile.settings.name.trim().isNotEmpty
            ? profile.settings.name
            : ((authUser.displayName ?? '').trim().isNotEmpty
                ? authUser.displayName
                : null),
      ),
    );
    if (normalizedProfile.orgId.trim().isEmpty) {
      return;
    }
    await upsertUserProfile(normalizedProfile);
  }

  Future<void> saveShift(
    Shift shift, {
    RecurrencePattern recurrencePattern = RecurrencePattern.none,
    DateTime? recurrenceEndDate,
  }) async {
    await saveShiftBatch(
      buildShiftOccurrences(
        shift,
        recurrencePattern: recurrencePattern,
        recurrenceEndDate: recurrenceEndDate,
      ),
    );
  }

  Future<void> saveShiftBatch(List<Shift> shifts) async {
    if (shifts.isEmpty) {
      return;
    }
    _assertSameOrg(shifts.map((s) => s.orgId));
    for (final chunk in _chunked(shifts, _maxCallableBatchSize)) {
      await _saveShiftBatchChunk(chunk);
    }
  }

  /// Schreibt Schichten **direkt** (ohne die `upsertShiftBatch`-Callable und
  /// damit ohne serverseitige Compliance-Prüfung). Bewusster Bypass für den
  /// Chef-Override beim Schichttausch (`confirmShiftSwapRequest`): die Rules
  /// erlauben Schicht-Updates nur Managern, der direkte Pfad spiegelt den
  /// „Sicherheitslücke per Design"-Direkt-Write. Chunked wie der Callable-Pfad.
  Future<void> saveShiftBatchDirect(List<Shift> shifts) async {
    if (shifts.isEmpty) {
      return;
    }
    final stableShifts = shifts
        .map((shift) => shift.id == null ? shift.copyWith(id: _uuid.v4()) : shift)
        .toList(growable: false);
    for (final chunk in _chunked(stableShifts, _maxCallableBatchSize)) {
      await _saveShiftBatchDirect(chunk);
    }
  }

  Future<void> _saveShiftBatchChunk(List<Shift> shifts) async {
    // Stabile Client-IDs fuer Neuanlagen (siehe saveWorkEntry, probleme #3/#8):
    // Callable (Server: `shift.id ?? hash`) und direkter Fallback schreiben
    // dieselbe Doc-ID -> kein Duplikat bei verlorenem Ack.
    final stableShifts = shifts
        .map((shift) => shift.id == null ? shift.copyWith(id: _uuid.v4()) : shift)
        .toList(growable: false);
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertShiftBatch',
        {
          'orgId': stableShifts.first.orgId,
          'shifts': stableShifts
              .map((shift) => shift.toMap())
              .toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveShiftBatchDirect(stableShifts);
  }

  Future<void> publishShiftBatch({
    required String orgId,
    required List<Shift> shifts,
    required ShiftStatus status,
  }) async {
    if (shifts.isEmpty) {
      return;
    }
    for (final chunk in _chunked(shifts, _maxCallableBatchSize)) {
      await _publishShiftBatchChunk(orgId: orgId, shifts: chunk, status: status);
    }
  }

  Future<void> _publishShiftBatchChunk({
    required String orgId,
    required List<Shift> shifts,
    required ShiftStatus status,
  }) async {
    // Stabile Client-IDs fuer etwaige Neuanlagen (siehe saveWorkEntry,
    // probleme #3/#8); bestehende Schichten behalten ihre ID.
    final stableShifts = shifts
        .map((shift) => shift.id == null ? shift.copyWith(id: _uuid.v4()) : shift)
        .toList(growable: false);
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'publishShiftBatch',
        {
          'orgId': orgId,
          'status': status.value,
          'shifts': stableShifts
              .map((shift) => shift.toMap())
              .toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveShiftBatchDirect(
      stableShifts
          .map((shift) => shift.copyWith(status: status))
          .toList(growable: false),
    );
  }

  Future<void> _saveShiftBatchDirect(List<Shift> shifts) async {
    final collection = _shiftCollection(shifts.first.orgId);
    final batch = _firestore.batch();
    final refs = shifts
        .map(
          (occurrence) => occurrence.id == null
              ? collection.doc()
              : collection.doc(occurrence.id),
        )
        .toList(growable: false);
    final existingSnapshots = refs.isEmpty
        ? const <DocumentSnapshot<Map<String, dynamic>>>[]
        : await Future.wait(refs.map((ref) => ref.get()));
    for (var index = 0; index < shifts.length; index++) {
      final occurrence = shifts[index];
      final docRef = refs[index];
      final exists = existingSnapshots[index].exists;
      batch.set(
          docRef,
          {
            ...occurrence.copyWith(id: docRef.id).toFirestoreMap(),
            if (!exists) 'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    await retryTransient(batch.commit, baseDelay: _retryBaseDelay);
  }

  Future<void> deleteShift({
    required String orgId,
    required String shiftId,
  }) {
    return _shiftCollection(orgId).doc(shiftId).delete();
  }

  /// Trägt den zugewiesenen Mitarbeiter aus einer Schicht aus (Schicht wird
  /// „frei"/unbesetzt) – z.B. bei einer Krankmeldung. Minimaler Merge-Write
  /// (nur `userId`/`employeeName` leeren, Status auf `planned`), damit ihn die
  /// Self-Austragen-Regel (resource.userId == auth.uid → '') zulässt.
  Future<void> releaseShiftAssignment({
    required String orgId,
    required String shiftId,
  }) {
    return _shiftCollection(orgId).doc(shiftId).set({
      'userId': '',
      'employeeName': '',
      'status': ShiftStatus.planned.value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteShiftSeries({
    required String orgId,
    required String seriesId,
  }) async {
    final snapshot = await _shiftCollection(orgId)
        .where('seriesId', isEqualTo: seriesId)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> updateShiftStatus({
    required String orgId,
    required String shiftId,
    required ShiftStatus status,
  }) {
    return _shiftCollection(orgId).doc(shiftId).update({
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Shift>> getShiftsInRange({
    required String orgId,
    required DateTime start,
    required DateTime end,
    String? userId,
  }) async {
    Query<Map<String, dynamic>> query = _shiftCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    query = query
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime');

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => Shift.fromFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<Shift?> getShiftById({
    required String orgId,
    required String shiftId,
  }) async {
    final snapshot = await _shiftCollection(orgId).doc(shiftId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }
    return Shift.fromFirestore(snapshot.id, data);
  }

  Future<List<AbsenceRequest>> getApprovedAbsencesInRange({
    required String orgId,
    required DateTime start,
    required DateTime end,
    String? userId,
  }) async {
    Query<Map<String, dynamic>> query = _absenceCollection(orgId);

    if (userId != null && userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }

    query = query
        .where(
          'startDate',
          isLessThanOrEqualTo: Timestamp.fromDate(end),
        )
        .orderBy('startDate');

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
        .where(
          (request) =>
              request.status == AbsenceStatus.approved &&
              request.overlaps(start, end),
        )
        .toList(growable: false);
  }

  Future<List<Shift>> findConflictingShifts(Shift shift) async {
    final queryWindow = _shiftConflictWindow(shift);
    final candidates = await getShiftsInRange(
      orgId: shift.orgId,
      start: queryWindow.start,
      end: queryWindow.end,
      userId: shift.userId,
    );

    return candidates
        .where((candidate) =>
            candidate.id != shift.id && candidate.overlaps(shift))
        .toList(growable: false);
  }

  Future<List<AbsenceRequest>> findBlockingAbsences(Shift shift) async {
    final snapshot = await _absenceCollection(shift.orgId)
        .where('userId', isEqualTo: shift.userId)
        .where(
          'startDate',
          isLessThanOrEqualTo: Timestamp.fromDate(shift.endTime),
        )
        .orderBy('startDate')
        .get();

    return snapshot.docs
        .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
        .where(
          (absence) =>
              absence.userId == shift.userId &&
              absence.status == AbsenceStatus.approved &&
              absence.overlaps(shift.startTime, shift.endTime),
        )
        .toList(growable: false);
  }

  Future<void> saveAbsenceRequest(AbsenceRequest request) async {
    final collection = _absenceCollection(request.orgId);
    final docRef =
        request.id == null ? collection.doc() : collection.doc(request.id);
    await docRef.set({
      ...request.copyWith(id: docRef.id).toFirestoreMap(),
      if (request.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteAbsenceRequest({
    required String orgId,
    required String requestId,
  }) {
    return _absenceCollection(orgId).doc(requestId).delete();
  }

  Future<void> reviewAbsenceRequest({
    required String orgId,
    required String requestId,
    required AbsenceStatus status,
    required String reviewerUid,
  }) {
    return _absenceCollection(orgId).doc(requestId).set({
      'status': status.value,
      'reviewedByUid': reviewerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --- Schichttausch (Tauschanfragen) ---

  static int _compareSwapRequests(ShiftSwapRequest a, ShiftSwapRequest b) {
    final aWhen = a.updatedAt ?? a.createdAt ?? a.requesterShiftStart;
    final bWhen = b.updatedAt ?? b.createdAt ?? b.requesterShiftStart;
    return bWhen.compareTo(aWhen);
  }

  /// Alle Tauschanfragen der Org (für Manager – Rules erlauben org-weit).
  Stream<List<ShiftSwapRequest>> watchAllSwapRequests({required String orgId}) {
    return _swapRequestCollection(orgId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => ShiftSwapRequest.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort(_compareSwapRequests);
      return List<ShiftSwapRequest>.unmodifiable(items);
    });
  }

  /// Eingehende Anfragen für einen Mitarbeiter (er ist Zielmitarbeiter).
  Stream<List<ShiftSwapRequest>> watchIncomingSwapRequests({
    required String orgId,
    required String targetUid,
  }) {
    return _swapRequestCollection(orgId)
        .where('targetUid', isEqualTo: targetUid)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => ShiftSwapRequest.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort(_compareSwapRequests);
      return List<ShiftSwapRequest>.unmodifiable(items);
    });
  }

  /// Ausgehende Anfragen eines Mitarbeiters (er ist Antragsteller).
  Stream<List<ShiftSwapRequest>> watchOutgoingSwapRequests({
    required String orgId,
    required String requesterUid,
  }) {
    return _swapRequestCollection(orgId)
        .where('requesterUid', isEqualTo: requesterUid)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => ShiftSwapRequest.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort(_compareSwapRequests);
      return List<ShiftSwapRequest>.unmodifiable(items);
    });
  }

  Future<void> saveSwapRequest(ShiftSwapRequest request) async {
    final collection = _swapRequestCollection(request.orgId);
    final docRef =
        request.id == null ? collection.doc() : collection.doc(request.id);
    await docRef.set({
      ...request.copyWith(id: docRef.id).toFirestoreMap(),
      if (request.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateSwapRequestStatus({
    required String orgId,
    required String requestId,
    required SwapStatus status,
    String? reviewerUid,
    bool? overriddenCompliance,
  }) {
    return _swapRequestCollection(orgId).doc(requestId).set({
      'status': status.value,
      if (reviewerUid != null) 'reviewedByUid': reviewerUid,
      if (overriddenCompliance != null)
        'overriddenCompliance': overriddenCompliance,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --- Schicht-Gutschriften (einseitiger Tausch) ---

  static int _compareSwapCredits(SwapCredit a, SwapCredit b) {
    return b.originShiftStart.compareTo(a.originShiftStart);
  }

  Stream<List<SwapCredit>> watchAllSwapCredits({required String orgId}) {
    return _swapCreditCollection(orgId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => SwapCredit.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort(_compareSwapCredits);
      return List<SwapCredit>.unmodifiable(items);
    });
  }

  Stream<List<SwapCredit>> watchSwapCredits({
    required String orgId,
    required String uid,
    required bool asCreditor,
  }) {
    return _swapCreditCollection(orgId)
        .where(asCreditor ? 'creditorUid' : 'debtorUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => SwapCredit.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort(_compareSwapCredits);
      return List<SwapCredit>.unmodifiable(items);
    });
  }

  Future<void> saveSwapCredit(SwapCredit credit) async {
    final collection = _swapCreditCollection(credit.orgId);
    final docRef =
        credit.id == null ? collection.doc() : collection.doc(credit.id);
    await docRef.set({
      ...credit.copyWith(id: docRef.id).toFirestoreMap(),
      if (credit.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<AbsenceRequest>> getApprovedVacationsForYear({
    required String orgId,
    required String userId,
    required int year,
  }) async {
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);

    final snapshot = await _absenceCollection(orgId)
        .where('userId', isEqualTo: userId)
        .where('startDate', isLessThan: Timestamp.fromDate(yearEnd))
        .orderBy('startDate')
        .get();

    return snapshot.docs
        .map((doc) => AbsenceRequest.fromFirestore(doc.id, doc.data()))
        .where(
          (request) =>
              request.type == AbsenceType.vacation &&
              request.status == AbsenceStatus.approved &&
              request.overlaps(yearStart, yearEnd),
        )
        .toList(growable: false);
  }

  /// Stösst den OktoPOS-Kassenabgleich für einen Standort an (read-only Pull der
  /// Verkaufsbuchungen → Bestandsabbuchung). Reiner Callable-Pfad: der API-Key
  /// liegt serverseitig im Secret Manager und verlässt nie den Client; der
  /// HTTP-Call gegen OktoPOS passiert in der Cloud Function (Server-zu-Server).
  /// Kein Hybrid-/Direkt-Fallback (es gibt keinen Client-seitigen Ersatzpfad) —
  /// Fehler propagieren als [FirebaseFunctionsException]. Gibt die
  /// Ergebnis-Zusammenfassung der Function zurück.
  Future<Map<String, dynamic>> syncOktoposTransactions({
    required String orgId,
    required String siteId,
    String? from,
    String? until,
    bool dryRun = false,
  }) async {
    final raw = await _callCloudFunction(
      'syncOktoposTransactions',
      {
        'orgId': orgId,
        'siteId': siteId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (until != null && until.isNotEmpty) 'until': until,
        if (dryRun) 'dryRun': true,
      },
      // Der Kassen-Pull kann über mehrere Seiten laufen; ein zu kurzes
      // Client-Timeout würde einen serverseitig erfolgreichen Abgleich
      // fälschlich als Fehler anzeigen. Server-Timeout = 300s.
      timeout: const Duration(seconds: 120),
    );
    return _callableResultData(raw);
  }

  /// Schreibt Artikel/Preise in die OktoPOS-Kasse (M5, Richtung WorkTime→Kasse).
  /// [productIds] leer/null ⇒ alle aktiven Artikel des Standorts. Reiner
  /// Callable-Pfad (Key serverseitig). Gibt die Ergebnis-Zusammenfassung
  /// (created/updated/failed/skipped + results[]) zurück.
  Future<Map<String, dynamic>> pushOktoposArticles({
    required String orgId,
    required String siteId,
    List<String>? productIds,
    bool dryRun = false,
  }) async {
    final raw = await _callCloudFunction(
      'pushOktoposArticles',
      {
        'orgId': orgId,
        'siteId': siteId,
        if (productIds != null && productIds.isNotEmpty) 'productIds': productIds,
        if (dryRun) 'dryRun': true,
      },
      timeout: const Duration(seconds: 120),
    );
    return _callableResultData(raw);
  }

  /// Schreibt Kunden-Kontakte (Typ Kunde) als OktoPOS-Customer in die Kasse
  /// (M6a). [contactIds] leer/null ⇒ alle aktiven Kunden-Kontakte. Idempotent
  /// serverseitig (vorhandene Kunden werden übersprungen). Gibt
  /// `{created, skipped, failed, total, results}` zurück.
  Future<Map<String, dynamic>> pushOktoposCustomers({
    required String orgId,
    required String siteId,
    List<String>? contactIds,
    bool dryRun = false,
  }) async {
    final raw = await _callCloudFunction(
      'pushOktoposCustomers',
      {
        'orgId': orgId,
        'siteId': siteId,
        if (contactIds != null && contactIds.isNotEmpty) 'contactIds': contactIds,
        if (dryRun) 'dryRun': true,
      },
      timeout: const Duration(seconds: 120),
    );
    return _callableResultData(raw);
  }

  /// Holt die Referenz-Tokens (Einheiten + Vertriebskanäle) aus der Kasse, damit
  /// die Einstellungs-UI gültige Werte anbieten kann. Gibt
  /// `{units: [...], distributionChannels: [...]}` zurück.
  Future<Map<String, dynamic>> getOktoposLookups({
    required String orgId,
    required String siteId,
  }) async {
    final raw = await _callCloudFunction('getOktoposLookups', {
      'orgId': orgId,
      'siteId': siteId,
    });
    return _callableResultData(raw);
  }

  /// Normalisiert das Ergebnis von [_callCloudFunction]: der echte Pfad liefert
  /// ein [HttpsCallableResult] (Nutzdaten unter `.data`), der Test-Invoker gibt
  /// die Map direkt zurück. Beide Formen auf eine `Map<String, dynamic>` bringen.
  Map<String, dynamic> _callableResultData(dynamic raw) {
    final data = raw is HttpsCallableResult ? raw.data : raw;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  /// Version des Callable-Payload-Vertrags (no-api-contract-versioning). Der
  /// Server kann über eine Mindestversion ein Force-Update erzwingen, ohne dass
  /// ein Feld-Rename alte Clients still falsch validieren lässt.
  static const int clientApiVersion = 1;

  Future<dynamic> _callCloudFunction(
    String name,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    // Jeden Callable-Payload zentral anreichern:
    //  - apiVersion: Vertragsversion (no-api-contract-versioning)
    //  - _request_id: Korrelations-/Trace-ID Client->Server (no-distributed-tracing),
    //    die der Server mitloggt, damit Client- und Server-Fehler verknüpfbar sind.
    final enriched = <String, dynamic>{
      ...payload,
      'apiVersion': clientApiVersion,
      '_request_id': _uuid.v4(),
    };
    final invoker = _cloudFunctionInvoker;
    if (invoker != null) {
      return invoker(name, enriched);
    }
    // Timeout, damit ein hängender Aufruf bei schlechter Verbindung nicht
    // unbegrenzt blockiert; bei Überschreitung greift der Hybrid-Fallback.
    return _firebaseFunctions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: timeout),
        )
        .call(enriched);
  }

  Future<bool> _callCloudFunctionIfAvailable(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      // Callables sind durch stabile Client-IDs idempotent -> transiente
      // Fehler (unavailable/deadline-exceeded) duerfen mit Backoff wiederholt
      // werden, bevor der Hybrid-/Cloud-Fallback greift (no-retry-backoff-idempotent).
      await retryTransient(
        () => _callCloudFunction(name, payload),
        baseDelay: _retryBaseDelay,
        onRetry: (error, attempt) => AppLogger.warning(
          'Callable $name transienter Fehler – Retry $attempt',
          error: error,
        ),
      );
      return true;
    } on FirebaseFunctionsException catch (error) {
      // Fallback-faehige (transiente/Infrastruktur-)Codes: hier soll der
      // direkte/Hybrid-Pfad greifen statt hart zu scheitern. deadline-exceeded
      // tritt beim 30s-Callable-Timeout auf schlechter Verbindung auf; da der
      // direkte Pfad dieselbe stabile Doc-ID schreibt (siehe saveWorkEntry/
      // saveShiftBatch), bleibt der Fallback duplikatfrei (probleme #3/#9).
      const fallbackCodes = {
        'not-found',
        'unavailable',
        'deadline-exceeded',
        'internal',
        'cancelled',
      };
      if (fallbackCodes.contains(error.code)) {
        return false;
      }
      // Blockierende Compliance-Ablehnung: strukturierte Verstöße bewahren,
      // statt nur die Sammelnachricht (Plan-Gap blocking-violations-discarded).
      if (error.code == 'failed-precondition') {
        final message = error.message?.trim();
        throw ComplianceRejectedException(
          (message == null || message.isEmpty)
              ? 'Die Aktion verstößt gegen Arbeitszeitregeln.'
              : message,
          ComplianceRejectedException.parseDetails(error.details),
        );
      }
      if (error.message?.trim().isNotEmpty == true) {
        throw StateError(error.message!.trim());
      }
      rethrow;
    }
  }

  Future<void> updateShiftSwapRequest({
    required String orgId,
    required String shiftId,
    required String requestedByUid,
  }) {
    return _shiftCollection(orgId).doc(shiftId).set({
      'swapRequestedByUid': requestedByUid,
      'swapStatus': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> reviewShiftSwap({
    required String orgId,
    required String shiftId,
    required bool approved,
  }) {
    return _shiftCollection(orgId).doc(shiftId).set({
      'swapStatus': approved ? 'approved' : 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> migrateLegacyDataIfNeeded({
    required String orgId,
    required String userId,
    required UserSettings currentSettings,
  }) async {
    final localFlag = await DatabaseService.getLocalSetting(
      'legacy_migrated_$userId',
    );
    if (localFlag == 'true') {
      return;
    }

    final hasLegacyData = await DatabaseService.hasLegacyData();
    if (!hasLegacyData) {
      await DatabaseService.saveLocalSetting('legacy_migrated_$userId', 'true');
      return;
    }

    final userDoc = await _users.doc(userId).get();
    if ((userDoc.data()?['legacyMigratedAt']) != null) {
      await DatabaseService.saveLocalSetting('legacy_migrated_$userId', 'true');
      await DatabaseService.clearLegacyWorkData();
      return;
    }

    final legacyEntries = await DatabaseService.loadLegacyEntries();
    final legacyTemplates = await DatabaseService.loadLegacyTemplates();
    final legacySettings = await DatabaseService.loadLegacyUserSettings();
    final mergedSettings = _mergeSettings(
      currentSettings: currentSettings,
      legacySettings: legacySettings,
    );

    final batch = _firestore.batch();

    for (final entry in legacyEntries) {
      final docId =
          entry.id == null ? 'legacy-${_uuid.v4()}' : 'legacy-${entry.id}';
      batch.set(
        _entryCollection(orgId).doc(docId),
        {
          ...entry
              .copyWith(
                id: docId,
                orgId: orgId,
                userId: userId,
              )
              .toFirestoreMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'legacyImported': true,
        },
        SetOptions(merge: true),
      );
    }

    for (final template in legacyTemplates) {
      final docId = template.id == null
          ? 'legacy-${_uuid.v4()}'
          : 'legacy-${template.id}';
      batch.set(
        _templateCollection(orgId).doc(docId),
        {
          ...template
              .copyWith(
                id: docId,
                orgId: orgId,
                userId: userId,
              )
              .toFirestoreMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'legacyImported': true,
        },
        SetOptions(merge: true),
      );
    }

    batch.set(
        _users.doc(userId),
        {
          'settings': mergedSettings.toFirestoreMap(),
          'legacyMigratedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
    await DatabaseService.clearLegacyWorkData();
    await DatabaseService.saveLocalSetting('legacy_migrated_$userId', 'true');
  }

  Future<void> _ensureOrganization(String orgId) {
    return _organizationDoc(orgId).set({
      'name': AppConfig.defaultOrganizationName,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _ensureOrganizationIfAdmin(AppUserProfile profile) async {
    if (!profile.isAdmin) {
      return;
    }

    try {
      await _ensureOrganization(profile.orgId);
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
    }
  }

  List<Shift> buildShiftOccurrences(
    Shift shift, {
    required RecurrencePattern recurrencePattern,
    DateTime? recurrenceEndDate,
  }) {
    if (shift.id != null || recurrencePattern == RecurrencePattern.none) {
      return [
        shift.copyWith(
          recurrencePattern: recurrencePattern,
        ),
      ];
    }

    final until = recurrenceEndDate == null
        ? shift.startTime
        : DateTime(
            recurrenceEndDate.year,
            recurrenceEndDate.month,
            recurrenceEndDate.day,
            shift.startTime.hour,
            shift.startTime.minute,
          );
    final seriesId = shift.seriesId ?? _uuid.v4();
    final occurrences = <Shift>[];
    var cursorStart = shift.startTime;
    var cursorEnd = shift.endTime;
    while (!cursorStart.isAfter(until)) {
      occurrences.add(
        shift.copyWith(
          startTime: cursorStart,
          endTime: cursorEnd,
          seriesId: seriesId,
          recurrencePattern: recurrencePattern,
        ),
      );

      switch (recurrencePattern) {
        case RecurrencePattern.weekly:
          cursorStart = cursorStart.add(const Duration(days: 7));
          cursorEnd = cursorEnd.add(const Duration(days: 7));
        case RecurrencePattern.biWeekly:
          cursorStart = cursorStart.add(const Duration(days: 14));
          cursorEnd = cursorEnd.add(const Duration(days: 14));
        case RecurrencePattern.monthly:
          cursorStart = DateTime(
            cursorStart.year,
            cursorStart.month + 1,
            cursorStart.day,
            cursorStart.hour,
            cursorStart.minute,
          );
          cursorEnd = DateTime(
            cursorEnd.year,
            cursorEnd.month + 1,
            cursorEnd.day,
            cursorEnd.hour,
            cursorEnd.minute,
          );
        case RecurrencePattern.none:
          break;
      }
    }

    return occurrences;
  }

  UserSettings _mergeSettings({
    required UserSettings currentSettings,
    required UserSettings legacySettings,
  }) {
    final hasCustomRate = currentSettings.hourlyRate > 0;
    final hasCustomHours = currentSettings.dailyHours != 8.0;
    final hasCustomCurrency = currentSettings.currency != 'EUR';
    final hasCustomName = currentSettings.name.trim().isNotEmpty;

    return currentSettings.copyWith(
      name: hasCustomName ? currentSettings.name : legacySettings.name,
      hourlyRate: hasCustomRate
          ? currentSettings.hourlyRate
          : legacySettings.hourlyRate,
      dailyHours: hasCustomHours
          ? currentSettings.dailyHours
          : legacySettings.dailyHours,
      currency: hasCustomCurrency
          ? currentSettings.currency
          : legacySettings.currency,
    );
  }

  ({DateTime start, DateTime end}) _monthRange(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return (start: start, end: end);
  }

  String? findShiftConflictMessage({
    required Shift shift,
    required List<Shift> conflictingShifts,
    required List<AbsenceRequest> blockingAbsences,
  }) {
    final conflicting = conflictingShifts.firstWhereOrNull((_) => true);
    if (conflicting != null) {
      final locationLabel =
          conflicting.effectiveSiteLabel?.trim().isNotEmpty == true
              ? ' am Standort ${conflicting.effectiveSiteLabel}'
              : '';
      return 'Konflikt mit bestehender Schicht von '
          '${conflicting.employeeName}$locationLabel.';
    }
    final blocking = blockingAbsences.firstWhereOrNull((_) => true);
    if (blocking != null) {
      return 'Konflikt mit ${blocking.type.label} von ${blocking.employeeName}.';
    }
    return null;
  }

  ({DateTime start, DateTime end}) _shiftConflictWindow(Shift shift) {
    final start = DateTime(
      shift.startTime.year,
      shift.startTime.month,
      shift.startTime.day,
    ).subtract(const Duration(days: 1));
    final end = DateTime(
      shift.endTime.year,
      shift.endTime.month,
      shift.endTime.day + 1,
    );
    return (start: start, end: end);
  }

  String _inviteDocId(String email) =>
      email.trim().toLowerCase().replaceAll('/', '_');

  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return false;
  }
}
