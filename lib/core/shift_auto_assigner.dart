import 'package:collection/collection.dart';

import '../models/absence_request.dart';
import '../models/app_user.dart';
import '../models/compliance_rule_set.dart';
import '../models/compliance_violation.dart';
import '../models/employee_site_assignment.dart';
import '../models/employment_contract.dart';
import '../models/org_settings.dart';
import '../models/shift.dart';
import '../models/shift_preference.dart';
import '../models/sollzeit_profile.dart';
import '../models/travel_time_rule.dart';
import '../services/compliance_service.dart';

/// Grund, warum eine offene Schicht nicht automatisch besetzt werden konnte.
enum UnassignableReason {
  qualification,
  site,
  monthlyCap,
  weeklyCap,
  minijob,
  absence,
  doubleBooking,
  compliance,

  /// Es gäbe grundsätzlich geeignete Mitarbeiter, doch alle sind in dieser Zeit
  /// bereits anderweitig verplant und ließen sich auch durch Umverteilung
  /// (Ejection-Chain bis [ShiftAutoAssigner._maxEjectionDepth]) nicht freischaufeln.
  contention,

  /// Alle geeigneten Mitarbeiter haben diese Zeit per harter Vorgabe gesperrt
  /// (`PreferenceKind.block`) — wie eine Abwesenheit behandelt.
  preferenceBlock,

  noCandidates,
}

/// Vorschlag, eine Schicht einem Mitarbeiter zuzuweisen (Snapshot — der Core
/// **mutiert keine** [Shift]; UI/Provider baut `shift.copyWith(...)`).
class ShiftAssignmentProposal {
  const ShiftAssignmentProposal({
    required this.shiftId,
    required this.userId,
    required this.userName,
    required this.score,
    required this.reason,
  });

  final String shiftId;
  final String userId;
  final String userName;
  final double score;
  final String reason;
}

/// Eine offene Schicht, die nicht zugewiesen werden konnte (+ deutscher Grund).
class UnassignableShift {
  const UnassignableShift({
    required this.shiftId,
    required this.reason,
    required this.message,
  });

  final String shiftId;
  final UnassignableReason reason;
  final String message;
}

/// Weiche Verletzung (z.B. Soft-Cap überschritten) — nur im weichen Cap-Modus.
class AssignmentWarning {
  const AssignmentWarning({
    required this.shiftId,
    required this.userId,
    required this.userName,
    required this.message,
  });

  final String shiftId;
  final String userId;
  final String userName;
  final String message;
}

/// Reines Ergebnis von [ShiftAutoAssigner.assign].
class AutoAssignmentResult {
  const AutoAssignmentResult({
    this.assignments = const [],
    this.unassigned = const [],
    this.warnings = const [],
  });

  final List<ShiftAssignmentProposal> assignments;
  final List<UnassignableShift> unassigned;
  final List<AssignmentWarning> warnings;
}

/// **Phase B** der automatischen Schichtverteilung: verteilt unbesetzte
/// Schichten auf Mitarbeiter unter **harten** Constraints (Standort, Quali,
/// Abwesenheit, Doppelbelegung, Compliance, Cap/Minijob) und **weichen** Zielen
/// (Fairness Richtung Sollzeit).
///
/// ## Algorithmus (Optimierer statt Einmal-Greedy)
///
/// Frühere Versionen waren ein **start-zeit-sortierter Greedy** (jede Schicht
/// einmalig an den besten Kandidaten, nie revidiert). Das ließ schwer besetzbare
/// Schichten leer, wenn ein früher Slot den einzigen passenden Mitarbeiter
/// „wegnahm". Diese Version ist ein dreistufiger Optimierer:
///
/// 1. **Konstruktion mit MRV-Heuristik** (`_construct`): es wird stets zuerst die
///    Schicht mit den **wenigsten zulässigen Kandidaten** besetzt (Minimum
///    Remaining Values), nicht die früheste. Kandidatenmengen schrumpfen
///    monoton (mehr Zuweisungen ⇒ nie mehr Spielraum), daher wird inkrementell
///    geprunt.
/// 2. **Ejection-Chain-Augmentierung** (`_augment`): bleibt eine grundsätzlich
///    besetzbare Schicht durch Verdrängung offen, wird eine blockierende
///    Zuweisung verschoben und neu vergeben (augmentierender Pfad, an die
///    zustandsabhängigen Compliance-/Cap-Constraints angepasst — deshalb **kein**
///    reines Min-Cost-Flow/Hungarian). Tiefe begrenzt ([_maxEjectionDepth]).
/// 3. **Lokale Suche für Fairness** (`_balanceFairness`): deterministische
///    Steepest-Descent-Verschiebungen/-Tausche reduzieren die quadratische
///    Abweichung von der Sollzeit, **ohne** Abdeckung zu verlieren oder harte
///    Regeln zu verletzen.
///
/// **Pure / testbar:** kein Provider-State, kein `BuildContext`, keine
/// Async-IO, **kein** `DateTime.now()`, **keine** Zufallswerte. Alle
/// Reihenfolgen/Tie-Breaks sind explizit deterministisch (Schicht: start,
/// siteId, id — Kandidat: uid aufsteigend). Cap-Härte über
/// `settings.enforceHourCapHard` umschaltbar; Compliance + Minijob bleiben in
/// beiden Fällen hart.
class ShiftAutoAssigner {
  ShiftAutoAssigner({
    required this.openShifts,
    required this.members,
    required this.contracts,
    required this.siteAssignments,
    required this.approvedAbsences,
    required this.existingAssignedShifts,
    required this.ruleSets,
    required this.travelTimeRules,
    required this.complianceService,
    required this.settings,
    this.sollzeitByUserId = const {},
    this.preferencesByUserId = const {},
    this.preferenceWeight = 0,
  });

