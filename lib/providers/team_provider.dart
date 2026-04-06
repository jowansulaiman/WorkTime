import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/local_demo_data.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/qualification_definition.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';

class TeamProvider extends ChangeNotifier {
  TeamProvider({
    required FirestoreService firestoreService,
    bool? disableAuthentication,
  })  : _firestoreService = firestoreService,
        _forceLocalStorage =
            disableAuthentication ?? AppConfig.disableAuthentication;

  final FirestoreService _firestoreService;
  final bool _forceLocalStorage;
  bool _localStorageOnly = false;
  bool _hybridStorageEnabled = false;

  StreamSubscription<List<AppUserProfile>>? _membersSubscription;
  StreamSubscription<List<UserInvite>>? _invitesSubscription;
  StreamSubscription<List<TeamDefinition>>? _teamsSubscription;
  StreamSubscription<List<SiteDefinition>>? _sitesSubscription;
  StreamSubscription<List<QualificationDefinition>>?
      _qualificationsSubscription;
  StreamSubscription<List<EmploymentContract>>? _contractsSubscription;
  StreamSubscription<List<EmployeeSiteAssignment>>?
      _siteAssignmentsSubscription;
  StreamSubscription<List<ComplianceRuleSet>>? _ruleSetsSubscription;
  StreamSubscription<List<TravelTimeRule>>? _travelTimeRulesSubscription;

  AppUserProfile? _currentUser;
  List<AppUserProfile> _members = [];
  List<UserInvite> _invites = [];
  List<TeamDefinition> _teams = [];
  List<SiteDefinition> _sites = [];
  List<QualificationDefinition> _qualifications = [];
  List<EmploymentContract> _contracts = [];
  List<EmployeeSiteAssignment> _siteAssignments = [];
  List<ComplianceRuleSet> _ruleSets = [];
  List<TravelTimeRule> _travelTimeRules = [];
  List<AppUserProfile> _localMembers = [];
  List<UserInvite> _localInvites = [];
  List<TeamDefinition> _localTeams = [];
  List<SiteDefinition> _localSites = [];
  List<QualificationDefinition> _localQualifications = [];
  List<EmploymentContract> _localContracts = [];
  List<EmployeeSiteAssignment> _localSiteAssignments = [];
  List<ComplianceRuleSet> _localRuleSets = [];
  List<TravelTimeRule> _localTravelTimeRules = [];
  bool _loading = false;
  bool _disposed = false;

  List<AppUserProfile> get members => _members;
  List<UserInvite> get invites => _invites;
  List<TeamDefinition> get teams => _teams;
  List<SiteDefinition> get sites => _sites;
  List<QualificationDefinition> get qualifications => _qualifications;
  List<EmploymentContract> get contracts =>
      _effectiveContracts(_contracts, _members);
  List<EmployeeSiteAssignment> get siteAssignments => _siteAssignments;
  List<ComplianceRuleSet> get ruleSets => _effectiveRuleSets(_ruleSets);
  List<TravelTimeRule> get travelTimeRules => _travelTimeRules;
  bool get loading => _loading;
  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  String? _lastSessionKey;

  LocalStorageScope? get _localScope {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    return LocalStorageScope.fromUser(currentUser);
  }

