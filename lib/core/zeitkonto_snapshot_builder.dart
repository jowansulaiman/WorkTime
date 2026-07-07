// lib/core/zeitkonto_snapshot_builder.dart

import '../models/absence_request.dart';
import '../models/shift.dart';
import '../models/sollzeit_profile.dart';
import '../models/work_entry.dart';
import '../models/zeitkonto_snapshot.dart';
import 'abwesenheit_matrix.dart';
import 'zeitkonto_calculator.dart';

/// Baut einen [ZeitkontoSnapshot] für einen Monat (AllTec `HourAccountService`,
/// M4) — **pure**, deterministisch, offline testbar (kein State/IO/`now()`).
///
/// Erweitert [computeZeitkonto] (Soll aus [SollzeitProfile], Ist aus [WorkEntry])
/// um die **Abwesenheits-Anrechnung** ins Ist (bezahlte/soll-angerechnete Tage via
/// [abwesenheitsMatrix], damit z. B. ein Krankheitstag das Stundenkonto nicht ins
/// Minus zieht), den **Übertrag** aus dem Vormonats-Snapshot, **Auszahlung** und
/// den kumulierten **Saldo**.
ZeitkontoSnapshot buildZeitkontoSnapshot({
  required String orgId,
  required String userId,
  required int jahr,
  required int monat,
  required List<SollzeitProfile> profiles,
  required List<WorkEntry> entries,
  required List<AbsenceRequest> approvedAbsences,
  ZeitkontoSnapshot? previous,
  int ausgezahltMinutes = 0,
  double urlaubstageGesamt = 0,
  double urlaubstageGenommen = 0,
  int plannedMinutes = 0,
}) {
  final base = computeZeitkonto(
    year: jahr,
    month: monat,
    profiles: profiles,
    entries: entries,
  );
  final anrechnung = anrechenbareAbwesenheitsMinutes(
    profiles: profiles,
    absences: approvedAbsences,
    jahr: jahr,
    monat: monat,
  );
  final istMinutes = base.istMinutes + anrechnung;
  final sollMinutes = base.sollMinutes;
  final ueberstunden = istMinutes - sollMinutes;
  final uebertrag = previous?.saldoMinutes ?? 0;
  // Zeitausgleich („Überstunden abfeiern") wird aus dem angesparten Saldo
  // bezahlt und muss ihn deshalb SENKEN. `timeOff` bleibt bewusst in [anrechnung]
  // (Ist-Gutschrift) — das hält den Zeitausgleichstag im Plus-Minus-Null und die
  // Lohn-Grundlage [istMinutes] unverändert. Ohne den folgenden Abzug bliebe der
  // Saldo beim Abfeiern aber fälschlich konstant (Review-Befund #15).
  final zeitausgleich = zeitausgleichSaldoMinutes(
    profiles: profiles,
    absences: approvedAbsences,
    jahr: jahr,
    monat: monat,
  );
  final saldo = uebertrag + ueberstunden - ausgezahltMinutes - zeitausgleich;
  final kranktage = krankTageImMonat(
    absences: approvedAbsences,
    jahr: jahr,
    monat: monat,
  );

  return ZeitkontoSnapshot(
    orgId: orgId,
    userId: userId,
    jahr: jahr,
    monat: monat,
    sollMinutes: sollMinutes,
    istMinutes: istMinutes,
    ueberstundenMinutes: ueberstunden,
    ausgezahltMinutes: ausgezahltMinutes,
    uebertragMinutes: uebertrag,
    saldoMinutes: saldo,
    geplantMinutes: plannedMinutes,
    urlaubstageGesamt: urlaubstageGesamt,
    urlaubstageGenommen: urlaubstageGenommen,
    urlaubstageRest: urlaubstageGesamt - urlaubstageGenommen,
    kranktage: kranktage,
  );
}

/// Z9/E6: Planzeit (Minuten) eines Mitarbeiters im Monat — Summe der
/// zugewiesenen Schicht-Netto-Zeiten (`Shift.workedHours`), ohne `cancelled`
/// und ohne unassigned. **Pure**, offline testbar. Rein anzeigend (fließt NICHT
/// in Saldo/Ist). Eine Schicht zählt zum Monat ihres `startTime`.
int plannedMinutesForMonth({
  required List<Shift> shifts,
  required String userId,
  required int jahr,
  required int monat,
}) {
  var minutes = 0.0;
  for (final shift in shifts) {
    if (shift.userId != userId) continue;
    if (shift.status == ShiftStatus.cancelled || shift.isUnassigned) continue;
    if (shift.startTime.year != jahr || shift.startTime.month != monat) {
      continue;
    }
    minutes += shift.workedHours * 60.0;
  }
  return minutes.round();
}

/// EFZG § 3: Entgeltfortzahlung im Krankheitsfall ist auf **6 Wochen
/// (42 Kalendertage je Erkrankung)** begrenzt. Danach zahlt die Krankenkasse
/// Krankengeld; der Arbeitgeber rechnet die Tage NICHT mehr als Soll an.
const int efzgEntgeltfortzahlungTage = 42;