  final List<Shift> openShifts;
  final List<AppUserProfile> members;
  final List<EmploymentContract> contracts;
  final List<EmployeeSiteAssignment> siteAssignments;

  /// Nur **genehmigte** Abwesenheiten (jede genehmigte Abwesenheit blockiert,
  /// inkl. Urlaub und Krankheit — Plan §8).
  final List<AbsenceRequest> approvedAbsences;

  /// Bereits besetzte Schichten im betroffenen Monat (deckt auch die ISO-Wochen
  /// ab) — Basis für Monats-/Wochen-Stundensummen, minRest und Doppelbelegung.
  final List<Shift> existingAssignedShifts;

  final List<ComplianceRuleSet> ruleSets;
  final List<TravelTimeRule> travelTimeRules;
  final ComplianceService complianceService;
  final OrgSettings settings;

  /// Optionale Sollzeit-Profile für Fairness-Zielstunden.
  final Map<String, SollzeitProfile> sollzeitByUserId;

  /// Schicht-Vorgaben je Mitarbeiter (uid → Vorgaben). `block`-Regeln wirken
  /// **hart** (wie Abwesenheit), `prefer`/`avoid` **weich** über
  /// [preferenceWeight]. Leer = kein Einfluss (Abwärtskompatibilität).
  final Map<String, EmployeeShiftPreference> preferencesByUserId;

  /// Gewicht der weichen Vorlieben (`prefer`/`avoid`) im Score. 0 = aus.
  /// Größenordnung wie die Monats-Fairness (~1,0), damit Vorlieben spürbar
  /// nudgen, aber Abdeckung/harte Regeln nie übersteuern.
  final double preferenceWeight;

  static const double _weightMonthlyFairness = 1.0;
  static const double _weightWeeklyFairness = 0.5;
  static const double _primaryBonus = 0.1;
  static const double _softCapPenaltyWeight = 5.0;
  static const double _hoursPerMonthFromWeek = 4.33;

  /// Max. Tiefe der Ejection-Chain (Schicht → verdränge Blocker → re-home …).
  /// 2 erlaubt Ketten der Länge 3 und genügt für Filialgrößen; höher ⇒ teurer.
  static const int _maxEjectionDepth = 2;

  /// Obergrenze der Steepest-Descent-Runden der Fairness-Lokalsuche (Konvergenz
  /// erfolgt typisch in wenigen Runden; Cap schützt vor Pathologien).
  static const int _maxFairnessRounds = 60;

  /// Ab so vielen mobilen Slots wird die **quadratische** Tausch-Nachbarschaft
  /// übersprungen (die lineare Verschiebung balanciert weiter). Schützt den
  /// UI-Thread bei sehr großen Monatsläufen; reale Filialgrößen liegen weit
  /// darunter.
  static const int _maxSwapShifts = 60;

  /// Verbesserungsschwelle der Lokalsuche (gegen Plateau-Oszillation).
  static const double _improveEpsilon = 1e-9;

  // ---- Vorberechnete, unveränderliche Indizes -------------------------------

  final Map<String, AppUserProfile> _memberById = {};
  final Map<String, EmployeeSiteAssignment> _assignmentByUserSite = {};
  final Map<String, int> _net = {}; // open shiftId -> Netto-Minuten
  final Map<String, Shift> _openById = {}; // open shiftId -> Original-Slot
  final Map<String, double> _monthlyTargetCache = {};
  final Map<String, double> _weeklyTargetCache = {};

  /// Monats-/Wochen-Buckets, die von den geplanten offenen Slots berührt werden.
  /// Die Fairness-Lokalsuche bewertet **genau** diese Buckets je Nutzer (auch
  /// mit 0 Minuten), damit die Kosten verlaufsunabhängig sind und ein leer
  /// stehender Mitarbeiter korrekt als „weit unter Soll" zählt.
  final Set<String> _horizonMonths = {};
  final Set<String> _horizonWeeks = {};
  late final DateTime _refDate;
  late final List<AppUserProfile> _activeMembers;

  // ---- Veränderlicher Arbeitszustand (während assign()) ---------------------

  /// Pro Nutzer: bestehende + virtuell zugewiesene Schichten (für Compliance,
  /// Doppelbelegung). Bestehende sind fix; offene sind über [_assignee] mobil.
  final Map<String, List<Shift>> _byUser = {};

  /// Pro Nutzer: Netto-Minuten je Monatslabel `y-m`.
  final Map<String, Map<String, int>> _monthMin = {};

  /// Pro Nutzer: Netto-Minuten je ISO-Wochenlabel (Montagsdatum).
  final Map<String, Map<String, int>> _weekMin = {};

  /// Offene Schicht-ID → aktuell zugewiesene uid (nur für **offene** Slots).
  final Map<String, String> _assignee = {};