  Future<void> updateSession(
    AppUserProfile? user, {
    bool localStorageOnly = false,
    bool hybridStorageEnabled = false,
  }) async {
    final previousStorageModeKey = _storageModeKey;
    _localStorageOnly = localStorageOnly;
    _hybridStorageEnabled = hybridStorageEnabled;
    final storageModeChanged = previousStorageModeKey != _storageModeKey;
    final sessionKey =
        user == null ? null : '${user.uid}:${user.orgId}:$_storageModeKey';
    if (sessionKey == _lastSessionKey && user != null) {
      if (!usesLocalStorage || _currentUser?.uid != user.uid) {
        _currentUser = user;
      }
      return;
    }
    _lastSessionKey = sessionKey;

    final changed =
        user?.uid != _currentUser?.uid || user?.orgId != _currentUser?.orgId;
    _currentUser = user;

    if (user == null) {
      _members = [];
      _invites = [];
      _teams = [];
      _sites = [];
      _qualifications = [];
      _contracts = [];
      _siteAssignments = [];
      _ruleSets = [];
      _travelTimeRules = [];
      _localMembers = [];
      _localInvites = [];
      _localTeams = [];
      _localSites = [];
      _localQualifications = [];
      _localContracts = [];
      _localSiteAssignments = [];
      _localRuleSets = [];
      _localTravelTimeRules = [];
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();
      notifyListeners();
      return;
    }

    if (usesHybridStorage && changed) {
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();
      _membersSubscription = null;
      _invitesSubscription = null;
      _teamsSubscription = null;
      _sitesSubscription = null;
      _qualificationsSubscription = null;
      _contractsSubscription = null;
      _siteAssignmentsSubscription = null;
      _ruleSetsSubscription = null;
      _travelTimeRulesSubscription = null;
    }

    if (usesLocalStorage) {
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();
      if (changed ||
          (_localMembers.isEmpty &&
              _localInvites.isEmpty &&
              _localTeams.isEmpty &&
              _localSites.isEmpty &&
              _localQualifications.isEmpty &&
              _localContracts.isEmpty &&
              _localSiteAssignments.isEmpty &&
              _localRuleSets.isEmpty &&
              _localTravelTimeRules.isEmpty)) {
        await _loadLocalState();
      } else {
        _applyLocalState();
        notifyListeners();
      }
      return;
    }

    // Im Hybrid-Modus kein manuelles Laden aus SharedPreferences noetig:
    // Firestore Offline-Persistence stellt Stammdaten automatisch bereit,
    // die Stream-Listener unten uebernehmen die Aktualisierung.

    if (!user.canManageShifts) {
      _members = [user];
      _invites = [];
      _teams = [];
    }

    if (changed || storageModeChanged) {
      _loading = true;
      _safeNotify();
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();

      // ---------------------------------------------------------------
      // Hybrid-Strategie: Alle Stammdaten in diesem Provider sind
      // *strukturelle* Daten (Teams, Sites, Qualifikationen, etc.).
      // Im Hybrid-Modus werden diese NUR in der Cloud gehalten —
      // Firestore Offline-Persistence cached sie automatisch lokal.
      // Manuelles SharedPreferences-Caching entfaellt, wodurch
      // Schreibvorgaenge drastisch reduziert werden und der
      // Firebase-Spark-Freitarif eingehalten wird.
      //
      // Das manuelle Caching in _local*-Listen bleibt nur fuer den
      // reinen Local-Modus erhalten (kein Firebase verfuegbar).
      // ---------------------------------------------------------------

      if (user.canManageShifts) {
        _membersSubscription = _firestoreService
            .watchOrganizationUsers(user.orgId)
            .listen((items) {
          _members = items;
          _loading = false;
          _safeNotify();
        }, onError: (Object error) {
          debugPrint('TeamProvider: Fehler beim Laden der Mitglieder: $error');
          _loading = false;
          _safeNotify();
        });

        if (user.isAdmin) {
          _invitesSubscription =
              _firestoreService.watchInvites(user.orgId).listen((items) {
            _invites = items;
            _safeNotify();
          }, onError: (Object error) {
            debugPrint(
                'TeamProvider: Fehler beim Laden der Einladungen: $error');
          });
        } else {
          _invites = [];
        }

        _teamsSubscription = _firestoreService.watchTeams(user.orgId).listen((
          items,
        ) {
          _teams = items;
          _safeNotify();
        }, onError: (Object error) {
          debugPrint('TeamProvider: Fehler beim Laden der Teams: $error');
        });
      } else {
        _members = [user];
        _invites = [];
        _teams = [];
      }

      _sitesSubscription = _firestoreService.watchSites(user.orgId).listen(
        (items) {
          _sites = items;
          _safeNotify();
        },
        onError: (Object error) {
          debugPrint('TeamProvider: Fehler beim Laden der Standorte: $error');
        },
      );

      _qualificationsSubscription =
          _firestoreService.watchQualifications(user.orgId).listen((items) {
        _qualifications = items;
        _safeNotify();
      }, onError: (Object error) {
        debugPrint(
            'TeamProvider: Fehler beim Laden der Qualifikationen: $error');
      });

      _contractsSubscription = _firestoreService
          .watchEmploymentContracts(user.orgId)
          .listen((items) {
        _contracts = items;
        _safeNotify();
      }, onError: (Object error) {
        debugPrint('TeamProvider: Fehler beim Laden der Vertraege: $error');
      });

      _siteAssignmentsSubscription =
          _firestoreService.watchSiteAssignments(user.orgId).listen((items) {
        _siteAssignments = items;
        _safeNotify();
      }, onError: (Object error) {
        debugPrint(
            'TeamProvider: Fehler beim Laden der Standortzuordnungen: $error');
      });

      _ruleSetsSubscription =
          _firestoreService.watchRuleSets(user.orgId).listen((items) async {
        _ruleSets = items;
        if (user.isAdmin && items.isEmpty) {
          await saveRuleSet(
            ComplianceRuleSet.defaultRetail(
              user.orgId,
              createdByUid: user.uid,
            ),
          );
          return;
        }
        _safeNotify();
      }, onError: (Object error) {
        debugPrint('TeamProvider: Fehler beim Laden der Regelwerke: $error');
      });

      _travelTimeRulesSubscription =
          _firestoreService.watchTravelTimeRules(user.orgId).listen((items) {
        _travelTimeRules = items;
        _safeNotify();
      }, onError: (Object error) {
        debugPrint(
            'TeamProvider: Fehler beim Laden der Fahrtzeitregeln: $error');
      });
    }
  }

