import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/qualification_definition.dart';
import '../models/shift.dart';
import '../models/shift_template.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../models/user_settings.dart';
import '../models/work_entry.dart';
import '../models/work_template.dart';
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
  })  : _providedFirestore = firestore,
        _functions = functions,
        _cloudFunctionInvoker = cloudFunctionInvoker,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore? _providedFirestore;
  final Uuid _uuid;
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

  CollectionReference<Map<String, dynamic>> _entryCollection(String orgId) =>
      _organizationDoc(orgId).collection('workEntries');

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

  CollectionReference<Map<String, dynamic>> _ruleSetCollection(String orgId) =>
      _organizationDoc(orgId).collection('ruleSets');

  CollectionReference<Map<String, dynamic>> _travelTimeRuleCollection(
    String orgId,
  ) =>
      _organizationDoc(orgId).collection('travelTimeRules');

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
      return [...requests]..sort((a, b) {
          final byStart = a.startDate.compareTo(b.startDate);
          if (byStart != 0) {
            return byStart;
          }
          final aUpdated = a.updatedAt ?? a.createdAt ?? a.startDate;
          final bUpdated = b.updatedAt ?? b.createdAt ?? b.startDate;
          return bUpdated.compareTo(aUpdated);
        });
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
    return [...requests]..sort((a, b) {
        final byStart = a.startDate.compareTo(b.startDate);
        if (byStart != 0) {
          return byStart;
        }
        final aUpdated = a.updatedAt ?? a.createdAt ?? a.startDate;
        final bUpdated = b.updatedAt ?? b.createdAt ?? b.startDate;
        return bUpdated.compareTo(aUpdated);
      });
  }

  Future<void> saveWorkEntry(WorkEntry entry) async {
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertWorkEntry',
        {
          'entry': entry.toMap(),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveWorkEntryDirect(entry);
  }

  Future<void> saveWorkEntryBatch(List<WorkEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertWorkEntryBatch',
        {
          'orgId': entries.first.orgId,
          'entries':
              entries.map((entry) => entry.toMap()).toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveWorkEntryBatchDirect(entries);
  }

  Future<void> _saveWorkEntryDirect(WorkEntry entry) async {
    final collection = _entryCollection(entry.orgId);
    final docRef =
        entry.id == null ? collection.doc() : collection.doc(entry.id);
    await docRef.set({
      ...entry.copyWith(id: docRef.id).toFirestoreMap(),
      if (entry.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveWorkEntryBatchDirect(List<WorkEntry> entries) async {
    final collection = _entryCollection(entries.first.orgId);
    final batch = _firestore.batch();
    for (final entry in entries) {
      final docRef =
          entry.id == null ? collection.doc() : collection.doc(entry.id);
      // Neue Docs (id == null) erhalten createdAt. Bei bestehenden Docs
      // wird createdAt durch merge: true nicht ueberschrieben, sofern es
      // bereits existiert — kein separater Existenz-Check noetig.
      batch.set(
        docRef,
        {
          ...entry.copyWith(id: docRef.id).toFirestoreMap(),
          if (entry.id == null) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
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

  Future<void> saveTeam(TeamDefinition team) async {
    final collection = _teamCollection(team.orgId);
    final docRef = team.id == null ? collection.doc() : collection.doc(team.id);
    await docRef.set({
      ...team.copyWith(id: docRef.id).toFirestoreMap(),
      if (team.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteTeam({
    required String orgId,
    required String teamId,
  }) {
    return _teamCollection(orgId).doc(teamId).delete();
  }

  Future<void> saveSite(SiteDefinition site) async {
    final collection = _siteCollection(site.orgId);
    final docRef = site.id == null ? collection.doc() : collection.doc(site.id);
    await docRef.set({
      ...site.copyWith(id: docRef.id).toFirestoreMap(),
      if (site.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteSite({
    required String orgId,
    required String siteId,
  }) {
    return _siteCollection(orgId).doc(siteId).delete();
  }

  Future<void> saveQualification(QualificationDefinition qualification) async {
    final collection = _qualificationCollection(qualification.orgId);
    final docRef = qualification.id == null
        ? collection.doc()
        : collection.doc(qualification.id);
    await docRef.set({
      ...qualification.copyWith(id: docRef.id).toFirestoreMap(),
      if (qualification.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteQualification({
    required String orgId,
    required String qualificationId,
  }) {
    return _qualificationCollection(orgId).doc(qualificationId).delete();
  }

  Future<void> saveEmploymentContract(EmploymentContract contract) async {
    final collection = _employmentContractCollection(contract.orgId);
    final docRef =
        contract.id == null ? collection.doc() : collection.doc(contract.id);
    await docRef.set({
      ...contract.copyWith(id: docRef.id).toFirestoreMap(),
      if (contract.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteEmploymentContract({
    required String orgId,
    required String contractId,
  }) {
    return _employmentContractCollection(orgId).doc(contractId).delete();
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

  Future<void> saveRuleSet(ComplianceRuleSet ruleSet) async {
    final collection = _ruleSetCollection(ruleSet.orgId);
    final docRef =
        ruleSet.id == null ? collection.doc() : collection.doc(ruleSet.id);
    await docRef.set({
      ...ruleSet.copyWith(id: docRef.id).toFirestoreMap(),
      if (ruleSet.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteRuleSet({
    required String orgId,
    required String ruleSetId,
  }) {
    return _ruleSetCollection(orgId).doc(ruleSetId).delete();
  }

  Future<void> saveTravelTimeRule(TravelTimeRule rule) async {
    final collection = _travelTimeRuleCollection(rule.orgId);
    final docRef = rule.id == null ? collection.doc() : collection.doc(rule.id);
    await docRef.set({
      ...rule.copyWith(id: docRef.id).toFirestoreMap(),
      if (rule.id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteTravelTimeRule({
    required String orgId,
    required String ruleId,
  }) {
    return _travelTimeRuleCollection(orgId).doc(ruleId).delete();
  }

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
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'upsertShiftBatch',
        {
          'orgId': shifts.first.orgId,
          'shifts':
              shifts.map((shift) => shift.toMap()).toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveShiftBatchDirect(shifts);
  }

  Future<void> publishShiftBatch({
    required String orgId,
    required List<Shift> shifts,
    required ShiftStatus status,
  }) async {
    if (shifts.isEmpty) {
      return;
    }
    if (!AppConfig.disableAuthentication) {
      final handledByFunction = await _callCloudFunctionIfAvailable(
        'publishShiftBatch',
        {
          'orgId': orgId,
          'status': status.value,
          'shifts':
              shifts.map((shift) => shift.toMap()).toList(growable: false),
        },
      );
      if (handledByFunction) {
        return;
      }
    }
    await _saveShiftBatchDirect(
      shifts
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
    await batch.commit();
  }

  Future<void> deleteShift({
    required String orgId,
    required String shiftId,
  }) {
    return _shiftCollection(orgId).doc(shiftId).delete();
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

  Future<dynamic> _callCloudFunction(
    String name,
    Map<String, dynamic> payload,
  ) {
    if (_cloudFunctionInvoker != null) {
      return _cloudFunctionInvoker!(name, payload);
    }
    return _firebaseFunctions.httpsCallable(name).call(payload);
  }

  Future<bool> _callCloudFunctionIfAvailable(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _callCloudFunction(name, payload);
      return true;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'unavailable') {
        return false;
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
