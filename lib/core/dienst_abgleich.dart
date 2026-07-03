// lib/core/dienst_abgleich.dart

import '../models/absence_request.dart';
import '../models/clock_entry.dart';
import '../models/shift.dart';

/// Ergebnis-Status des Soll-Ist-Abgleichs einer geplanten Schicht bzw. einer
/// ungeplanten Anwesenheit (ZV-2.2a). Rein anzeigend — **kein** persistierter
/// Enum-Wert (keine `.value`/`fromValue`-Kopplung), nur ein Dart-Ergebnis.
enum DienstStatus {
  /// Rechtzeitig erschienen (im Karenzfenster um den Schichtbeginn).
  puenktlich,

  /// Erschienen, aber nach dem Karenzfenster ([DienstAbgleich.abweichungMinuten]).
  verspaetet,

  /// Vor Schichtende ausgestempelt ([DienstAbgleich.abweichungMinuten]).
  frueherGegangen,

  /// Schicht hat begonnen (Karenz vorbei), aber niemand eingestempelt und keine
  /// genehmigte Abwesenheit.
  nichtErschienen,

  /// Eine genehmigte Abwesenheit deckt die Schicht ab.
  abwesendEntschuldigt,

  /// Stempel ohne zugeordnete Schicht (spontane/ungeplante Anwesenheit).
  ungeplantAnwesend,

  /// Schicht liegt (relativ zu `now`) noch in der Zukunft — noch nichts zu werten.
  offen;

  /// Deutsches UI-Label (ohne die variable Minutenangabe).
  String get label => switch (this) {
        DienstStatus.puenktlich => 'Pünktlich',
        DienstStatus.verspaetet => 'Verspätet',
        DienstStatus.frueherGegangen => 'Früher gegangen',
        DienstStatus.nichtErschienen => 'Nicht erschienen',
        DienstStatus.abwesendEntschuldigt => 'Entschuldigt',
        DienstStatus.ungeplantAnwesend => 'Ungeplant anwesend',
        DienstStatus.offen => 'Offen',
      };

  /// Ist dieser Status ein Handlungssignal für den Manager (Tagessicht)?
  bool get istAuffaellig =>
      this == DienstStatus.verspaetet ||
      this == DienstStatus.nichtErschienen ||
      this == DienstStatus.frueherGegangen ||
      this == DienstStatus.ungeplantAnwesend;
}

/// Eine Zeile des Tagesabgleichs: eine geplante Schicht mit ihrem Ist-Status
/// **oder** eine ungeplante Anwesenheit (dann `shiftId == null`).
class DienstAbgleich {
  const DienstAbgleich({
    required this.userId,
    required this.status,
    this.userName,
    this.shiftId,
    this.siteId,
    this.siteName,
    this.shiftStart,
    this.shiftEnd,
    this.kommen,
    this.gehen,
    this.abweichungMinuten = 0,
    this.clockEntryId,
  });

  final String userId;
  final String? userName;
  final String? shiftId;
  final String? siteId;
  final String? siteName;
  final DateTime? shiftStart;
  final DateTime? shiftEnd;
  final DateTime? kommen;
  final DateTime? gehen;
  final DienstStatus status;

  /// Minuten Verspätung ([DienstStatus.verspaetet]) bzw. zu-früh-gegangen
  /// ([DienstStatus.frueherGegangen]); sonst 0.
  final int abweichungMinuten;

  /// Zugeordnete Stempel-Buchung (falls vorhanden).
  final String? clockEntryId;
}

/// **Pure** Soll-Ist-Abgleich zwischen geplanten Schichten und tatsächlichen
/// Stempelungen eines Tages (ZV-2.2a). Kein State/IO/`now()`/Zufall — `now` wird
/// injiziert → deterministisch + offline testbar (Muster `ShiftSlotGenerator`).
///
/// **Vertrag:** Der Aufrufer übergibt die Schichten und Stempelungen **eines
/// Kalendertags** sowie die den Tag berührenden **genehmigten** Abwesenheiten.
/// Die Zuordnung erfolgt pro Mitarbeiter: zuerst über `ClockEntry.shiftId`
/// (harte Verknüpfung, ZV-2.1), dann über zeitliche Nähe (`kommen` am nächsten am
/// Schichtbeginn, innerhalb eines großzügigen Fensters). Nicht zugeordnete
/// Stempel werden zu [DienstStatus.ungeplantAnwesend].
abstract final class DienstAbgleichService {
  /// Standard-Karenz (Minuten) um den Schichtbeginn/-ende (Betreiber via
  /// `OrgSettings` überschreibbar, ZV-2 / E-Z6).
  static const int defaultKarenzMinuten = 5;