/// Summe der Soll-Minuten, die durch **genehmigte, soll-angerechnete**
/// Abwesenheiten (z. B. Urlaub/Krankheit) im Monat als Ist gutgeschrieben werden.
/// Zählt nur echte Arbeitstage (Tagessoll > 0); halbtägig → halbes Tagessoll.
///
/// **EFZG-Kappung:** Krankheit (`sickness`) wird nur für die ersten
/// [efzgEntgeltfortzahlungTage] Kalendertage **ab Antragsbeginn** angerechnet
/// (Entgeltfortzahlung, § 3 EFZG) — länger andauernde Krankheit ist ab Tag 43
/// Krankengeld-Sache und wird nicht mehr als Soll gutgeschrieben. Über mehrere
/// Anträge verteilte **Fortsetzungserkrankungen** lassen sich ohne Diagnose-
/// Identität nicht verketten → konservativ je Antrag gekappt. `childSick`
/// (Kinderkrankengeld § 45 SGB V) ist ein anderes Verfahren und bleibt ungekappt.
int anrechenbareAbwesenheitsMinutes({
  required List<SollzeitProfile> profiles,
  required List<AbsenceRequest> absences,
  required int jahr,
  required int monat,
}) {
  final sorted = [...profiles]
    ..sort((a, b) => b.gueltigAb.compareTo(a.gueltigAb));
  SollzeitProfile? activeOn(DateTime day) {
    for (final p in sorted) {
      if (p.isEffectiveOn(day)) return p;
    }
    return null;
  }

  final first = DateTime(jahr, monat, 1);
  final last = DateTime(jahr, monat + 1, 0);
  var minutes = 0;
  for (final absence in absences) {
    if (absence.status != AbsenceStatus.approved) continue;
    final regel = abwesenheitsMatrix[absence.type];
    if (regel == null || !regel.alsSollAngerechnet) continue;
    // Letzter EFZG-anrechenbarer Kalendertag bei Krankheit (sonst null = ohne Cap).
    final efzgLastDay = absence.type == AbsenceType.sickness
        ? absence.startDate
            .add(const Duration(days: efzgEntgeltfortzahlungTage - 1))
        : null;
    for (var day = absence.startDate;
        !day.isAfter(absence.endDate);
        day = day.add(const Duration(days: 1))) {
      if (day.isBefore(first) || day.isAfter(last)) continue;
      if (efzgLastDay != null && day.isAfter(efzgLastDay)) {
        continue; // EFZG-Kappung: ab Tag 43 keine Entgeltfortzahlung mehr
      }
      final profile = activeOn(day);
      if (profile == null) continue;
      final soll = profile.sollMinutesForWeekday(day.weekday);
      if (soll <= 0) continue; // kein Arbeitstag (z. B. Wochenende)
      minutes += absence.halfDay ? (soll / 2).round() : soll;
    }
  }
  return minutes;
}

/// Minuten, die **Zeitausgleich** ([AbsenceType.timeOff], „Überstunden
/// abfeiern") in diesem Monat vom Stundenkonto-**Saldo** abzieht.
///
/// Zeitausgleich wird — anders als Urlaub/Krankheit — aus dem angesparten Saldo
/// bezahlt: der freie Tag muss den Saldo senken, statt ihn unverändert zu lassen.
///
/// Der Betrag entspricht **exakt** der Ist-Gutschrift, die [AbsenceType.timeOff]
/// über [anrechenbareAbwesenheitsMinutes] erhält (gleiche Tagessoll-Logik,
/// halbtägig → halbes Tagessoll). Das ist Absicht: `timeOff` bleibt
/// soll-angerechnet, damit der Zeitausgleichstag nicht ins Minus läuft und die
/// Lohn-Grundlage ([ZeitkontoSnapshot.istMinutes]) unverändert bleibt — dieser
/// Abzug hebt die Gutschrift **nur im Saldo** wieder auf, sodass der Saldo genau
/// um das abgefeierte Tagessoll sinkt. (`AbsenceRequest.hours` bleibt der
/// informelle/DATEV-Wert und beeinflusst den Saldo bewusst nicht, weil sonst ein
/// Restfehler gegenüber der Tagessoll-basierten Ist-Gutschrift entstünde.)
int zeitausgleichSaldoMinutes({
  required List<SollzeitProfile> profiles,
  required List<AbsenceRequest> absences,
  required int jahr,
  required int monat,
}) {
  final nurZeitausgleich =
      absences.where((a) => a.type == AbsenceType.timeOff).toList();
  if (nurZeitausgleich.isEmpty) return 0;
  return anrechenbareAbwesenheitsMinutes(
    profiles: profiles,
    absences: nurZeitausgleich,
    jahr: jahr,
    monat: monat,
  );
}

/// Krankheitstage (sickness/childSick) im Monat — Kalendertage im Zeitraum,
/// auf den Monat geklemmt.
int krankTageImMonat({
  required List<AbsenceRequest> absences,
  required int jahr,
  required int monat,
}) {
  final first = DateTime(jahr, monat, 1);
  final last = DateTime(jahr, monat + 1, 0);
  var days = 0;
  for (final absence in absences) {
    if (absence.status != AbsenceStatus.approved) continue;
    if (absence.type != AbsenceType.sickness &&
        absence.type != AbsenceType.childSick) {
      continue;
    }
    for (var day = absence.startDate;
        !day.isAfter(absence.endDate);
        day = day.add(const Duration(days: 1))) {
      if (day.isBefore(first) || day.isAfter(last)) continue;
      days++;
    }
  }
  return days;
}
