import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/local_demo_data.dart';
import '../core/site_name_resolver.dart';
import '../models/app_user.dart';
import '../models/audit_log_entry.dart';
import '../models/compliance_rule_set.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/shift_preference.dart';
import '../models/qualification_definition.dart';
import '../models/site_definition.dart';
import '../models/team_definition.dart';
import '../models/travel_time_rule.dart';
import '../models/user_invite.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../core/app_logger.dart';
import '../core/error_reporter.dart';
import 'audit_sink.dart';

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
  StreamSubscription<List<EmployeeShiftPreference>>?
      _shiftPreferencesSubscription;
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
  List<EmployeeShiftPreference> _shiftPreferences = [];
  List<ComplianceRuleSet> _ruleSets = [];
  List<TravelTimeRule> _travelTimeRules = [];
  List<AppUserProfile> _localMembers = [];
  List<UserInvite> _localInvites = [];
  List<TeamDefinition> _localTeams = [];
  List<SiteDefinition> _localSites = [];
  List<QualificationDefinition> _localQualifications = [];
  List<EmploymentContract> _localContracts = [];
  List<EmployeeSiteAssignment> _localSiteAssignments = [];
  List<EmployeeShiftPreference> _localShiftPreferences = [];
  List<ComplianceRuleSet> _localRuleSets = [];
  List<TravelTimeRule> _localTravelTimeRules = [];
  bool _loading = false;
  bool _disposed = false;
  String? _errorMessage;

  List<AppUserProfile> get members => _members;
  List<UserInvite> get invites => _invites;
  List<TeamDefinition> get teams => _teams;
  List<SiteDefinition> get sites => _sites;

  /// Aktueller Standortname zu einer `siteId` (SSoT = `SiteDefinition.name`),
  /// mit dem persistierten Snapshot als Fallback (H-C2, [resolveSiteName]).
  String? siteNameById(String? siteId, {String? fallback}) =>
      resolveSiteName(_sites, siteId, fallback: fallback);

  List<QualificationDefinition> get qualifications => _qualifications;
  List<EmploymentContract> get contracts =>
      _effectiveContracts(_contracts, _members);
  List<EmployeeSiteAssignment> get siteAssignments => _siteAssignments;
  List<EmployeeShiftPreference> get shiftPreferences => _shiftPreferences;
  EmployeeShiftPreference? shiftPreferenceForUser(String userId) =>
      _shiftPreferences.firstWhereOrNull((p) => p.userId == userId);
  List<ComplianceRuleSet> get ruleSets => _effectiveRuleSets(_ruleSets);
  List<TravelTimeRule> get travelTimeRules => _travelTimeRules;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  /// Macht einen Fehler beim fire-and-forget Sitzungsaufbau in der UI sichtbar
  /// (fire-and-forget-updatesession). Reportet NICHT erneut – das uebernimmt
  /// bereits `_dispatchProviderUpdate` in main.dart (kein Doppel-Logging).
  void surfaceSessionError(Object error) {
    _errorMessage =
        'Daten konnten nicht geladen werden. Bitte später erneut versuchen.';
    _errorArea = null;
    _safeNotify();
  }

  /// Loescht einen zuvor gesetzten Stream-Fehler, sobald GENAU DIESER Bereich
  /// wieder gesund Daten liefert (verhindert eine stehenbleibende Fehlermeldung
  /// nach transienter Stoerung – ohne einen persistenten Fehler eines anderen
  /// Bereichs zu verstecken).
  void _markStreamHealthy(String bereich) {
    if (_errorMessage != null && _errorArea == bereich) {
      _errorMessage = null;
      _errorArea = null;
      _safeNotify();
    }
  }

  bool get usesLocalStorage => _forceLocalStorage || _localStorageOnly;
  bool get usesHybridStorage =>
      !_forceLocalStorage && !_localStorageOnly && _hybridStorageEnabled;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // Bereich des aktuell angezeigten Stream-Fehlers (z.B. 'Standorte'), damit ein
  // erholter Stream nur SEINEN eigenen Fehler loescht und einen persistenten
  // Fehler eines anderen Bereichs nicht versteckt.
  String? _errorArea;

  /// Macht einen dauerhaften Stammdaten-Stream-Fehler sichtbar: setzt eine
  /// Nutzer-Botschaft, meldet ihn ans Crash-Reporting und benachrichtigt die
  /// UI (statt ihn nur ins Log zu schlucken — stream-onerror-debugprint-only).
  void _setStreamError(String bereich, Object error) {
    _errorMessage = 'Fehler beim Laden ($bereich). Bitte später erneut versuchen.';
    _errorArea = bereich;
    _loading = false;
    ErrorReporter.report(
      error,
      StackTrace.current,
      context: 'TeamProvider-Stream: $bereich',
    );
    _safeNotify();
  }

  String? _lastSessionKey;

  AuditSink? _audit;

  /// Senke fürs Änderungsprotokoll (best-effort). Wird in main.dart verdrahtet.
  void setAuditSink(AuditSink sink) {
    _audit = sink;
  }

  /// Schlägt den Anzeigenamen eines Mitglieds aus den in-memory-Listen nach
  /// (für menschenlesbare Audit-Zusammenfassungen); Fallback auf die uid.
  String _memberLabel(String uid) {
    final matches = _members.where((member) => member.uid == uid);
    if (matches.isNotEmpty) {
      return matches.first.displayName;
    }
    final localMatches = _localMembers.where((member) => member.uid == uid);
    if (localMatches.isNotEmpty) {
      return localMatches.first.displayName;
    }
    return uid;
  }

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
      // #64: Profil-/Rollen-/Rechte-/isActive-Änderung desselben Nutzers immer
      // übernehmen (billige Referenz-Zuweisung, kein Stream-Neuaufbau) — der
      // sessionKey enthält nur uid/orgId/Modus, nicht die Rolle.
      _currentUser = user;
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
      _shiftPreferences = [];
      _ruleSets = [];
      _travelTimeRules = [];
      _localMembers = [];
      _localInvites = [];
      _localTeams = [];
      _localSites = [];
      _localQualifications = [];
      _localContracts = [];
      _localSiteAssignments = [];
      _localShiftPreferences = [];
      _localRuleSets = [];
      _localTravelTimeRules = [];
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _shiftPreferencesSubscription?.cancel();
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
      await _shiftPreferencesSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();
      _membersSubscription = null;
      _invitesSubscription = null;
      _teamsSubscription = null;
      _sitesSubscription = null;
      _qualificationsSubscription = null;
      _contractsSubscription = null;
      _siteAssignmentsSubscription = null;
      _shiftPreferencesSubscription = null;
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
      await _shiftPreferencesSubscription?.cancel();
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
              _localShiftPreferences.isEmpty &&
              _localRuleSets.isEmpty &&
              _localTravelTimeRules.isEmpty)) {
        await _loadLocalState();
      } else {
        _applyLocalState();
        notifyListeners();
      }
      return;
    }

    if (usesHybridStorage &&
        (changed ||
            storageModeChanged ||
            (_localMembers.isEmpty &&
                _localInvites.isEmpty &&
                _localTeams.isEmpty &&
                _localSites.isEmpty &&
                _localQualifications.isEmpty &&
                _localContracts.isEmpty &&
                _localSiteAssignments.isEmpty &&
                _localShiftPreferences.isEmpty &&
                _localRuleSets.isEmpty &&
                _localTravelTimeRules.isEmpty))) {
      await _loadLocalState();
    }

    if (!user.canManageShifts) {
      _members = [user];
      _invites = [];
      _teams = [];
    }

    if (changed || storageModeChanged) {
      _loading = true;
      _errorMessage = null; // stale Stream-Fehler vor Neuaufbau zuruecksetzen
      _errorArea = null;
      _safeNotify();
      await _membersSubscription?.cancel();
      await _invitesSubscription?.cancel();
      await _teamsSubscription?.cancel();
      await _sitesSubscription?.cancel();
      await _qualificationsSubscription?.cancel();
      await _contractsSubscription?.cancel();
      await _siteAssignmentsSubscription?.cancel();
      await _shiftPreferencesSubscription?.cancel();
      await _ruleSetsSubscription?.cancel();
      await _travelTimeRulesSubscription?.cancel();

      // Im Hybrid-Modus bleiben strukturelle Stammdaten lokal als Fallback
      // erhalten. Cloud-Snapshots aktualisieren diesen Cache inkrementell,
      // damit beim Wechsel aus dem Local-Modus oder bei unvollstaendigen
      // Transfers keine Standorte, Zuordnungen oder Regeln verloren gehen.

      if (user.canManageShifts) {
        _membersSubscription = _firestoreService
            .watchOrganizationUsers(user.orgId)
            .listen((items) {
          _markStreamHealthy('Mitglieder');
          if (usesHybridStorage) {
            unawaited(
              _storeHybridMembersSnapshot(
                items.where((member) => member.uid != user.uid).toList(),
              ),
            );
            return;
          }
          _members = items;
          _loading = false;
          _safeNotify();
        }, onError: (Object error) {
          _setStreamError('Mitglieder', error);
        });

        if (user.isAdmin) {
          _invitesSubscription =
              _firestoreService.watchInvites(user.orgId).listen((items) {
            if (usesHybridStorage) {
              unawaited(_storeHybridInvitesSnapshot(items));
              return;
            }
            _invites = items;
            _safeNotify();
          }, onError: (Object error) {
            _setStreamError('Einladungen', error);
          });
        } else {
          _invites = [];
        }

        _teamsSubscription = _firestoreService.watchTeams(user.orgId).listen((
          items,
        ) {
          if (usesHybridStorage) {
            unawaited(_storeHybridTeamsSnapshot(items));
            return;
          }
          _teams = items;
          _safeNotify();
        }, onError: (Object error) {
          _setStreamError('Teams', error);
        });
      } else {
        _members = [user];
        _invites = [];
        _teams = [];
        // #63: Nicht-Manager haben keinen Mitglieder-Stream, der `_loading`
        // zurücksetzt → Spinner hing dauerhaft. Stammdaten kommen über die
        // Sites/Quali-Streams nach; die Mitglieder-Sicht ist sofort fertig.
        _loading = false;
      }

      _sitesSubscription = _firestoreService.watchSites(user.orgId).listen(
        (items) {
          _markStreamHealthy('Standorte');
          if (usesHybridStorage) {
            unawaited(_storeHybridSitesSnapshot(items));
            return;
          }
          _sites = items;
          _safeNotify();
        },
        onError: (Object error) {
          _setStreamError('Standorte', error);
        },
      );

      _qualificationsSubscription =
          _firestoreService.watchQualifications(user.orgId).listen((items) {
        if (usesHybridStorage) {
          unawaited(_storeHybridQualificationsSnapshot(items));
          return;
        }
        _qualifications = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Qualifikationen', error);
      });

      // PA-0.2: Vertraege sind seit der Leck-Schliessung nicht mehr org-weit
      // lesbar. Manager streamen weiterhin alle (Planung/Compliance/Verteiler),
      // Nicht-Manager nur den eigenen Vertrag (self-Query) — sonst liefert der
      // org-weite Stream permission-denied und der Mitarbeiter verliert auch
      // seine eigenen Referenzdaten fuer die Compliance-Vorschau.
      final contractsStream = user.canManageShifts
          ? _firestoreService.watchEmploymentContracts(user.orgId)
          : _firestoreService.watchEmploymentContractsForUser(
              user.orgId,
              user.uid,
            );
      _contractsSubscription = contractsStream.listen((items) {
        if (usesHybridStorage) {
          unawaited(_storeHybridContractsSnapshot(items));
          return;
        }
        _contracts = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Verträge', error);
      });

      _siteAssignmentsSubscription =
          _firestoreService.watchSiteAssignments(user.orgId).listen((items) {
        if (usesHybridStorage) {
          unawaited(_storeHybridSiteAssignmentsSnapshot(items));
          return;
        }
        _siteAssignments = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Standortzuordnungen', error);
      });

      _shiftPreferencesSubscription =
          _firestoreService.watchShiftPreferences(user.orgId).listen((items) {
        if (usesHybridStorage) {
          unawaited(_storeHybridShiftPreferencesSnapshot(items));
          return;
        }
        _shiftPreferences = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Schicht-Vorgaben', error);
      });

      _ruleSetsSubscription =
          _firestoreService.watchRuleSets(user.orgId).listen((items) async {
        if (user.isAdmin && items.isEmpty) {
          await saveRuleSet(
            ComplianceRuleSet.defaultRetail(
              user.orgId,
              createdByUid: user.uid,
            ),
          );
          return;
        }
        if (usesHybridStorage) {
          await _storeHybridRuleSetsSnapshot(items);
          return;
        }
        _ruleSets = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Regelwerke', error);
      });

      _travelTimeRulesSubscription =
          _firestoreService.watchTravelTimeRules(user.orgId).listen((items) {
        if (usesHybridStorage) {
          unawaited(_storeHybridTravelTimeRulesSnapshot(items));
          return;
        }
        _travelTimeRules = items;
        _safeNotify();
      }, onError: (Object error) {
        _setStreamError('Fahrtzeitregeln', error);
      });
    }
  }

  Future<void> saveInvite(UserInvite invite) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final isNew = invite.id == null || invite.id!.isEmpty;
    final preparedInvite = invite.copyWith(
      id: invite.id ?? _inviteIdForEmail(invite.email),
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );
    final auditSummary =
        'Einladung ${preparedInvite.email} (${preparedInvite.role.label}) '
        'gespeichert';

    if (usesLocalStorage) {
      _upsertLocalInvite(preparedInvite);
      _upsertLocalMember(_memberFromInvite(preparedInvite));
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: isNew ? AuditAction.created : AuditAction.updated,
        entityType: 'Einladung',
        entityId: preparedInvite.id,
        summary: auditSummary,
      );
      return;
    }

    await _firestoreService.createOrUpdateInvite(preparedInvite);
    _audit?.call(
      action: isNew ? AuditAction.created : AuditAction.updated,
      entityType: 'Einladung',
      entityId: preparedInvite.id,
      summary: auditSummary,
    );
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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Einladung',
        entityId: inviteId,
        summary: 'Einladung gelöscht',
      );
      return;
    }

    await _firestoreService.deleteInvite(inviteId);
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Einladung',
      entityId: inviteId,
      summary: 'Einladung gelöscht',
    );
  }

  Future<void> saveTeam(TeamDefinition team) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final memberIds = team.memberIds.toSet().toList(growable: false);
    final isNew = team.id == null || team.id!.isEmpty;
    final preparedTeam = team.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
      memberIds: memberIds,
    );
    final auditAction = isNew ? AuditAction.created : AuditAction.updated;
    final auditSummary = 'Team „${preparedTeam.name}" gespeichert';

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
      _audit?.call(
        action: auditAction,
        entityType: 'Team',
        entityId: localTeam.id,
        summary: auditSummary,
      );
      return;
    }

    final savedId = await _firestoreService.saveTeam(preparedTeam);
    _audit?.call(
      action: auditAction,
      entityType: 'Team',
      entityId: preparedTeam.id ?? savedId,
      summary: auditSummary,
    );
  }

  Future<void> deleteTeam(String teamId) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    // Namen vor dem Löschen nachschlagen (cloud-Liste, sonst lokale Liste).
    final namedTeam = [..._teams, ..._localTeams].where(
      (team) => team.id == teamId,
    );
    final auditSummary = namedTeam.isEmpty
        ? 'Team gelöscht'
        : 'Team „${namedTeam.first.name}" gelöscht';

    if (usesLocalStorage) {
      _localTeams.removeWhere((team) => team.id == teamId);
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Team',
        entityId: teamId,
        summary: auditSummary,
      );
      return;
    }

    await _firestoreService.deleteTeam(
      orgId: currentUser.orgId,
      teamId: teamId,
    );
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Team',
      entityId: teamId,
      summary: auditSummary,
    );
  }

  Future<void> updateMember(AppUserProfile profile) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final persisted = await _updateMemberInternal(profile);
    if (!persisted) {
      return;
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Mitglied',
      entityId: profile.uid,
      summary: 'Mitglied ${profile.displayName} aktualisiert',
    );
  }

  /// Schreibt das Mitgliedsprofil ohne eigenes Audit-Logging und meldet, ob die
  /// Persistierung stattfand. Geteilt von [updateMember] und Wrappern wie
  /// [saveMemberWorkRuleSettings], damit pro oeffentlicher Aktion GENAU EINMAL
  /// geloggt wird (kein Doppel-Logging ueber die Delegation).
  Future<bool> _updateMemberInternal(AppUserProfile profile) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return false;
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
      return true;
    }

    await _firestoreService.upsertUserProfile(profile);
    return true;
  }

  Future<void> saveMemberConfiguration({
    required AppUserProfile profile,
    required EmploymentContract contract,
    required List<EmployeeSiteAssignment> siteAssignments,
  }) async {
    final persisted = await _saveMemberConfigurationInternal(
      profile: profile,
      contract: contract,
      siteAssignments: siteAssignments,
    );
    if (!persisted) {
      return;
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Mitglied',
      entityId: profile.uid,
      summary: 'Mitglied-Konfiguration ${profile.displayName} gespeichert',
    );
  }

  /// Schreibt Profil + Vertrag + Standortzuordnungen ohne eigenes Audit-Logging
  /// und meldet, ob persistiert wurde. Geteilt von [saveMemberConfiguration] und
  /// [saveMemberProtectionRules], damit jede oeffentliche Aktion GENAU EINMAL
  /// mit ihrer eigenen Zusammenfassung loggt (kein Doppel-Logging).
  Future<bool> _saveMemberConfigurationInternal({
    required AppUserProfile profile,
    required EmploymentContract contract,
    required List<EmployeeSiteAssignment> siteAssignments,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return false;
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
      return true;
    }

    await _firestoreService.upsertUserProfile(profile);
    await _firestoreService.saveEmploymentContract(preparedContract);
    await _firestoreService.saveSiteAssignments(
      orgId: currentUser.orgId,
      userId: profile.uid,
      assignments: preparedAssignments,
    );
    return true;
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

    // Direkt an den nicht-loggenden Helfer delegieren, damit hier GENAU EINMAL
    // mit der eigenen „Schutzregeln"-Zusammenfassung geloggt wird (kein
    // zusaetzliches „Mitglied-Konfiguration"-Log aus saveMemberConfiguration).
    final persisted = await _saveMemberConfigurationInternal(
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
    if (!persisted) {
      return;
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Mitglied',
      entityId: userId,
      summary: 'Schutzregeln für ${member.displayName} gespeichert',
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

    final member = memberMatches.first;
    // Nicht-loggenden Helfer nutzen, damit hier GENAU EINMAL mit der eigenen
    // „Arbeitsregeln"-Zusammenfassung geloggt wird (kein zusaetzliches
    // „Mitglied aktualisiert"-Log aus updateMember).
    final persisted = await _updateMemberInternal(
      member.copyWith(workRuleSettings: settings),
    );
    if (!persisted) {
      return;
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Mitglied',
      entityId: userId,
      summary: 'Arbeitsregeln für ${member.displayName} gespeichert',
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
    final isNew = site.id == null || site.id!.isEmpty;
    final auditAction = isNew ? AuditAction.created : AuditAction.updated;
    final auditSummary = 'Standort „${prepared.name}" gespeichert';

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
      _audit?.call(
        action: auditAction,
        entityType: 'Standort',
        entityId: localSite.id,
        summary: auditSummary,
      );
      return;
    }

    final savedId = await _firestoreService.saveSite(prepared);
    _audit?.call(
      action: auditAction,
      entityType: 'Standort',
      entityId: prepared.id ?? savedId,
      summary: auditSummary,
    );
  }

  /// Speichert (oder löscht bei leerer Regelliste) die Schicht-Vorgaben eines
  /// Mitarbeiters. Nur Chef/Teamleitung. Doc-ID = userId (eine Vorgabe je
  /// Mitarbeiter). Wird vom Verteiler (`proposeAutoAssignment`) ausgewertet.
  Future<void> saveShiftPreference(EmployeeShiftPreference preference) async {
    final currentUser = _currentUser;
    if (currentUser == null ||
        !(currentUser.isAdmin || currentUser.isTeamLead)) {
      return;
    }
    if (preference.userId.trim().isEmpty) {
      return;
    }

    final prepared = preference.copyWith(
      id: preference.userId,
      orgId: currentUser.orgId,
    );
    final isEmpty = prepared.rules.isEmpty;
    final auditSummary = isEmpty
        ? 'Schicht-Vorgaben zurückgesetzt'
        : 'Schicht-Vorgaben aktualisiert (${prepared.rules.length} Regel(n))';

    if (usesLocalStorage) {
      _localShiftPreferences.removeWhere(
        (item) =>
            item.orgId == prepared.orgId && item.userId == prepared.userId,
      );
      if (!isEmpty) {
        _localShiftPreferences.add(prepared);
      }
      await _persistLocalState();
      _applyLocalState();
      notifyListeners();
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Schicht-Vorgaben',
        entityId: prepared.userId,
        summary: auditSummary,
      );
      return;
    }

    if (isEmpty) {
      await _firestoreService.deleteShiftPreference(
        orgId: prepared.orgId,
        userId: prepared.userId,
      );
    } else {
      await _firestoreService.saveShiftPreference(prepared);
    }
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Schicht-Vorgaben',
      entityId: prepared.userId,
      summary: auditSummary,
    );
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

    // Namen vor dem Löschen nachschlagen (cloud-Liste, sonst lokale Liste).
    final namedSite = [..._sites, ..._localSites].where(
      (site) => site.id == siteId,
    );
    final auditSummary = namedSite.isEmpty
        ? 'Standort gelöscht'
        : 'Standort „${namedSite.first.name}" gelöscht';

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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Standort',
        entityId: siteId,
        summary: auditSummary,
      );
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
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Standort',
      entityId: siteId,
      summary: auditSummary,
    );
  }

  Future<void> saveQualification(QualificationDefinition qualification) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final isNew = qualification.id == null || qualification.id!.isEmpty;
    final prepared = qualification.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );
    final auditAction = isNew ? AuditAction.created : AuditAction.updated;
    final auditSummary = 'Qualifikation „${prepared.name}" gespeichert';

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
      _audit?.call(
        action: auditAction,
        entityType: 'Qualifikation',
        entityId: localQualification.id,
        summary: auditSummary,
      );
      return;
    }

    final savedId = await _firestoreService.saveQualification(prepared);
    _audit?.call(
      action: auditAction,
      entityType: 'Qualifikation',
      entityId: prepared.id ?? savedId,
      summary: auditSummary,
    );
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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Qualifikation',
        entityId: qualificationId,
        summary: 'Qualifikation gelöscht',
      );
      return;
    }

    await _firestoreService.deleteQualification(
      orgId: currentUser.orgId,
      qualificationId: qualificationId,
    );
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Qualifikation',
      entityId: qualificationId,
      summary: 'Qualifikation gelöscht',
    );
  }

  Future<void> saveRuleSet(ComplianceRuleSet ruleSet) async {
    final currentUser = _currentUser;
    if (currentUser == null || !currentUser.isAdmin) {
      return;
    }

    final isNew = ruleSet.id == null || ruleSet.id!.isEmpty;
    final prepared = ruleSet.copyWith(
      orgId: currentUser.orgId,
      createdByUid: currentUser.uid,
    );
    final auditAction = isNew ? AuditAction.created : AuditAction.updated;
    final auditSummary = 'Regelwerk „${prepared.name}" gespeichert';

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
      _audit?.call(
        action: auditAction,
        entityType: 'Regelwerk',
        entityId: localRuleSet.id,
        summary: auditSummary,
      );
      return;
    }

    final savedId = await _firestoreService.saveRuleSet(prepared);
    _audit?.call(
      action: auditAction,
      entityType: 'Regelwerk',
      entityId: prepared.id ?? savedId,
      summary: auditSummary,
    );
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
    // „Neu", wenn weder eine eingehende id noch eine passende bestehende Regel
    // existiert (sonst wird eine vorhandene Regel ueberschrieben → updated).
    final isNew = prepared.id == null || prepared.id!.isEmpty;
    final auditAction = isNew ? AuditAction.created : AuditAction.updated;
    final auditSummary = _travelRuleSummary(prepared);

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
      _audit?.call(
        action: auditAction,
        entityType: 'Wegezeit-Regel',
        entityId: localRule.id,
        summary: auditSummary,
      );
      return;
    }

    final savedId = await _firestoreService.saveTravelTimeRule(prepared);
    _audit?.call(
      action: auditAction,
      entityType: 'Wegezeit-Regel',
      entityId: prepared.id ?? savedId,
      summary: auditSummary,
    );
  }

  /// Menschlich lesbare Zusammenfassung einer Wegezeit-Regel; ersetzt die
  /// Standort-ids durch Standortnamen, wenn verfuegbar.
  String _travelRuleSummary(TravelTimeRule rule) {
    final from = _siteName(rule.fromSiteId);
    final to = _siteName(rule.toSiteId);
    return 'Wegezeit-Regel $from → $to gespeichert';
  }

  String _siteName(String siteId) {
    final matches = [..._sites, ..._localSites].where(
      (site) => site.id == siteId,
    );
    return matches.isEmpty ? siteId : matches.first.name;
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
      _audit?.call(
        action: AuditAction.deleted,
        entityType: 'Wegezeit-Regel',
        entityId: ruleId,
        summary: 'Wegezeit-Regel gelöscht',
      );
      return;
    }

    await _firestoreService.deleteTravelTimeRule(
      orgId: currentUser.orgId,
      ruleId: ruleId,
    );
    _audit?.call(
      action: AuditAction.deleted,
      entityType: 'Wegezeit-Regel',
      entityId: ruleId,
      summary: 'Wegezeit-Regel gelöscht',
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

    // Zugriffssteuerung – wichtig, daher den Namen vorab nachschlagen.
    final memberName =
        uid == currentUser.uid ? currentUser.displayName : _memberLabel(uid);
    final auditSummary =
        'Mitglied $memberName ${isActive ? 'aktiviert' : 'deaktiviert'}';

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
      _audit?.call(
        action: AuditAction.updated,
        entityType: 'Mitglied',
        entityId: uid,
        summary: auditSummary,
      );
      return;
    }

    // #65: Defense-in-Depth — nur Mitglieder der eigenen Org (de)aktivieren
    // (die Firestore-Rules erzwingen das ebenfalls; hier zusätzlich am Client).
    final isOrgMember =
        uid == currentUser.uid || _members.any((m) => m.uid == uid);
    if (!isOrgMember) {
      return;
    }
    await _firestoreService.setUserActive(uid: uid, isActive: isActive);
    _audit?.call(
      action: AuditAction.updated,
      entityType: 'Mitglied',
      entityId: uid,
      summary: auditSummary,
    );
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
    _localShiftPreferences = [..._shiftPreferences];
    _localRuleSets = [..._ruleSets];
    _localTravelTimeRules = [..._travelTimeRules];
    await _persistLocalState();
  }

  Future<void> syncLocalStateToCloud() async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      await _firestoreService.upsertUserProfile(currentUser);
    } catch (error) {
      AppLogger.warning('syncLocalStateToCloud: eigenes Profil konnte nicht '
          'geschrieben werden: $error');
    }

    if (!currentUser.isAdmin) {
      return;
    }

    for (final member in _localMembers) {
      try {
        await _firestoreService.upsertUserProfile(member);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Mitglied ${member.uid} '
            'konnte nicht geschrieben werden: $error');
      }
    }
    for (final invite in _localInvites) {
      try {
        await _firestoreService.createOrUpdateInvite(invite);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Einladung konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final team in _localTeams) {
      try {
        await _firestoreService.saveTeam(team);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Team konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final site in _localSites) {
      try {
        await _firestoreService.saveSite(site);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Standort konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final qualification in _localQualifications) {
      try {
        await _firestoreService.saveQualification(qualification);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Qualifikation konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final contract in _localContracts) {
      try {
        await _firestoreService.saveEmploymentContract(contract);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Vertrag konnte nicht '
            'geschrieben werden: $error');
      }
    }

    final assignmentsByUser = <String, List<EmployeeSiteAssignment>>{};
    for (final assignment in _localSiteAssignments) {
      assignmentsByUser
          .putIfAbsent(assignment.userId, () => <EmployeeSiteAssignment>[])
          .add(assignment);
    }
    for (final entry in assignmentsByUser.entries) {
      try {
        await _firestoreService.saveSiteAssignments(
          orgId: currentUser.orgId,
          userId: entry.key,
          assignments: entry.value,
        );
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Standortzuweisungen konnten '
            'nicht geschrieben werden: $error');
      }
    }

    for (final ruleSet in _localRuleSets) {
      try {
        await _firestoreService.saveRuleSet(ruleSet);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Regelwerk konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final rule in _localTravelTimeRules) {
      try {
        await _firestoreService.saveTravelTimeRule(rule);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Fahrtzeitregel konnte nicht '
            'geschrieben werden: $error');
      }
    }
    for (final preference in _localShiftPreferences) {
      try {
        await _firestoreService.saveShiftPreference(preference);
      } catch (error) {
        AppLogger.warning('syncLocalStateToCloud: Schicht-Vorgaben konnten '
            'nicht geschrieben werden: $error');
      }
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
    _localShiftPreferences = await DatabaseService.loadLocalShiftPreferences(
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
      _shiftPreferences = [];
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

    _shiftPreferences = _localShiftPreferences
        .where((pref) => pref.orgId == currentUser.orgId)
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
      DatabaseService.saveLocalShiftPreferences(
        _localShiftPreferences,
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

  Future<void> _storeHybridMembersSnapshot(
    List<AppUserProfile> items,
  ) async {
    await _storeHybridCollection<AppUserProfile>(
      cloudItems: items,
      currentLocalItems: _localMembers,
      assignLocal: (merged) => _localMembers = merged,
      persist: DatabaseService.saveLocalTeamMembers,
      keyOf: (member) => member.uid,
    );
  }

  Future<void> _storeHybridInvitesSnapshot(
    List<UserInvite> items,
  ) async {
    await _storeHybridCollection<UserInvite>(
      cloudItems: items,
      currentLocalItems: _localInvites,
      assignLocal: (merged) => _localInvites = merged,
      persist: DatabaseService.saveLocalInvites,
      keyOf: (invite) =>
          invite.id?.trim().isNotEmpty == true ? invite.id! : invite.emailLower,
    );
  }

  Future<void> _storeHybridTeamsSnapshot(
    List<TeamDefinition> items,
  ) async {
    await _storeHybridCollection<TeamDefinition>(
      cloudItems: items,
      currentLocalItems: _localTeams,
      assignLocal: (merged) => _localTeams = merged,
      persist: DatabaseService.saveLocalTeams,
      keyOf: (team) =>
          team.id?.trim().isNotEmpty == true ? team.id! : team.name,
    );
  }

  Future<void> _storeHybridSitesSnapshot(
    List<SiteDefinition> items,
  ) async {
    await _storeHybridCollection<SiteDefinition>(
      cloudItems: items,
      currentLocalItems: _localSites,
      assignLocal: (merged) => _localSites = merged,
      persist: DatabaseService.saveLocalSites,
      keyOf: (site) =>
          site.id?.trim().isNotEmpty == true ? site.id! : site.name,
    );
  }

  Future<void> _storeHybridQualificationsSnapshot(
    List<QualificationDefinition> items,
  ) async {
    await _storeHybridCollection<QualificationDefinition>(
      cloudItems: items,
      currentLocalItems: _localQualifications,
      assignLocal: (merged) => _localQualifications = merged,
      persist: DatabaseService.saveLocalQualifications,
      keyOf: (qualification) => qualification.id?.trim().isNotEmpty == true
          ? qualification.id!
          : qualification.name,
    );
  }

  Future<void> _storeHybridContractsSnapshot(
    List<EmploymentContract> items,
  ) async {
    await _storeHybridCollection<EmploymentContract>(
      cloudItems: items,
      currentLocalItems: _localContracts,
      assignLocal: (merged) => _localContracts = merged,
      persist: DatabaseService.saveLocalEmploymentContracts,
      keyOf: (contract) => contract.id?.trim().isNotEmpty == true
          ? contract.id!
          : '${contract.userId}:${contract.validFrom.toIso8601String()}',
    );
  }

  Future<void> _storeHybridSiteAssignmentsSnapshot(
    List<EmployeeSiteAssignment> items,
  ) async {
    await _storeHybridCollection<EmployeeSiteAssignment>(
      cloudItems: items,
      currentLocalItems: _localSiteAssignments,
      assignLocal: (merged) => _localSiteAssignments = merged,
      persist: DatabaseService.saveLocalSiteAssignments,
      keyOf: (assignment) => assignment.id?.trim().isNotEmpty == true
          ? assignment.id!
          : '${assignment.userId}:${assignment.siteId}',
    );
  }

  Future<void> _storeHybridShiftPreferencesSnapshot(
    List<EmployeeShiftPreference> items,
  ) async {
    await _storeHybridCollection<EmployeeShiftPreference>(
      cloudItems: items,
      currentLocalItems: _localShiftPreferences,
      assignLocal: (merged) => _localShiftPreferences = merged,
      persist: DatabaseService.saveLocalShiftPreferences,
      keyOf: (pref) =>
          pref.id?.trim().isNotEmpty == true ? pref.id! : pref.userId,
    );
  }

  Future<void> _storeHybridRuleSetsSnapshot(
    List<ComplianceRuleSet> items,
  ) async {
    await _storeHybridCollection<ComplianceRuleSet>(
      cloudItems: items,
      currentLocalItems: _localRuleSets,
      assignLocal: (merged) => _localRuleSets = merged,
      persist: DatabaseService.saveLocalRuleSets,
      keyOf: (ruleSet) =>
          ruleSet.id?.trim().isNotEmpty == true ? ruleSet.id! : ruleSet.name,
    );
  }

  Future<void> _storeHybridTravelTimeRulesSnapshot(
    List<TravelTimeRule> items,
  ) async {
    await _storeHybridCollection<TravelTimeRule>(
      cloudItems: items,
      currentLocalItems: _localTravelTimeRules,
      assignLocal: (merged) => _localTravelTimeRules = merged,
      persist: DatabaseService.saveLocalTravelTimeRules,
      keyOf: (rule) => rule.id?.trim().isNotEmpty == true
          ? rule.id!
          : '${rule.fromSiteId}:${rule.toSiteId}',
    );
  }

  Future<void> _storeHybridCollection<T>({
    required List<T> cloudItems,
    required List<T> currentLocalItems,
    required void Function(List<T> items) assignLocal,
    required Future<void> Function(
      List<T> items, {
      LocalStorageScope? scope,
    }) persist,
    required String Function(T item) keyOf,
  }) async {
    final scope = _localScope;
    if (!usesHybridStorage || scope == null) {
      return;
    }
    final merged = _mergeByKey(currentLocalItems, cloudItems, keyOf);
    assignLocal(merged);
    _applyLocalState();
    _safeNotify();
    await persist(merged, scope: scope);
  }

  List<T> _mergeByKey<T>(
    Iterable<T> localItems,
    Iterable<T> remoteItems,
    String Function(T item) keyOf,
  ) {
    final merged = <String, T>{};
    var index = 0;
    for (final item in localItems) {
      final key = keyOf(item).trim();
      merged[key.isEmpty ? 'local:$index' : key] = item;
      index++;
    }
    for (final item in remoteItems) {
      final key = keyOf(item).trim();
      merged[key.isEmpty ? 'remote:$index' : key] = item;
      index++;
    }
    return merged.values.toList(growable: true);
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
      // Ohne Festgehalt ist ein Stundensatz-Mitarbeiter ein Stundenlöhner —
      // sonst klassifiziert der synthetische Standardvertrag ihn als
      // Festgehalt OHNE monthlyGrossCents, und die Lohn-Herleitung
      // (LohnHerleitung.grundlohnCents) liefert 0 → der Monatsabschluss
      // erzeugt KEINEN Lohn-Entwurf und der Lohnlauf bleibt leer.
      salaryKind:
          settings.hourlyRate > 0 ? SalaryKind.hourly : SalaryKind.monthly,
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
    _shiftPreferencesSubscription?.cancel();
    _ruleSetsSubscription?.cancel();
    _travelTimeRulesSubscription?.cancel();
    super.dispose();
  }
}