  /// Fenster (Minuten vor Beginn / nach Ende), in dem ein Stempel ohne `shiftId`
  /// noch einer Schicht zeitlich zugeordnet werden darf.
  static const int _matchFensterMinuten = 180;

  static List<DienstAbgleich> berechne({
    required List<Shift> schichten,
    required List<ClockEntry> stempel,
    required List<AbsenceRequest> abwesenheiten,
    required DateTime now,
    int karenzMinuten = defaultKarenzMinuten,
  }) {
    final karenz = karenzMinuten < 0 ? 0 : karenzMinuten;

    // Nur wertbare Schichten/Stempel.
    final aktiveSchichten = schichten
        .where((s) => s.status != ShiftStatus.cancelled)
        .toList(growable: false);
    final aktiveStempel = stempel
        .where((e) => e.status != ClockStatus.deaktiviert)
        .toList(growable: false);
    final genehmigt = abwesenheiten
        .where((a) => a.status == AbsenceStatus.approved)
        .toList(growable: false);

    // Pro Mitarbeiter gruppieren, damit sich Zuordnungen nicht über Personen
    // hinweg vermischen.
    final userIds = <String>{
      ...aktiveSchichten.map((s) => s.userId),
      ...aktiveStempel.map((e) => e.userId),
    };

    final ergebnis = <DienstAbgleich>[];

    for (final uid in userIds) {
      final userSchichten = aktiveSchichten
          .where((s) => s.userId == uid)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final userStempel = aktiveStempel.where((e) => e.userId == uid).toList()
        ..sort((a, b) => a.kommen.compareTo(b.kommen));
      final userAbwesend = genehmigt.where((a) => a.userId == uid).toList();

      // Zuordnung Stempel → Schicht. `matchedStempel` = bereits vergebene
      // ClockEntry-IDs; `stempelJeSchicht` = Schicht-Index → ClockEntry.
      final matchedStempelIds = <String>{};
      final stempelJeSchicht = <int, ClockEntry>{};

      // Pass 1: harte shiftId-Verknüpfung.
      for (var i = 0; i < userSchichten.length; i++) {
        final schicht = userSchichten[i];
        for (final e in userStempel) {
          final id = e.id;
          if (id == null) continue;
          if (matchedStempelIds.contains(id)) continue;
          if (e.shiftId != null && e.shiftId == schicht.id) {
            stempelJeSchicht[i] = e;
            matchedStempelIds.add(id);
            break;
          }
        }
      }

      // Pass 2: zeitliche Nähe für noch unbesetzte Schichten.
      for (var i = 0; i < userSchichten.length; i++) {
        if (stempelJeSchicht.containsKey(i)) continue;
        final schicht = userSchichten[i];
        ClockEntry? best;
        int? bestDelta;
        for (final e in userStempel) {
          final id = e.id;
          if (id == null || matchedStempelIds.contains(id)) continue;
          if (!_imFenster(e, schicht)) continue;
          final delta =
              (e.kommen.difference(schicht.startTime).inMinutes).abs();
          if (bestDelta == null || delta < bestDelta) {
            best = e;
            bestDelta = delta;
          }
        }
        if (best != null) {
          stempelJeSchicht[i] = best;
          matchedStempelIds.add(best.id!);
        }
      }

      // Schicht-Zeilen bilden.
      for (var i = 0; i < userSchichten.length; i++) {
        final schicht = userSchichten[i];
        final entry = stempelJeSchicht[i];
        ergebnis.add(_bewerteSchicht(
          schicht: schicht,
          entry: entry,
          abwesenheiten: userAbwesend,
          now: now,
          karenz: karenz,
        ));
      }

      // Ungeplante Stempel (kein Schicht-Match).
      for (final e in userStempel) {
        final id = e.id;
        if (id != null && matchedStempelIds.contains(id)) continue;
        ergebnis.add(DienstAbgleich(
          userId: uid,
          userName: e.userName,
          siteId: e.siteId,
          siteName: e.siteName,
          kommen: e.kommen,
          gehen: e.gehen,
          status: DienstStatus.ungeplantAnwesend,
          clockEntryId: e.id,
        ));
      }
    }

    // Stabile Sortierung: nach Schichtbeginn (ungeplante ans Kommen), dann Name.
    ergebnis.sort((a, b) {
      final aRef = a.shiftStart ?? a.kommen;
      final bRef = b.shiftStart ?? b.kommen;
      if (aRef != null && bRef != null) {
        final c = aRef.compareTo(bRef);
        if (c != 0) return c;
      } else if (aRef == null && bRef != null) {
        return 1;
      } else if (aRef != null && bRef == null) {
        return -1;
      }
      return (a.userName ?? a.userId).compareTo(b.userName ?? b.userId);
    });

    return ergebnis;
  }