  AutoAssignmentResult assign() {
    _setup();

    // Offene Slots ohne brauchbare ID/Standort sofort als unbesetzbar markieren.
    final hardUnassignable = <UnassignableShift>[];
    final planShifts = <Shift>[];
    for (final shift in openShifts) {
      final id = shift.id;
      if (id == null || id.trim().isEmpty) {
        continue; // ohne ID nicht referenzierbar (Preview/Apply mergen über id)
      }
      if (shift.siteId == null || shift.siteId!.trim().isEmpty) {
        hardUnassignable.add(UnassignableShift(
          shiftId: id,
          reason: UnassignableReason.site,
          message: 'Standort fehlt — keine automatische Zuweisung möglich.',
        ));
        continue;
      }
      planShifts.add(shift);
    }

    for (final shift in planShifts) {
      _horizonMonths.add(_monthLabel(shift.startTime));
      _horizonWeeks.add(_weekLabel(shift.startTime));
    }

    // Basis-Feasibility (gegen den Ausgangszustand, vor jeder Zuweisung) +
    // Ablehnungsgründe je grundsätzlich unbesetzbarer Schicht.
    final baseFeasible = <String, Set<String>>{};
    final baseFailReasons = <String, Set<UnassignableReason>>{};
    for (final shift in planShifts) {
      final id = shift.id!;
      final feasible = <String>{};
      final reasons = <UnassignableReason>{};
      for (final member in _activeMembers) {
        final reason = _hardFailure(shift, member);
        if (reason == null) {
          feasible.add(member.uid);
        } else {
          reasons.add(reason);
        }
      }
      baseFeasible[id] = feasible;
      baseFailReasons[id] = reasons;
    }

    // Deterministische Schicht-Reihenfolge (Basis für Tie-Breaks).
    final sortedShifts = [...planShifts]..sort(_shiftOrder);

    // Kandidaten-Schichten = grundsätzlich besetzbar (Basis-Feasible ≠ leer).
    final candidateShifts =
        sortedShifts.where((s) => baseFeasible[s.id!]!.isNotEmpty).toList();

    // Mutable Kandidatenmengen (monoton schrumpfend) für die Konstruktion.
    final candidates = <String, Set<String>>{
      for (final s in candidateShifts) s.id!: {...baseFeasible[s.id!]!},
    };

    _construct(candidateShifts, candidates);
    _augment(candidateShifts);
    _balanceFairness();

    return _buildResult(
      planShifts: planShifts,
      sortedShifts: sortedShifts,
      hardUnassignable: hardUnassignable,
      baseFeasible: baseFeasible,
      baseFailReasons: baseFailReasons,
    );
  }

  // ===========================================================================
  // Setup
  // ===========================================================================

  void _setup() {
    _activeMembers = members.where((m) => m.isActive).toList(growable: false);
    for (final m in _activeMembers) {
      _memberById[m.uid] = m;
    }
    for (final a in siteAssignments) {
      _assignmentByUserSite['${a.userId}|${a.siteId}'] = a;
    }
    for (final shift in openShifts) {
      final id = shift.id;
      if (id == null || id.trim().isEmpty) continue;
      _openById[id] = shift;
      _net[id] = _netMinutes(shift);
    }

    // Referenzdatum = frühester offener Slot (für Sollzeit-/Vertragsauswahl).
    DateTime? earliest;
    for (final shift in openShifts) {
      if (earliest == null || shift.startTime.isBefore(earliest)) {
        earliest = shift.startTime;
      }
    }
    _refDate = earliest ?? DateTime(2020, 1, 1);

    // Ausgangszustand aus bestehenden, besetzten Schichten aufbauen.
    for (final shift in existingAssignedShifts) {
      if (shift.isUnassigned) continue;
      (_byUser[shift.userId] ??= <Shift>[]).add(shift);
      _addMinutes(shift.userId, shift.startTime, _netMinutes(shift));
    }
  }

  // ===========================================================================
  // Phase 1 — MRV-Konstruktion
  // ===========================================================================

  void _construct(
    List<Shift> candidateShifts,
    Map<String, Set<String>> candidates,
  ) {
    final assigned = <String>{};
    while (true) {
      // Schicht mit den **wenigsten** verbleibenden Kandidaten wählen
      // (Most-Constrained-First). candidateShifts ist nach _shiftOrder
      // vorsortiert ⇒ erster Treffer gewinnt den Gleichstand deterministisch.
      Shift? target;
      var bestCount = 1 << 30;
      for (final s in candidateShifts) {
        final id = s.id!;
        if (assigned.contains(id)) continue;
        final c = candidates[id]!;
        if (c.isEmpty) continue;
        if (c.length < bestCount) {
          bestCount = c.length;
          target = s;
          if (bestCount == 1) break; // minimal — nicht weiter suchen
        }
      }
      if (target == null) break;
      final targetId = target.id!;

      // Bester Kandidat nach Score (Tie-Break: uid aufsteigend).
      AppUserProfile? winner;
      var bestScore = double.negativeInfinity;
      for (final uid in candidates[targetId]!.sorted((a, b) => a.compareTo(b))) {
        final member = _memberById[uid];
        if (member == null) continue;
        if (_hardFailure(target, member) != null) continue; // Sicherheits-Prune
        final score = _score(target, member);
        if (winner == null || score > bestScore) {
          bestScore = score;
          winner = member;
        }
      }

      if (winner == null) {
        // Alle (rest-)Kandidaten doch unzulässig → als Contention behandeln.
        candidates[targetId]!.clear();
        continue;
      }

      _apply(target, winner.uid);
      assigned.add(targetId);

      // Inkrementelles Prune: nur Schichten, deren Feasibility sich durch den
      // Gewinner ändern KANN (gleicher Monat oder ±2 Tage → Cap/Woche/Tag/Rest).
      for (final s in candidateShifts) {
        final id = s.id!;
        if (assigned.contains(id)) continue;
        final c = candidates[id]!;
        if (!c.contains(winner.uid)) continue;
        if (!_mayAffect(target, s)) continue;
        if (_hardFailure(s, winner) != null) {
          c.remove(winner.uid);
        }
      }
    }
  }

  // ===========================================================================
  // Phase 2 — Ejection-Chain-Augmentierung
  // ===========================================================================

  void _augment(List<Shift> candidateShifts) {
    for (final shift in candidateShifts) {
      if (_assignee.containsKey(shift.id!)) continue;
      _augmentShift(shift, <String>{}, _maxEjectionDepth);
    }
  }

