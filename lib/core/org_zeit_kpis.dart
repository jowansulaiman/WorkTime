// lib/core/org_zeit_kpis.dart

import '../models/absence_request.dart';
import '../models/sollzeit_profile.dart';
import '../models/work_entry.dart';
import '../models/zeitkonto_snapshot.dart';
import 'zeitkonto_snapshot_builder.dart';

/// Org-weite Zeit-Kennzahlen eines Monats (REPORTING-2) — Ergebnis von
/// [computeOrgZeitKpis]. Alle Zeitwerte in Minuten.
///
/// `urlaubOffen` ist BEWUSST NICHT enthalten (Prüf-Befund: Quelle offener
/// Urlaubsanträge ist der `ScheduleProvider`/REPORTING-3, nicht diese Engine).
class OrgZeitKpis {
  const OrgZeitKpis({
    this.sollMinutes = 0,
    this.istMinutes = 0,
    this.saldoMinutes = 0,
    this.mitarbeiterMitSoll = 0,
    this.offeneFreigaben = 0,
    this.offeneEntwuerfe = 0,
  });

  /// Summe der Monatssolls aller betrachteten Mitglieder.
  final int sollMinutes;

  /// Summe des **bindenden** Ist (E3: nur `approved`, inkl. angerechneter
  /// bezahlter Abwesenheiten) aller betrachteten Mitglieder.
  final int istMinutes;

  /// Summe der kumulierten Salden (inkl. Übertrag/Auszahlung/Zeitausgleich).
  final int saldoMinutes;

  /// Anzahl Mitglieder mit hinterlegtem Monatssoll (> 0 Minuten).
  final int mitarbeiterMitSoll;

  /// Zeiteinträge des Monats mit Status `submitted` („warten auf Freigabe") —
  /// **separater Zähler**, zählt NICHT in [istMinutes] (E3).
  final int offeneFreigaben;

  /// Zeiteinträge des Monats mit Status `draft` — separater Zähler wie
  /// [offeneFreigaben].
  final int offeneEntwuerfe;

  double get sollHours => sollMinutes / 60.0;
  double get istHours => istMinutes / 60.0;
  double get saldoHours => saldoMinutes / 60.0;
}

/// Berechnet die org-weiten Zeit-Kennzahlen eines Monats — **pure**,
/// deterministisch, offline testbar (kein State/IO/`now()`).
///
/// Intern läuft je Mitglied [buildZeitkontoSnapshot] (und darüber
/// `computeZeitkonto`): die **E3-Invariante** (bindendes Ist = nur `approved`)
/// wird hier bewusst NICHT neu implementiert — `submitted`/`draft` fließen nur
/// in die separaten Zähler [OrgZeitKpis.offeneFreigaben] /
/// [OrgZeitKpis.offeneEntwuerfe].
///
/// **Snapshot-Konsistenz-Regel:** Für ein Mitglied, dessen Monat per
/// Monatsabschluss festgeschrieben ist ([ZeitkontoSnapshot.abgeschlossen] in
/// [currentMonthSnapshots]), **gewinnt der persistierte Snapshot** — der
/// Report darf dem festgeschriebenen Abschluss nicht widersprechen. Nur für
/// offene Monate/Mitglieder wird live gerechnet; dabei wird
/// `ausgezahltMinutes` eines (noch nicht gesperrten) persistierten Snapshots
/// **durchgereicht** (Auszahlungen senken den Saldo auch vor dem Abschluss —
/// gleiches Muster wie der Mitarbeiterabschluss-Hub).
///
/// - [memberIds]: die zu aggregierenden Mitglieder (i. d. R. alle aktiven);
///   Duplikate werden ignoriert. Soll/Ist/Saldo/mitarbeiterMitSoll zählen NUR
///   über diese Menge.
/// - [profilesByUser]: Sollzeit-Profile je Mitglied (gültig-ab-versioniert);
///   fehlender Eintrag = kein Soll hinterlegt.
/// - [entries]/[approvedAbsences]: org-weite Monatsdaten; werden intern je
///   Mitglied gefiltert (Monatsfilterung übernehmen die Builder selbst).
///   Die Zähler [OrgZeitKpis.offeneFreigaben]/[OrgZeitKpis.offeneEntwuerfe]
///   zählen über ALLE übergebenen Einträge des Monats (Arbeitsvorrat der
///   Freigeber), unabhängig von [memberIds].
/// - [previousMonthSnapshots]: Vormonats-Snapshots als Übertragsquelle der
///   Live-Berechnung.
OrgZeitKpis computeOrgZeitKpis({
  required String orgId,
  required int jahr,
  required int monat,
  required List<String> memberIds,
  required Map<String, List<SollzeitProfile>> profilesByUser,
  required List<WorkEntry> entries,
  required List<AbsenceRequest> approvedAbsences,
  required List<ZeitkontoSnapshot> currentMonthSnapshots,
  List<ZeitkontoSnapshot> previousMonthSnapshots = const [],
}) {
  ZeitkontoSnapshot? snapshotFor(
      List<ZeitkontoSnapshot> snapshots, String userId) {
    for (final s in snapshots) {
      if (s.userId == userId) return s;
    }
    return null;
  }

  var soll = 0;
  var ist = 0;
  var saldo = 0;
  var mitSoll = 0;

  for (final userId in {...memberIds}) {
    final persisted = snapshotFor(currentMonthSnapshots, userId);
    final ZeitkontoSnapshot effective;
    if (persisted != null && persisted.abgeschlossen) {
      // Festgeschriebener Monat: der persistierte Snapshot gewinnt.
      effective = persisted;
    } else {
      effective = buildZeitkontoSnapshot(
        orgId: orgId,
        userId: userId,
        jahr: jahr,
        monat: monat,
        profiles: profilesByUser[userId] ?? const [],
        entries: [
          for (final e in entries)
            if (e.userId == userId) e,
        ],
        approvedAbsences: [
          for (final a in approvedAbsences)
            if (a.userId == userId) a,
        ],
        previous: snapshotFor(previousMonthSnapshots, userId),
        ausgezahltMinutes: persisted?.ausgezahltMinutes ?? 0,
      );
    }
    soll += effective.sollMinutes;
    ist += effective.istMinutes;
    saldo += effective.saldoMinutes;
    if (effective.sollMinutes > 0) {
      mitSoll++;
    }
  }

  var offeneFreigaben = 0;
  var offeneEntwuerfe = 0;
  for (final entry in entries) {
    // Robustheit: nur Einträge des Zielmonats zählen, auch wenn der Aufrufer
    // eine breitere Liste übergibt.
    if (entry.date.year != jahr || entry.date.month != monat) continue;
    if (entry.status == WorkEntryStatus.submitted) {
      offeneFreigaben++;
    } else if (entry.status == WorkEntryStatus.draft) {
      offeneEntwuerfe++;
    }
  }

  return OrgZeitKpis(
    sollMinutes: soll,
    istMinutes: ist,
    saldoMinutes: saldo,
    mitarbeiterMitSoll: mitSoll,
    offeneFreigaben: offeneFreigaben,
    offeneEntwuerfe: offeneEntwuerfe,
  );
}