  static bool _imFenster(ClockEntry e, Shift schicht) {
    final fensterStart = schicht.startTime
        .subtract(const Duration(minutes: _matchFensterMinuten));
    final fensterEnde =
        schicht.endTime.add(const Duration(minutes: _matchFensterMinuten));
    return e.kommen.isAfter(fensterStart) && e.kommen.isBefore(fensterEnde);
  }

  static DienstAbgleich _bewerteSchicht({
    required Shift schicht,
    required ClockEntry? entry,
    required List<AbsenceRequest> abwesenheiten,
    required DateTime now,
    required int karenz,
  }) {
    DienstAbgleich base(DienstStatus status, {int abweichung = 0}) =>
        DienstAbgleich(
          userId: schicht.userId,
          userName: entry?.userName ??
              (schicht.employeeName.isEmpty ? null : schicht.employeeName),
          shiftId: schicht.id,
          siteId: entry?.siteId ?? schicht.siteId,
          siteName: entry?.siteName ?? schicht.siteName,
          shiftStart: schicht.startTime,
          shiftEnd: schicht.endTime,
          kommen: entry?.kommen,
          gehen: entry?.gehen,
          status: status,
          abweichungMinuten: abweichung,
          clockEntryId: entry?.id,
        );

    if (entry != null) {
      final spaetMin =
          entry.kommen.difference(schicht.startTime).inMinutes;
      if (spaetMin > karenz) {
        return base(DienstStatus.verspaetet, abweichung: spaetMin);
      }
      // Früher gegangen nur bei abgeschlossener Buchung werten (gehen gesetzt).
      final gehen = entry.gehen;
      if (gehen != null) {
        final fruehMin = schicht.endTime.difference(gehen).inMinutes;
        if (fruehMin > karenz) {
          return base(DienstStatus.frueherGegangen, abweichung: fruehMin);
        }
      }
      return base(DienstStatus.puenktlich);
    }

    // Kein Stempel: Abwesenheit deckt die Schicht?
    if (_abwesenheitDeckt(schicht, abwesenheiten)) {
      return base(DienstStatus.abwesendEntschuldigt);
    }

    // Schicht bereits begonnen (Karenz vorbei) → nicht erschienen; sonst offen.
    final faelligAb =
        schicht.startTime.add(Duration(minutes: karenz));
    if (!now.isBefore(faelligAb)) {
      return base(DienstStatus.nichtErschienen);
    }
    return base(DienstStatus.offen);
  }

  static bool _abwesenheitDeckt(
      Shift schicht, List<AbsenceRequest> abwesenheiten) {
    final tag = DateTime(
        schicht.startTime.year, schicht.startTime.month, schicht.startTime.day);
    for (final a in abwesenheiten) {
      final von = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final bis = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      if (!tag.isBefore(von) && !tag.isAfter(bis)) return true;
    }
    return false;
  }
}