  /// Versucht, [shift] (aktuell unbesetzt) zu besetzen — notfalls durch
  /// Verdrängung. Mutiert den Zustand **nur** bei Erfolg (Netto +1 Abdeckung);
  /// bei Misserfolg ist der Zustand unverändert (jede tentative Mutation wird
  /// auf dem Fehlerpfad zurückgerollt). [visited] verhindert Zyklen.
  bool _augmentShift(Shift shift, Set<String> visited, int depth) {
    for (final uid in _baseOrderedCandidates(shift)) {
      final member = _memberById[uid]!;

      // Direkt zuweisbar?
      if (_hardFailure(shift, member) == null) {
        _apply(shift, uid);
        return true;
      }
      if (depth <= 0) continue;

      // Einzel-Blocker-Verdrängung: einen mobilen offenen Slot dieses Nutzers
      // entfernen; passt [shift] dann, den verdrängten Slot neu unterbringen.
      final blockers = _movableOpenShiftsOf(uid)
          .where((b) => !visited.contains(b.id))
          .toList()
        ..sort(_shiftOrder);
      for (final blocker in blockers) {
        _unapply(blocker);
        if (_hardFailure(shift, member) == null) {
          _apply(shift, uid); // Slot für [member] reservieren …
          if (_augmentShift(blocker, {...visited, shift.id!}, depth - 1)) {
            return true; // … verdrängter Slot fand neues Zuhause.
          }
          _unapply(shift); // Reservierung zurücknehmen
        }
        _apply(blocker, uid); // Blocker bei [member] wiederherstellen
      }
    }
    return false;
  }

  // ===========================================================================
  // Phase 3 — Fairness-Lokalsuche (deterministisches Steepest-Descent)
  // ===========================================================================

  void _balanceFairness() {
    // Nur sinnvoll, wenn Zielzeiten ODER weiche Vorlieben existieren.
    final hasTargets = _activeMembers
        .any((m) => _monthlyTarget(m.uid) > 0 || _weeklyTarget(m.uid) > 0);
    final hasPreferences =
        preferenceWeight != 0 && preferencesByUserId.isNotEmpty;
    if (!hasTargets && !hasPreferences) return;

    for (var round = 0; round < _maxFairnessRounds; round++) {
      _FairnessMove? best;

      final movable = _assignee.keys.map((id) => _openById[id]!).toList()
        ..sort(_shiftOrder);

      // (a) Verschiebung: Slot von aktuellem Nutzer zu einem anderen geeigneten.
      for (final shift in movable) {
        final from = _assignee[shift.id!]!;
        for (final uid in _baseOrderedCandidates(shift)) {
          if (uid == from) continue;
          final to = _memberById[uid]!;
          final before = _userCost(from) +
              _userCost(uid) +
              _assignmentPrefCost(from, shift);
          _unapply(shift);
          final feasible = _hardFailure(shift, to) == null;
          if (feasible) {
            _apply(shift, uid);
            final delta = (_userCost(from) +
                    _userCost(uid) +
                    _assignmentPrefCost(uid, shift)) -
                before;
            if (delta < -_improveEpsilon &&
                (best == null || delta < best.delta)) {
              best = _FairnessMove.reassign(shift, from, uid, delta);
            }
            _unapply(shift);
          }
          _apply(shift, from); // Auswertungs-Zustand wiederherstellen
        }
      }

      // (b) Tausch: zwei Slots verschiedener Nutzer tauschen die Zuweisung
      // (löst Fälle, in denen keine einzelne Verschiebung zulässig ist).
      // Quadratisch → bei sehr großen Läufen übersprungen.
      for (var i = 0; movable.length <= _maxSwapShifts && i < movable.length; i++) {
        final s1 = movable[i];
        final a = _assignee[s1.id!]!;
        for (var j = i + 1; j < movable.length; j++) {
          final s2 = movable[j];
          final b = _assignee[s2.id!]!;
          if (a == b) continue;
          final before = _userCost(a) +
              _userCost(b) +
              _assignmentPrefCost(a, s1) +
              _assignmentPrefCost(b, s2);
          _unapply(s1);
          _unapply(s2);
          if (_hardFailure(s1, _memberById[b]!) == null) {
            _apply(s1, b);
            if (_hardFailure(s2, _memberById[a]!) == null) {
              _apply(s2, a);
              final delta = (_userCost(a) +
                      _userCost(b) +
                      _assignmentPrefCost(b, s1) +
                      _assignmentPrefCost(a, s2)) -
                  before;
              if (delta < -_improveEpsilon &&
                  (best == null || delta < best.delta)) {
                best = _FairnessMove.swap(s1, s2, a, b, delta);
              }
              _unapply(s2);
            }
            _unapply(s1);
          }
          // Ausgangszustand wiederherstellen (s1→a, s2→b).
          _apply(s1, a);
          _apply(s2, b);
        }
      }

      if (best == null) break; // konvergiert
      _applyMove(best);
    }
  }

  void _applyMove(_FairnessMove move) {
    if (move.isSwap) {
      _unapply(move.shift);
      _unapply(move.shift2!);
      _apply(move.shift, move.toUid); // s1 → b
      _apply(move.shift2!, move.fromUid); // s2 → a
    } else {
      _unapply(move.shift);
      _apply(move.shift, move.toUid);
    }
  }

  // ===========================================================================
  // Ergebnisaufbau
  // ===========================================================================

