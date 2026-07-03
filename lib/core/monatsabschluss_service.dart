// lib/core/monatsabschluss_service.dart

import '../models/work_entry.dart';
import '../models/zeitkonto_snapshot.dart';

/// Ergebnis einer Monatsabschluss-Prüfung (AllTec `MonthClosingValidation`, M5).
///
/// [errors] blockieren den Abschluss ([canClose] == false), [warnings] sind
/// nicht-blockierende Hinweise. Alle Texte sind deutsch (de_DE).
class MonatsabschlussValidation {
  const MonatsabschlussValidation({
    required this.canClose,
    this.errors = const [],
    this.warnings = const [],
  });

  final bool canClose;
  final List<String> errors;
  final List<String> warnings;

  static const MonatsabschlussValidation empty = MonatsabschlussValidation(
    canClose: true,
  );

  bool get hasWarnings => warnings.isNotEmpty;
}

/// **Pure** Domänenlogik des Monatsabschlusses (AllTec `MonthClosingService`,
/// M5 — auf WorkTimes Typen [ZeitkontoSnapshot] + [WorkEntry]).
///
/// Validiert die Abschluss-Vorbedingungen, sperrt/entsperrt einen Snapshot. Kein
/// State/IO/`now()` — der Sperr-Zeitstempel wird als Parameter übergeben, damit
/// der Service deterministisch + offline testbar bleibt. Die Persistenz liegt im
/// [ZeitwirtschaftProvider].
class MonatsabschlussService {
  const MonatsabschlussService();

  /// Prüft, ob der Monat von [snapshot] abschließbar ist.
  ///
  /// **Blocker** ([errors]):
  /// - der Monat ist bereits abgeschlossen,
  /// - der Monat ist noch nicht vollständig vorbei (laufender/zukünftiger Monat,
  ///   bezogen auf [now]) — nur abgeschlossene Kalendermonate sind buchbar,
  /// - es gibt noch nicht entschiedene Zeiteinträge (Status `draft`/`submitted`),
  /// - es gibt noch **offene Klärungsfälle** ([offeneKlaerungen] > 0) — sonst
  ///   fehlten die betroffenen Stunden still in Zeitkonto/Lohn (ZV-5.2),
  /// - der **Vormonat** existiert als Snapshot, ist aber nicht gesperrt
  ///   (eine Lücke; fehlt der Vormonats-Snapshot ganz, ist das kein Blocker —
  ///   z. B. Beginn der Zeiterfassung, AllTec-konform).
  ///
  /// **Warnungen** ([warnings], nicht blockierend):
  /// - kein Ist trotz Soll > 0,
  /// - sehr viele Krankheitstage (> 20).
  ///
  /// [now] wird injiziert (Pure-Function-Disziplin), damit der Service
  /// deterministisch testbar bleibt. [offeneKlaerungen] = Anzahl der
  /// `ClockStatus.klaerung`-Buchungen des Zielmonats (der Provider ermittelt sie,
  /// der Service bleibt pur).
  MonatsabschlussValidation validate({
    required ZeitkontoSnapshot snapshot,
    required List<WorkEntry> entries,
    required ZeitkontoSnapshot? vormonat,
    required DateTime now,
    int offeneKlaerungen = 0,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    if (snapshot.abgeschlossen) {
      errors.add('Der Monat ist bereits abgeschlossen.');
    }

    // Nur vollständig vergangene Kalendermonate sind abschließbar.
    final istVergangen = snapshot.jahr < now.year ||
        (snapshot.jahr == now.year && snapshot.monat < now.month);
    if (!istVergangen) {
      errors.add('Der Monat ist noch nicht vollständig vorbei.');
    }

    final offen = entries
        .where((e) =>
            e.status == WorkEntryStatus.draft ||
            e.status == WorkEntryStatus.submitted)
        .length;
    if (offen > 0) {
      errors.add(offen == 1
          ? 'Ein Zeiteintrag ist noch nicht genehmigt.'
          : '$offen Zeiteinträge sind noch nicht genehmigt.');
    }

    if (offeneKlaerungen > 0) {
      errors.add(offeneKlaerungen == 1
          ? 'Ein Stempel-Klärungsfall ist noch offen.'
          : '$offeneKlaerungen Stempel-Klärungsfälle sind noch offen.');
    }

    if (vormonat != null && !vormonat.abgeschlossen) {
      errors.add('Der Vormonat ist noch nicht abgeschlossen.');
    }

    if (snapshot.istMinutes == 0 && snapshot.sollMinutes > 0) {
      warnings.add('Keine Ist-Stunden erfasst — bitte das Stundenkonto prüfen.');
    }
    if (snapshot.kranktage > 20) {
      warnings.add('Viele Krankheitstage (> 20) — bitte Atteste prüfen.');
    }

    return MonatsabschlussValidation(
      canClose: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Sperrt [snapshot] (Monatsabschluss). [von] = Akteur-uid, [am] = Zeitpunkt.
  ZeitkontoSnapshot applyLock(
    ZeitkontoSnapshot snapshot, {
    required String von,
    required DateTime am,
  }) {
    return snapshot.copyWith(
      abgeschlossen: true,
      abgeschlossenVon: von,
      abgeschlossenAm: am,
    );
  }

  /// Hebt die Sperre von [snapshot] auf (Abschluss zurücknehmen).
  ZeitkontoSnapshot applyUnlock(ZeitkontoSnapshot snapshot) {
    return snapshot.copyWith(
      abgeschlossen: false,
      clearAbgeschlossenVon: true,
      clearAbgeschlossenAm: true,
    );
  }
}