  Future<void> saveInvite(UserInvite invite) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final preparedInvite = invite.copyWith(
      id: invite.id ?? _inviteIdForEmail(invite.email),
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );

    if (usesLocalStorage) {
      _upsertLocalInvite(preparedInvite);
      _upsertLocalMember(_memberFromInvite(preparedInvite));
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.createOrUpdateInvite(preparedInvite);
  }

  Future<void> deleteInvite(String inviteId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      final inviteIndex = _localInvites.indexWhere(
        (invite) => invite.id == inviteId,
      );
      if (inviteIndex == -1) {
        return;
      }
      final invite = _localInvites.removeAt(inviteIndex);
      final memberId = _localMemberIdForEmail(invite.email);
      _localMembers.removeWhere((member) => member.uid == memberId);
      _localTeams = _localTeams
          .map((team) => team.copyWith(
                memberIds: team.memberIds
                    .where((candidate) => candidate != memberId)
                    .toList(growable: false),
              ))
          .toList(growable: false);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteInvite(inviteId);
  }

  Future<void> saveTeam(TeamDefinition team) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final memberIds = team.memberIds.toSet().toList(growable: false);
    final preparedTeam = team.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
      memberIds: memberIds,
    );

    if (usesLocalStorage) {
      final localTeam = preparedTeam.copyWith(
        id: preparedTeam.id ?? _nextLocalId('team'),
      );
      final index = _localTeams.indexWhere((item) => item.id == localTeam.id);
      if (index == -1) {
        _localTeams.add(localTeam);
      } else {
        _localTeams[index] = localTeam;
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveTeam(preparedTeam);
  }

  Future<void> deleteTeam(String teamId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      _localTeams.removeWhere((team) => team.id == teamId);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteTeam(
      orgId: currentUser.orgId,
      teamId: teamId,
    );
  }

  Future<void> updateMember(AppUserProfile profile) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      if (profile.uid == currentUser.uid) {
        _currentUser = profile;
      } else {
        _upsertLocalMember(profile);
      }
      _syncInviteForMember(profile);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.upsertUserProfile(profile);
  }

  Future<void> saveMemberConfiguration({
    required AppUserProfile profile,
    required EmploymentContract contract,
    required List<EmployeeSiteAssignment> siteAssignments,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final preparedContract = contract.copyWith(
      orgId: currentUser.orgId,
      userId: profile.uid,
      createdByUid: currentUser.uid,
    );
    final preparedAssignments = siteAssignments
        .map((assignment) => assignment.copyWith(
              orgId: currentUser.orgId,
              userId: profile.uid,
              createdByUid: currentUser.uid,
            ))
        .toList(growable: false);

    if (usesLocalStorage) {
      _upsertLocalMember(profile);
      _localContracts.removeWhere(
        (item) => item.userId == profile.uid && item.id != preparedContract.id,
      );
      final contractIndex = _localContracts.indexWhere(
        (item) => item.id == preparedContract.id,
      );
      final localContract = preparedContract.copyWith(
        id: preparedContract.id ?? _nextLocalId('contract'),
      );
      if (contractIndex == -1) {
        _localContracts.add(localContract);
      } else {
        _localContracts[contractIndex] = localContract;
      }
      _localSiteAssignments.removeWhere((item) => item.userId == profile.uid);
      _localSiteAssignments.addAll(
        preparedAssignments.map(
          (assignment) => assignment.copyWith(
            id: assignment.id ?? _nextLocalId('site-assignment'),
          ),
        ),
      );
      _syncInviteForMember(profile);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.upsertUserProfile(profile);
    await _firestoreService.saveEmploymentContract(preparedContract);
    await _firestoreService.saveSiteAssignments(
      orgId: currentUser.orgId,
      userId: profile.uid,
      assignments: preparedAssignments,
    );
  }

  Future<void> saveMemberProtectionRules({
    required String userId,
    bool? isMinor,
    bool? isPregnant,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final memberMatches = members.where((member) => member.uid == userId);
    if (memberMatches.isEmpty) {
      return;
    }
    final member = memberMatches.first;
    final contractMatches =
        contracts.where((contract) => contract.userId == userId);
    final currentContract = contractMatches.isEmpty
        ? _defaultContractForMember(member)
        : contractMatches.first;
    final nextIsMinor = isMinor ?? currentContract.isMinor;
    final nextIsPregnant = isPregnant ?? currentContract.isPregnant;

    await saveMemberConfiguration(
      profile: member,
      contract: currentContract.copyWith(
        isMinor: nextIsMinor,
        isPregnant: nextIsPregnant,
        maxDailyMinutes: _protectionRuleDailyLimit(
          contract: currentContract,
          isMinor: nextIsMinor,
          isPregnant: nextIsPregnant,
        ),
      ),
      siteAssignments: siteAssignments
          .where((assignment) => assignment.userId == userId)
          .toList(growable: false),
    );
  }

  Future<void> saveMemberWorkRuleSettings({
    required String userId,
    required WorkRuleSettings settings,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final memberMatches = members.where((member) => member.uid == userId);
    if (memberMatches.isEmpty) {
      return;
    }

    await updateMember(
      memberMatches.first.copyWith(workRuleSettings: settings),
    );
  }

  Future<void> saveSite(SiteDefinition site) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final prepared = site.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
      countryCode: SiteDefinition.germanyCountryCode,
      federalState:
          SiteDefinition.normalizeGermanFederalState(site.federalState),
    );
    final validationError = _validateSiteDefinition(prepared);
    if (validationError != null) {
      throw StateError(validationError);
    }

    if (usesLocalStorage) {
      final localSite =
          prepared.copyWith(id: prepared.id ?? _nextLocalId('site'));
      final index = _localSites.indexWhere((item) => item.id == localSite.id);
      if (index == -1) {
        _localSites.add(localSite);
      } else {
        _localSites[index] = localSite;
      }
      _ensureLocalDemoData();
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveSite(prepared);
  }

  String? _validateSiteDefinition(SiteDefinition site) {
    if (site.name.trim().isEmpty) {
      return 'Bitte einen Standortnamen eingeben.';
    }
    final street = site.street?.trim() ?? '';
    if (street.isEmpty) {
      return 'Bitte eine Strasse mit Hausnummer eingeben.';
    }
    if (!RegExp(r'\d').hasMatch(street)) {
      return 'Bitte eine echte Adresse mit Hausnummer eingeben.';
    }
    final postalCode = site.postalCode?.trim() ?? '';
    if (!SiteDefinition.isValidGermanPostalCode(postalCode)) {
      return 'Bitte eine gueltige deutsche PLZ mit 5 Ziffern eingeben.';
    }
    if ((site.city?.trim().isEmpty ?? true)) {
      return 'Bitte einen Ort in Deutschland eingeben.';
    }
    if (SiteDefinition.normalizeGermanFederalState(site.federalState) == null) {
      return 'Bitte ein gueltiges deutsches Bundesland auswaehlen.';
    }
    if (site.countryCode.trim().toUpperCase() !=
        SiteDefinition.germanyCountryCode) {
      return 'Standorte koennen nur in Deutschland angelegt werden.';
    }
    final latitude = site.latitude;
    final longitude = site.longitude;
    if (latitude != null &&
        longitude != null &&
        !SiteDefinition.isWithinGermanyBounds(latitude, longitude)) {
      return 'Standorte muessen innerhalb Deutschlands liegen.';
    }
    return null;
  }

  Future<void> deleteSite(String siteId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      _localSites.removeWhere((item) => item.id == siteId);
      _localSiteAssignments.removeWhere((item) => item.siteId == siteId);
      _localTravelTimeRules.removeWhere(
        (item) => item.fromSiteId == siteId || item.toSiteId == siteId,
      );
      _ensureLocalDemoData();
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    final linkedTravelRules = _travelTimeRules
        .where((item) => item.fromSiteId == siteId || item.toSiteId == siteId)
        .toList(growable: false);
    for (final rule in linkedTravelRules) {
      if (rule.id == null) {
        continue;
      }
      await _firestoreService.deleteTravelTimeRule(
        orgId: currentUser.orgId,
        ruleId: rule.id!,
      );
    }

    await _firestoreService.deleteSite(
        orgId: currentUser.orgId, siteId: siteId);
  }

  Future<void> saveQualification(QualificationDefinition qualification) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final prepared = qualification.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );

    if (usesLocalStorage) {
      final localQualification = prepared.copyWith(
        id: prepared.id ?? _nextLocalId('qualification'),
      );
      final index = _localQualifications.indexWhere(
        (item) => item.id == localQualification.id,
      );
      if (index == -1) {
        _localQualifications.add(localQualification);
      } else {
        _localQualifications[index] = localQualification;
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveQualification(prepared);
  }

  Future<void> deleteQualification(String qualificationId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      _localQualifications.removeWhere((item) => item.id == qualificationId);
      _localSiteAssignments = _localSiteAssignments
          .map((item) => item.copyWith(
                qualificationIds: item.qualificationIds
                    .where((candidate) => candidate != qualificationId)
                    .toList(growable: false),
              ))
          .toList(growable: false);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteQualification(
      orgId: currentUser.orgId,
      qualificationId: qualificationId,
    );
  }

  Future<void> saveRuleSet(ComplianceRuleSet ruleSet) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final prepared = ruleSet.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );

    if (usesLocalStorage) {
      final localRuleSet =
          prepared.copyWith(id: prepared.id ?? _nextLocalId('rule-set'));
      final index =
          _localRuleSets.indexWhere((item) => item.id == localRuleSet.id);
      if (index == -1) {
        _localRuleSets.add(localRuleSet);
      } else {
        _localRuleSets[index] = localRuleSet;
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveRuleSet(prepared);
  }

  Future<void> saveTravelTimeRule(TravelTimeRule rule) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final existing = travelTimeRules.firstWhere(
      (item) =>
          item.id == rule.id ||
          ((item.fromSiteId == rule.fromSiteId &&
                  item.toSiteId == rule.toSiteId) ||
              (item.fromSiteId == rule.toSiteId &&
                  item.toSiteId == rule.fromSiteId)),
      orElse: () => const TravelTimeRule(
        orgId: '',
        fromSiteId: '',
        toSiteId: '',
        travelMinutes: 0,
      ),
    );

    final prepared = rule.copyWith(
      id: rule.id ?? (existing.id?.isNotEmpty == true ? existing.id : null),
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );

    if (usesLocalStorage) {
      final localRule =
          prepared.copyWith(id: prepared.id ?? _nextLocalId('travel'));
      _localTravelTimeRules.removeWhere(
        (item) =>
            item.id != localRule.id &&
            ((item.fromSiteId == localRule.fromSiteId &&
                    item.toSiteId == localRule.toSiteId) ||
                (item.fromSiteId == localRule.toSiteId &&
                    item.toSiteId == localRule.fromSiteId)),
      );
      final index =
          _localTravelTimeRules.indexWhere((item) => item.id == localRule.id);
      if (index == -1) {
        _localTravelTimeRules.add(localRule);
      } else {
        _localTravelTimeRules[index] = localRule;
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.saveTravelTimeRule(prepared);
  }

  Future<void> deleteTravelTimeRule(String ruleId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      _localTravelTimeRules.removeWhere((item) => item.id == ruleId);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.deleteTravelTimeRule(
      orgId: currentUser.orgId,
      ruleId: ruleId,
    );
  }

  Future<void> setMemberActive({
    required String uid,
    required bool isActive,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    if (usesLocalStorage) {
      if (uid == currentUser.uid) {
        _currentUser = currentUser.copyWith(isActive: isActive);
      } else {
        final index = _localMembers.indexWhere((member) => member.uid == uid);
        if (index == -1) {
          return;
        }
        _localMembers[index] =
            _localMembers[index].copyWith(isActive: isActive);
        _syncInviteForMember(_localMembers[index]);
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      return;
    }

    await _firestoreService.setUserActive(uid: uid, isActive: isActive);
  }

  Future<void> cacheCloudStateLocally() async {
    final currentUser = _currentUser;
    if (currentUser == null || usesLocalStorage) {
      return;
    }

    _localMembers =
        _members.where((member) => member.uid != currentUser.uid).toList();
    _localInvites = [..._invites];
    _localTeams = [..._teams];
    _localSites = [..._sites];
    _localQualifications = [..._qualifications];
    _localContracts = [..._contracts];
    _localSiteAssignments = [..._siteAssignments];
    _localRuleSets = [..._ruleSets];
    _localTravelTimeRules = [..._travelTimeRules];
    await _persistLocalState();
  }

  Future<void> syncLocalStateToCloud() async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    await _firestoreService.upsertUserProfile(currentUser);
    for (final member in _localMembers) {
      await _firestoreService.upsertUserProfile(member);
    }
    for (final invite in _localInvites) {
      await _firestoreService.createOrUpdateInvite(invite);
    }
    for (final team in _localTeams) {
      await _firestoreService.saveTeam(team);
    }
    for (final site in _localSites) {
      await _firestoreService.saveSite(site);
    }
    for (final qualification in _localQualifications) {
      await _firestoreService.saveQualification(qualification);
    }
    for (final contract in _localContracts) {
      await _firestoreService.saveEmploymentContract(contract);
    }

    final assignmentsByUser = <String, List<EmployeeSiteAssignment>>{};
    for (final assignment in _localSiteAssignments) {
      assignmentsByUser
          .putIfAbsent(assignment.userId, () => <EmployeeSiteAssignment>[])
          .add(assignment);
    }
    for (final entry in assignmentsByUser.entries) {
      await _firestoreService.saveSiteAssignments(
        orgId: currentUser.orgId,
        userId: entry.key,
        assignments: entry.value,
      );
    }

    for (final ruleSet in _localRuleSets) {
      await _firestoreService.saveRuleSet(ruleSet);
    }
    for (final rule in _localTravelTimeRules) {
      await _firestoreService.saveTravelTimeRule(rule);
    }
  }

  Future<void> _loadLocalState() async {
    _loading = true;
    notifyListeners();
    _localMembers =
        await DatabaseService.loadLocalTeamMembers(scope: _localScope);
    _localInvites = await DatabaseService.loadLocalInvites(scope: _localScope);
    _localTeams = await DatabaseService.loadLocalTeams(scope: _localScope);
    _localSites = await DatabaseService.loadLocalSites(scope: _localScope);
    _localQualifications =
        await DatabaseService.loadLocalQualifications(scope: _localScope);
    _localContracts = await DatabaseService.loadLocalEmploymentContracts(
      scope: _localScope,
    );
    _localSiteAssignments = await DatabaseService.loadLocalSiteAssignments(
      scope: _localScope,
    );
    _localRuleSets = await DatabaseService.loadLocalRuleSets(
      scope: _localScope,
    );
    _localTravelTimeRules = await DatabaseService.loadLocalTravelTimeRules(
      scope: _localScope,
    );
    if (_currentUser?.isAdmin == true && _localRuleSets.isEmpty) {
      _localRuleSets = [
        ComplianceRuleSet.defaultRetail(
          _currentUser!.orgId,
          createdByUid: _currentUser!.uid,
        ),
      ];
      await DatabaseService.saveLocalRuleSets(
        _localRuleSets,
        scope: _localScope,
      );
    }
    final seededDemoData = _ensureLocalDemoData();
    if (seededDemoData) {
      await _persistLocalState();
    }
    _applyLocalState();
    notifyListeners();
  }

  void _applyLocalState() {
    final currentUser = _currentUser;
    if (currentUser == null) {
      _members = [];
      _invites = [];
      _teams = [];
      _sites = [];
      _qualifications = [];
      _contracts = [];
      _siteAssignments = [];
      _ruleSets = [];
      _travelTimeRules = [];
      _loading = false;
      return;
    }

    final relevantMembers = <AppUserProfile>[
      currentUser,
      ..._localMembers.where(
        (member) =>
            member.orgId == currentUser.orgId && member.uid != currentUser.uid,
      ),
    ];
    final dedupedMembers = <String, AppUserProfile>{};
    for (final member in relevantMembers) {
      dedupedMembers[member.uid] = member;
    }

    _members = dedupedMembers.values.toList(growable: false)
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );

    final validMemberIds = _members.map((member) => member.uid).toSet();
    _invites = _localInvites
        .where(
          (invite) =>
              invite.orgId == currentUser.orgId &&
              invite.isActive &&
              !invite.isAccepted,
        )
        .toList(growable: false)
      ..sort((a, b) => a.emailLower.compareTo(b.emailLower));

    _teams = _localTeams
        .where((team) => team.orgId == currentUser.orgId)
        .map((team) => team.copyWith(
              memberIds: team.memberIds
                  .where(validMemberIds.contains)
                  .toList(growable: false),
            ))
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _sites = _localSites
        .where((site) => site.orgId == currentUser.orgId)
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _qualifications = _localQualifications
        .where((item) => item.orgId == currentUser.orgId)
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _contracts = _localContracts
        .where((contract) => contract.orgId == currentUser.orgId)
        .toList(growable: false);

    _siteAssignments = _localSiteAssignments
        .where((assignment) => assignment.orgId == currentUser.orgId)
        .toList(growable: false);

    _ruleSets = _localRuleSets
        .where((ruleSet) => ruleSet.orgId == currentUser.orgId)
        .toList(growable: false);

    _travelTimeRules = _localTravelTimeRules
        .where((rule) => rule.orgId == currentUser.orgId)
        .toList(growable: false);

    _loading = false;
  }

  Future<void> _persistLocalState() async {
    final scope = _localScope;
    await Future.wait([
      DatabaseService.saveLocalTeamMembers(_localMembers, scope: scope),
      DatabaseService.saveLocalInvites(_localInvites, scope: scope),
      DatabaseService.saveLocalTeams(_localTeams, scope: scope),
      DatabaseService.saveLocalSites(_localSites, scope: scope),
      DatabaseService.saveLocalQualifications(
        _localQualifications,
        scope: scope,
      ),
      DatabaseService.saveLocalEmploymentContracts(
        _localContracts,
        scope: scope,
      ),
      DatabaseService.saveLocalSiteAssignments(
        _localSiteAssignments,
        scope: scope,
      ),
      DatabaseService.saveLocalRuleSets(_localRuleSets, scope: scope),
      DatabaseService.saveLocalTravelTimeRules(
        _localTravelTimeRules,
        scope: scope,
      ),
    ]);
  }

  String get _storageModeKey {
    if (usesLocalStorage) {
      return 'local';
    }
    return usesHybridStorage ? 'hybrid' : 'cloud';
  }

  void _upsertLocalInvite(UserInvite invite) {
    final index = _localInvites.indexWhere((item) => item.id == invite.id);
    if (index == -1) {
      _localInvites.add(invite);
    } else {
      _localInvites[index] = invite;
    }
  }

  void _upsertLocalMember(AppUserProfile member) {
    final index = _localMembers.indexWhere((item) => item.uid == member.uid);
    if (index == -1) {
      _localMembers.add(member);
    } else {
      _localMembers[index] = member;
    }
  }

  void _syncInviteForMember(AppUserProfile member) {
    final index = _localInvites.indexWhere(
      (invite) => _localMemberIdForEmail(invite.email) == member.uid,
    );
    if (index == -1) {
      return;
    }
    final invite = _localInvites[index];
    _localInvites[index] = invite.copyWith(
      email: member.email,
      role: member.role,
      settings: member.settings,
      permissions: member.effectivePermissions,
      isActive: member.isActive,
    );
  }

  AppUserProfile _memberFromInvite(UserInvite invite) {
    return AppUserProfile(
      uid: _localMemberIdForEmail(invite.email),
      orgId: invite.orgId,
      email: invite.email,
      role: invite.role,
      isActive: invite.isActive,
      settings: invite.settings,
      permissions: invite.effectivePermissions,
    );
  }

  String _inviteIdForEmail(String email) =>
      email.trim().toLowerCase().replaceAll('/', '_');

  String _localMemberIdForEmail(String email) =>
      'invite-member-${_inviteIdForEmail(email)}';

  List<EmploymentContract> _effectiveContracts(
    List<EmploymentContract> contracts,
    List<AppUserProfile> members,
  ) {
    final resolved = [...contracts];
    for (final member in members) {
      final hasStored = contracts.any((item) => item.userId == member.uid);
      if (hasStored) {
        continue;
      }
      resolved.add(_defaultContractForMember(member));
    }
    return resolved
      ..sort((a, b) {
        final userCompare = a.userId.compareTo(b.userId);
        if (userCompare != 0) {
          return userCompare;
        }
        return b.validFrom.compareTo(a.validFrom);
      });
  }

  List<ComplianceRuleSet> _effectiveRuleSets(List<ComplianceRuleSet> ruleSets) {
    if (ruleSets.isNotEmpty) {
      return ruleSets;
    }
    final currentUser = _currentUser;
    if (currentUser == null) {
      return const [];
    }
    return [
      ComplianceRuleSet.defaultRetail(
        currentUser.orgId,
        createdByUid: currentUser.uid,
      ),
    ];
  }

  EmploymentContract _defaultContractForMember(AppUserProfile member) {
    final settings = member.settings;
    return EmploymentContract(
      id: 'default-${member.uid}',
      orgId: member.orgId,
      userId: member.uid,
      label: 'Standardvertrag',
      type: settings.hourlyRate > 0 && settings.hourlyRate * 40 <= 603
          ? EmploymentType.miniJob
          : EmploymentType.fullTime,
      validFrom: DateTime(2020, 1, 1),
      weeklyHours: settings.dailyHours * 5,
      dailyHours: settings.dailyHours,
      hourlyRate: settings.hourlyRate,
      currency: settings.currency,
      vacationDays: settings.vacationDays,
      maxDailyMinutes: 600,
      monthlyIncomeLimitCents:
          settings.hourlyRate > 0 && settings.hourlyRate * 40 <= 603
              ? 60300
              : null,
      createdByUid: _currentUser?.uid,
    );
  }

  int _protectionRuleDailyLimit({
    required EmploymentContract contract,
    required bool isMinor,
    required bool isPregnant,
  }) {
    if (isMinor) {
      return 480;
    }
    if (isPregnant) {
      return 510;
    }

    final currentLimit = contract.maxDailyMinutes;
    final usesProtectionDefault = contract.isMinor ||
        contract.isPregnant ||
        currentLimit == null ||
        currentLimit == 480 ||
        currentLimit == 510 ||
        currentLimit == 600;
    return usesProtectionDefault ? 600 : currentLimit;
  }

  String _nextLocalId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _ensureLocalDemoData() {
    final currentUser = _currentUser;
    if (currentUser == null || !LocalDemoData.isDemoUser(currentUser)) {
      return false;
    }

    var changed = false;
    final demoProfiles = LocalDemoData.profilesForOrg(currentUser.orgId);
    for (final profile in demoProfiles) {
      final existingIndex = _localMembers.indexWhere(
        (member) =>
            member.orgId == currentUser.orgId &&
            (member.uid == profile.uid ||
                member.email.trim().toLowerCase() ==
                    profile.email.trim().toLowerCase()),
      );
      if (existingIndex == -1) {
        _localMembers.add(profile);
        changed = true;
        continue;
      }

      final existing = _localMembers[existingIndex];
      final settingsChanged = existing.settings.name != profile.settings.name ||
          existing.settings.hourlyRate != profile.settings.hourlyRate ||
          existing.settings.dailyHours != profile.settings.dailyHours ||
          existing.settings.currency != profile.settings.currency ||
          existing.settings.vacationDays != profile.settings.vacationDays ||
          existing.settings.autoBreakAfterMinutes !=
              profile.settings.autoBreakAfterMinutes;
      if (existing.uid != profile.uid ||
          existing.orgId != profile.orgId ||
          existing.email != profile.email ||
          existing.role != profile.role ||
          existing.isActive != profile.isActive ||
          settingsChanged) {
        _localMembers[existingIndex] = profile;
        changed = true;
      }
    }

    final seededSites = LocalDemoData.sitesForOrg(
      orgId: currentUser.orgId,
      createdByUid: LocalDemoData.adminAccount.uid,
    );
    for (final site in seededSites) {
      final exists = _localSites.any(
        (item) => item.orgId == site.orgId && item.id == site.id,
      );
      if (!exists) {
        _localSites.add(site);
        changed = true;
      }
    }

    for (final profile in demoProfiles) {
      final hasContract = _localContracts.any(
        (contract) =>
            contract.orgId == currentUser.orgId &&
            contract.userId == profile.uid,
      );
      if (!hasContract) {
        _localContracts.add(_defaultContractForMember(profile));
        changed = true;
      }
    }

    final seededAssignments = LocalDemoData.siteAssignmentsForOrg(
      orgId: currentUser.orgId,
      createdByUid: LocalDemoData.adminAccount.uid,
    );
    for (final assignment in seededAssignments) {
      final exists = _localSiteAssignments.any(
        (item) => item.orgId == assignment.orgId && item.id == assignment.id,
      );
      if (!exists) {
        _localSiteAssignments.add(assignment);
        changed = true;
      }
    }

    return changed;
  }

  @override
  void dispose() {
    _disposed = true;
    _membersSubscription?.cancel();
    _invitesSubscription?.cancel();
    _teamsSubscription?.cancel();
    _sitesSubscription?.cancel();
    _qualificationsSubscription?.cancel();
    _contractsSubscription?.cancel();
    _siteAssignmentsSubscription?.cancel();
    _ruleSetsSubscription?.cancel();
    _travelTimeRulesSubscription?.cancel();
    super.dispose();
  }
}