  AutoAssignmentResult _buildResult({
    required List<Shift> planShifts,
    required List<Shift> sortedShifts,
    required List<UnassignableShift> hardUnassignable,
    required Map<String, Set<String>> baseFeasible,
    required Map<String, Set<UnassignableReason>> baseFailReasons,
  }) {
    final assignments = <ShiftAssignmentProposal>[];
    final unassigned = <UnassignableShift>[...hardUnassignable];
    final warnings = <AssignmentWarning>[];

    for (final shift in sortedShifts) {
      final id = shift.id!;
      final uid = _assignee[id];
      if (uid != null) {
        final member = _memberById[uid]!;
        final monthKey = _monthLabel(shift.startTime);
        final weekKey = _weekLabel(shift.startTime);
        final plannedMonth = _monthMin[uid]?[monthKey] ?? 0;
        final plannedWeek = _weekMin[uid]?[weekKey] ?? 0;
        final assignment = _assignmentByUserSite['$uid|${shift.siteId}'];

        assignments.add(ShiftAssignmentProposal(
          shiftId: id,
          userId: uid,
          userName: member.displayName,
          score: _score(shift, member),
          reason: _proposalReason(
            assignment: assignment,
            projectedMonth: plannedMonth,
          ),
        ));

        // Soft-Cap-Warnung (nur weicher Modus, finale Projektion).
        if (!settings.enforceHourCapHard) {
          final contract = _activeContract(uid, shift.startTime);
          final exceedsMonthly = contract?.monthlyMaxHours != null &&
              plannedMonth > contract!.monthlyMaxHours! * 60;
          final exceedsWeekly = contract?.weeklyMaxHours != null &&
              plannedWeek > contract!.weeklyMaxHours! * 60;
          if (exceedsMonthly || exceedsWeekly) {
            warnings.add(AssignmentWarning(
              shiftId: id,
              userId: uid,
              userName: member.displayName,
              message: _softCapWarningText(
                member: member,
                exceedsMonthly: exceedsMonthly,
                exceedsWeekly: exceedsWeekly,
                projectedMonth: plannedMonth,
                projectedWeek: plannedWeek,
                contract: contract,
              ),
            ));
          }
        }
        continue;
      }

      // Unbesetzt → Grund bestimmen.
      final feasible = baseFeasible[id] ?? const <String>{};
      if (_activeMembers.isEmpty) {
        unassigned.add(UnassignableShift(
          shiftId: id,
          reason: UnassignableReason.noCandidates,
          message: _reasonMessage(UnassignableReason.noCandidates),
        ));
      } else if (feasible.isEmpty) {
        final reason = _aggregateReason(baseFailReasons[id] ?? const {});
        unassigned.add(UnassignableShift(
          shiftId: id,
          reason: reason,
          message: _reasonMessage(reason),
        ));
      } else {
        // Grundsätzlich besetzbar, aber durch Verdrängung nicht freizubekommen.
        unassigned.add(UnassignableShift(
          shiftId: id,
          reason: UnassignableReason.contention,
          message: _reasonMessage(UnassignableReason.contention),
        ));
      }
    }

    return AutoAssignmentResult(
      assignments: assignments,
      unassigned: unassigned,
      warnings: warnings,
    );
  }

  // ===========================================================================
  // Harte Constraints (Feasibility)
  // ===========================================================================

  /// Liefert den **ersten** harten Ablehnungsgrund für `(shift, member)` gegen
  /// den aktuellen Arbeitszustand, oder `null` wenn zulässig. Reihenfolge:
  /// günstige Checks zuerst, die teure Compliance zuletzt (Performance).
  UnassignableReason? _hardFailure(Shift shift, AppUserProfile member) {
    final uid = member.uid;

    // 1. Standort-Berechtigung.
    final assignment = _assignmentByUserSite['$uid|${shift.siteId}'];
    if (assignment == null) return UnassignableReason.site;

    // 2. Quali-Match (Schichtanforderungen ⊆ Qualis der Standortzuordnung).
    for (final qId in shift.requiredQualificationIds) {
      if (!assignment.qualificationIds.contains(qId)) {
        return UnassignableReason.qualification;
      }
    }

    // 3. Abwesenheit (jede genehmigte Abwesenheit blockiert).
    for (final absence in approvedAbsences) {
      if (absence.userId == uid &&
          absence.status == AbsenceStatus.approved &&
          absence.overlaps(shift.startTime, shift.endTime)) {
        return UnassignableReason.absence;
      }
    }

    // 3b. Harte Vorgabe-Sperre (`PreferenceKind.block`) — wie Abwesenheit.
    final preference = preferencesByUserId[uid];
    if (preference != null && preference.isNotEmpty) {
      final window = _shiftDayWindow(shift);
      if (preference.isBlocked(window.weekday, window.start, window.end)) {
        return UnassignableReason.preferenceBlock;
      }
    }

    // 4. Doppelbelegung (günstiger Overlap-Scan vor der teuren Compliance).
    final userShifts = _byUser[uid] ?? const <Shift>[];
    for (final existing in userShifts) {
      if (existing.startTime.isBefore(shift.endTime) &&
          existing.endTime.isAfter(shift.startTime)) {
        return UnassignableReason.doubleBooking;
      }
    }

    final net = _net[shift.id] ?? _netMinutes(shift);
    final contract = _activeContract(uid, shift.startTime);
    final plannedMonth = _monthMin[uid]?[_monthLabel(shift.startTime)] ?? 0;
    final plannedWeek = _weekMin[uid]?[_weekLabel(shift.startTime)] ?? 0;
    final projectedMonth = plannedMonth + net;
    final projectedWeek = plannedWeek + net;

    // 5./6. Stundengrenzen (nur im harten Modus → Filter).
    if (settings.enforceHourCapHard) {
      if (contract?.monthlyMaxHours != null &&
          projectedMonth > contract!.monthlyMaxHours! * 60) {
        return UnassignableReason.monthlyCap;
      }
      if (contract?.weeklyMaxHours != null &&
          projectedWeek > contract!.weeklyMaxHours! * 60) {
        return UnassignableReason.weeklyCap;
      }
    }

    // 7. Minijob-Verdienstgrenze (IMMER hart, unabhängig von enforceHourCapHard).
    if (contract != null &&
        contract.type == EmploymentType.miniJob &&
        contract.hourlyRate > 0) {
      final ruleSet = complianceService.resolveRuleSet(
        ruleSets: ruleSets,
        siteId: shift.siteId,
        contract: contract,
      );
      final limitCents =
          contract.monthlyIncomeLimitCents ?? ruleSet.minijobMonthlyLimitCents;
      final projectedCents =
          ((projectedMonth / 60) * contract.hourlyRate * 100).round();
      if (projectedCents > limitCents) {
        return UnassignableReason.minijob;
      }
    }

    // 8. Compliance (autoritativ für Rest/Tageslimit/Pausen/Nacht; teuer).
    final candidateShift =
        shift.copyWith(userId: uid, employeeName: member.displayName);
    final violations = complianceService.validateShift(
      shift: candidateShift,
      existingShifts: userShifts,
      draftShifts: const [],
      absences: approvedAbsences,
      contracts: contracts,
      siteAssignments: siteAssignments,
      ruleSets: ruleSets,
      travelTimeRules: travelTimeRules,
      members: members,
    );
    final blocking =
        violations.any((v) => v.severity == ComplianceSeverity.blocking);
    if (blocking) return UnassignableReason.compliance;

    return null;
  }

  // ===========================================================================
  // Scoring (weiche Ziele) — Fairness Richtung Sollzeit
  // ===========================================================================

  double _score(Shift shift, AppUserProfile member) {
    final uid = member.uid;
    final net = _net[shift.id] ?? _netMinutes(shift);
    final plannedMonth = _monthMin[uid]?[_monthLabel(shift.startTime)] ?? 0;
    final plannedWeek = _weekMin[uid]?[_weekLabel(shift.startTime)] ?? 0;

    var score = 0.0;
    final monthlyTarget = _monthlyTarget(uid);
    if (monthlyTarget > 0) {
      score +=
          _weightMonthlyFairness * ((monthlyTarget - plannedMonth) / monthlyTarget);
    }
    final weeklyTarget = _weeklyTarget(uid);
    if (weeklyTarget > 0) {
      score +=
          _weightWeeklyFairness * ((weeklyTarget - plannedWeek) / weeklyTarget);
    }

    final assignment = _assignmentByUserSite['$uid|${shift.siteId}'];
    if (assignment?.isPrimary == true) {
      score += _primaryBonus;
    }

    // Weiche Vorlieben (prefer/avoid): positiv hebt, negativ senkt den Score.
    if (preferenceWeight != 0) {
      score += preferenceWeight * _prefScore(uid, shift);
    }

    if (!settings.enforceHourCapHard) {
      final contract = _activeContract(uid, shift.startTime);
      final exceedsMonthly = contract?.monthlyMaxHours != null &&
          (plannedMonth + net) > contract!.monthlyMaxHours! * 60;
      final exceedsWeekly = contract?.weeklyMaxHours != null &&
          (plannedWeek + net) > contract!.weeklyMaxHours! * 60;
      if (exceedsMonthly && monthlyTarget > 0) {
        final overage = (plannedMonth + net) - monthlyTarget;
        score -= _softCapPenaltyWeight * (overage / monthlyTarget);
      }
      if (exceedsWeekly && weeklyTarget > 0) {
        final overage = (plannedWeek + net) - weeklyTarget;
        score -= _softCapPenaltyWeight * (overage / weeklyTarget);
      }
    }

    return score;
  }

  /// Fairness-Kosten eines Nutzers = gewichtete Summe der quadratischen
  /// relativen Abweichung von Monats-/Wochen-Sollzeit über die **fixen**
  /// Horizont-Buckets ([_horizonMonths]/[_horizonWeeks], 0-Minuten inklusive).
  /// Verlaufsunabhängig → konsistente Δ-Vergleiche in der Lokalsuche.
  double _userCost(String uid) {
    var cost = 0.0;
    final monthlyTarget = _monthlyTarget(uid);
    if (monthlyTarget > 0) {
      final buckets = _monthMin[uid];
      for (final label in _horizonMonths) {
        final mins = buckets?[label] ?? 0;
        final d = (mins - monthlyTarget) / monthlyTarget;
        cost += _weightMonthlyFairness * d * d;
      }
    }
    final weeklyTarget = _weeklyTarget(uid);
    if (weeklyTarget > 0) {
      final buckets = _weekMin[uid];
      for (final label in _horizonWeeks) {
        final mins = buckets?[label] ?? 0;
        final d = (mins - weeklyTarget) / weeklyTarget;
        cost += _weightWeeklyFairness * d * d;
      }
    }
    return cost;
  }

  // ===========================================================================
  // Schicht-Vorlieben (weich)
  // ===========================================================================

  /// Wochentag (1–7) + Tages-Minutenfenster `[start, end)` einer Schicht für die
  /// Vorgaben-Auswertung. `end` kann > 1440 sein (Schicht über Mitternacht);
  /// die Überlappung mit Regelfenstern (≤ 1440) bleibt korrekt.
  ({int weekday, int start, int end}) _shiftDayWindow(Shift shift) {
    final s = shift.startTime;
    final start = s.hour * 60 + s.minute;
    final duration = shift.endTime.difference(shift.startTime).inMinutes;
    return (weekday: s.weekday, start: start, end: start + duration);
  }

  /// Weicher Vorlieben-Score der Schicht für [uid] in [-1, 1] (0 ohne Vorgabe).
  double _prefScore(String uid, Shift shift) {
    final preference = preferencesByUserId[uid];
    if (preference == null || preference.isEmpty) return 0;
    final w = _shiftDayWindow(shift);
    return preference.softScore(w.weekday, w.start, w.end);
  }

  /// Vorlieben-Kostenbeitrag einer Zuweisung für die Lokalsuche (niedriger =
  /// besser): bevorzugte Slots senken, gemiedene erhöhen die Kosten.
  double _assignmentPrefCost(String uid, Shift shift) {
    if (preferenceWeight == 0) return 0;
    return -preferenceWeight * _prefScore(uid, shift);
  }

  // ===========================================================================
  // Zustands-Mutation (apply/unapply offener Slots)
  // ===========================================================================

  void _apply(Shift openShift, String uid) {
    final member = _memberById[uid]!;
    final placed =
        openShift.copyWith(userId: uid, employeeName: member.displayName);
    (_byUser[uid] ??= <Shift>[]).add(placed);
    _addMinutes(uid, openShift.startTime, _net[openShift.id]!);
    _assignee[openShift.id!] = uid;
  }

  void _unapply(Shift openShift) {
    final uid = _assignee.remove(openShift.id);
    if (uid == null) return;
    _byUser[uid]?.removeWhere((s) => s.id == openShift.id);
    _addMinutes(uid, openShift.startTime, -_net[openShift.id]!);
  }

  void _addMinutes(String uid, DateTime date, int delta) {
    final monthKey = _monthLabel(date);
    final weekKey = _weekLabel(date);
    final monthMap = _monthMin[uid] ??= <String, int>{};
    monthMap[monthKey] = (monthMap[monthKey] ?? 0) + delta;
    final weekMap = _weekMin[uid] ??= <String, int>{};
    weekMap[weekKey] = (weekMap[weekKey] ?? 0) + delta;
  }

  List<Shift> _movableOpenShiftsOf(String uid) {
    final result = <Shift>[];
    _assignee.forEach((shiftId, assignedUid) {
      if (assignedUid == uid) {
        final s = _openById[shiftId];
        if (s != null) result.add(s);
      }
    });
    return result;
  }

  /// Mitglieder, die [shift] **grundsätzlich** (gegen den Ausgangszustand)
  /// übernehmen könnten, in deterministischer uid-Reihenfolge. Da Feasibility
  /// monoton mit Zuweisungen schrumpft, ist dies die obere Schranke der je
  /// zulässigen Kandidaten — Ejection/Lokalsuche müssen nie darüber hinaus.
  List<String> _baseOrderedCandidates(Shift shift) {
    final result = [for (final m in _activeMembers) m.uid]
      ..sort((a, b) => a.compareTo(b));
    // Auf die zur Basiszeit zulässigen filtern wäre exakter; da der Aufrufer
    // ohnehin _hardFailure prüft, genügt die uid-sortierte Aktivliste. Wir
    // filtern dennoch grob auf Standort/Quali (billig, unveränderlich), um die
    // teure Compliance-Schleife klein zu halten.
    return result
        .where((uid) => _staticallyEligible(shift, _memberById[uid]!))
        .toList(growable: false);
  }

  /// Unveränderliche, billige Eignung (Standort + Quali) — ändert sich nie durch
  /// Zuweisungen, daher als Vorfilter für Ejection/Lokalsuche nutzbar.
  bool _staticallyEligible(Shift shift, AppUserProfile member) {
    final assignment = _assignmentByUserSite['${member.uid}|${shift.siteId}'];
    if (assignment == null) return false;
    for (final qId in shift.requiredQualificationIds) {
      if (!assignment.qualificationIds.contains(qId)) return false;
    }
    return true;
  }

  /// Kann eine Zuweisung von [a] die Feasibility eines Nutzers für [b] ändern?
  /// Nur bei zeitlicher Nähe: gleicher Monat (Cap/Woche/Tag/Minijob) oder ±2
  /// Tage (Overlap/Rest, auch über Monatsgrenzen).
  bool _mayAffect(Shift a, Shift b) {
    if (_monthLabel(a.startTime) == _monthLabel(b.startTime)) return true;
    final dayA = DateTime(a.startTime.year, a.startTime.month, a.startTime.day);
    final dayB = DateTime(b.startTime.year, b.startTime.month, b.startTime.day);
    return dayA.difference(dayB).inDays.abs() <= 2;
  }

  // ===========================================================================
  // Ziel-/Vertrags-Helfer (gecacht)
  // ===========================================================================

  double _monthlyTarget(String uid) =>
      _monthlyTargetCache[uid] ??= _computeMonthlyTarget(uid);

  double _weeklyTarget(String uid) =>
      _weeklyTargetCache[uid] ??= _computeWeeklyTarget(uid);

  /// Monats-Zielminuten: `monthlyMaxHours` → Sollzeit-Monatssoll →
  /// `weeklyHours × 4,33` (Plan §13.5). 0 = neutral.
  double _computeMonthlyTarget(String uid) {
    final contract = _activeContract(uid, _refDate);
    if (contract?.monthlyMaxHours != null) {
      return contract!.monthlyMaxHours! * 60;
    }
    final sollzeit = sollzeitByUserId[uid];
    if (sollzeit != null) {
      if (sollzeit.isMonatsarbeitszeit &&
          sollzeit.monatsarbeitszeitMinutes != null &&
          sollzeit.monatsarbeitszeitMinutes! > 0) {
        return sollzeit.monatsarbeitszeitMinutes!.toDouble();
      }
      if (sollzeit.wochensollMinutes > 0) {
        return sollzeit.wochensollMinutes * _hoursPerMonthFromWeek;
      }
    }
    if (contract != null && contract.weeklyHours > 0) {
      return contract.weeklyHours * 60 * _hoursPerMonthFromWeek;
    }
    return 0;
  }

  /// Wochen-Zielminuten: `weeklyMaxHours` → Sollzeit-Wochensoll → `weeklyHours`.
  double _computeWeeklyTarget(String uid) {
    final contract = _activeContract(uid, _refDate);
    if (contract?.weeklyMaxHours != null) {
      return contract!.weeklyMaxHours! * 60;
    }
    final sollzeit = sollzeitByUserId[uid];
    if (sollzeit != null && sollzeit.wochensollMinutes > 0) {
      return sollzeit.wochensollMinutes.toDouble();
    }
    if (contract != null && contract.weeklyHours > 0) {
      return contract.weeklyHours * 60;
    }
    return 0;
  }

  EmploymentContract? _activeContract(String userId, DateTime at) {
    return contracts
        .where((c) => c.userId == userId && c.isActiveOn(at))
        .sorted((a, b) => b.validFrom.compareTo(a.validFrom))
        .firstOrNull;
  }

  // ===========================================================================
  // Reason-/Text-Helfer
  // ===========================================================================

  /// Aggregiert die häufigsten Ablehnungsgründe nach Priorität (Plan §6.3b):
  /// Quali → Standort → Cap/Minijob → Abwesenheit → Doppelbelegung →
  /// Compliance.
  UnassignableReason _aggregateReason(Set<UnassignableReason> failures) {
    const priority = [
      UnassignableReason.qualification,
      UnassignableReason.site,
      UnassignableReason.monthlyCap,
      UnassignableReason.weeklyCap,
      UnassignableReason.minijob,
      UnassignableReason.absence,
      UnassignableReason.preferenceBlock,
      UnassignableReason.doubleBooking,
      UnassignableReason.compliance,
    ];
    for (final reason in priority) {
      if (failures.contains(reason)) {
        return reason;
      }
    }
    return UnassignableReason.noCandidates;
  }

  String _reasonMessage(UnassignableReason reason) {
    switch (reason) {
      case UnassignableReason.qualification:
        return 'Keine passende Qualifikation verfügbar.';
      case UnassignableReason.site:
        return 'Kein für den Standort berechtigter Mitarbeiter verfügbar.';
      case UnassignableReason.monthlyCap:
        return 'Monatsgrenze aller Kandidaten erreicht.';
      case UnassignableReason.weeklyCap:
        return 'Wochengrenze aller Kandidaten erreicht.';
      case UnassignableReason.minijob:
        return 'Minijob-Verdienstgrenze würde überschritten.';
      case UnassignableReason.absence:
        return 'Verfügbare Mitarbeiter sind abwesend (Urlaub/Krankheit).';
      case UnassignableReason.doubleBooking:
        return 'Mitarbeiter sind in dieser Zeit bereits eingeplant.';
      case UnassignableReason.compliance:
        return 'Arbeitszeit-Regeln verhindern eine Zuweisung.';
      case UnassignableReason.preferenceBlock:
        return 'Verfügbare Mitarbeiter haben diese Zeit gesperrt.';
      case UnassignableReason.contention:
        return 'Alle geeigneten Mitarbeiter sind in dieser Zeit bereits '
            'verplant — nicht ohne Umbuchung lösbar.';
      case UnassignableReason.noCandidates:
        return 'Keine verfügbaren Mitarbeiter.';
    }
  }

  String _proposalReason({
    required EmployeeSiteAssignment? assignment,
    required int projectedMonth,
  }) {
    final hours = (projectedMonth / 60).toStringAsFixed(1).replaceAll('.', ',');
    final base = 'Auslastung ca. $hours h/Monat';
    return assignment?.isPrimary == true ? '$base, Primärstandort' : base;
  }

  String _softCapWarningText({
    required AppUserProfile member,
    required bool exceedsMonthly,
    required bool exceedsWeekly,
    required int projectedMonth,
    required int projectedWeek,
    required EmploymentContract? contract,
  }) {
    final parts = <String>[];
    if (exceedsMonthly && contract?.monthlyMaxHours != null) {
      parts.add(
          'Monat ${_h(projectedMonth)}/${_hHours(contract!.monthlyMaxHours!)} h');
    }
    if (exceedsWeekly && contract?.weeklyMaxHours != null) {
      parts.add(
          'Woche ${_h(projectedWeek)}/${_hHours(contract!.weeklyMaxHours!)} h');
    }
    return '${member.displayName} über Grenze: ${parts.join(', ')}';
  }

  String _h(int minutes) =>
      (minutes / 60).toStringAsFixed(1).replaceAll('.', ',');

  String _hHours(double hours) =>
      hours.toStringAsFixed(1).replaceAll('.', ',');

  int _netMinutes(Shift shift) =>
      shift.endTime.difference(shift.startTime).inMinutes -
      shift.breakMinutes.round();

  int _shiftOrder(Shift a, Shift b) {
    final byStart = a.startTime.compareTo(b.startTime);
    if (byStart != 0) return byStart;
    final bySite = (a.siteId ?? '').compareTo(b.siteId ?? '');
    if (bySite != 0) return bySite;
    return (a.id ?? '').compareTo(b.id ?? '');
  }

  String _monthLabel(DateTime date) => '${date.year}-${date.month}';

  /// ISO-Wochen-Bucket = Montag-Datum der Woche (deterministisch, ohne
  /// ISO-Wochennummern-Sonderfälle).
  String _weekLabel(DateTime date) {
    final monday = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }
}

/// Eine angenommene Fairness-Verbesserung (Verschiebung oder Tausch).
class _FairnessMove {
  const _FairnessMove._({
    required this.shift,
    required this.shift2,
    required this.fromUid,
    required this.toUid,
    required this.delta,
    required this.isSwap,
  });

  factory _FairnessMove.reassign(
    Shift shift,
    String fromUid,
    String toUid,
    double delta,
  ) =>
      _FairnessMove._(
        shift: shift,
        shift2: null,
        fromUid: fromUid,
        toUid: toUid,
        delta: delta,
        isSwap: false,
      );

  /// Tausch: [shift] (bei [fromUid]=a) und [shift2] (bei [toUid]=b) tauschen die
  /// Zuweisung → shift→b, shift2→a.
  factory _FairnessMove.swap(
    Shift shift,
    Shift shift2,
    String a,
    String b,
    double delta,
  ) =>
      _FairnessMove._(
        shift: shift,
        shift2: shift2,
        fromUid: a,
        toUid: b,
        delta: delta,
        isSwap: true,
      );

  final Shift shift;
  final Shift? shift2;
  final String fromUid;
  final String toUid;
  final double delta;
  final bool isSwap;
}
