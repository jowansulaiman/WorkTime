// lib/core/datev_export_check.dart

import '../models/cash_closing.dart';
import '../models/finance_models.dart';
import 'datev_export.dart';

/// **DATEV-2 — Prüflauf vor dem Export.** Transiente Befundliste (Muster
/// `ComplianceViolation`: KEINE Collection, KEIN `now()` ohne Injektion). Wird
/// vor jedem DATEV-Buchungsstapel-Export ausgeführt; Fehler blockieren den
/// Export, Warnungen erfordern ein ausdrückliches „Trotz Warnungen exportieren".
///
/// **Modellbedingt keine Soll/Haben-Balance-Prüfung:** das einseitige
/// Allokationsmodell kennt keine Beleg-Balance — es gibt kein Soll==Haben-Paar
/// je Beleg. Ersatz: [DatevExportFinding] `entries_empty` + die S/H-Summen
/// werden in der Export-Historie (Q2) sichtbar. Bewusst dokumentiert, damit die
/// Anforderung „unbalancierte Buchungen" nicht als vergessen gilt.
enum DatevFindingSeverity {
  /// Blockiert den Export (kaputte/falsche Zeile).
  error,

  /// Export möglich, aber nur mit ausdrücklicher Bestätigung.
  warning,

  /// Reiner Hinweis (blockiert nicht, braucht keine Bestätigung).
  info,
}

/// Ein einzelner Prüf-Befund. [code] ist stabil (Tests asserten darauf, Muster
/// `ComplianceViolation.code`); [message] ist die deutsche Anzeige.
class DatevExportFinding {
  const DatevExportFinding({
    required this.code,
    required this.severity,
    required this.message,
    this.affectedIds = const [],
  });

  final String code;
  final DatevFindingSeverity severity;
  final String message;

  /// Betroffene Entitäten (Buchungs-IDs, Kostenstellen-/-art-IDs, Tage) — für
  /// die Detail-Anzeige; nie für die Gate-Entscheidung nötig.
  final List<String> affectedIds;

  bool get isError => severity == DatevFindingSeverity.error;
  bool get isWarning => severity == DatevFindingSeverity.warning;
}

abstract final class DatevExportCheck {
  /// Führt alle v1-Prüfungen aus. **Pure**: keine Seiteneffekte, keine Uhr.
  ///
  /// - [entries]: das komplette Journal (wird intern auf [year] gefiltert).
  /// - [centersById]/[typesById]: aufgelöste Stammdaten (Muster wie der
  ///   Export-Builder) — fehlende Schlüssel = kaputte Referenz.
  /// - [config]: DATEV-Config (Gegenkonto, Erlöskonto-je-Satz).
  /// - [closings]: Kassenabschlüsse des Zeitraums. **`null` bedeutet
  ///   „nicht verfügbar" (local-Modus)** — dann werden die closing-Prüfungen
  ///   NICHT als „keine Abschlüsse" fehlinterpretiert, sondern ein Info-Befund
  ///   `closings_unavailable` gesetzt. Eine leere Liste heißt dagegen wirklich
  ///   „keine Abschlüsse im Zeitraum".
  static List<DatevExportFinding> run({
    required List<JournalEntry> entries,
    required Map<String, CostCenter> centersById,
    required Map<String, CostType> typesById,
    required DatevExportConfig config,
    required int year,
    List<CashClosing>? closings,
  }) {
    final findings = <DatevExportFinding>[];
    final yearEntries =
        entries.where((e) => e.date.year == year).toList(growable: false);

    // 1) entries_empty — nichts zu exportieren.
    if (yearEntries.isEmpty) {
      findings.add(DatevExportFinding(
        code: 'entries_empty',
        severity: DatevFindingSeverity.error,
        message: 'Keine Buchungen im Jahr $year — der Export wäre leer.',
      ));
      // Ohne Buchungen sind die Zeilen-Prüfungen gegenstandslos; Config-/
      // Closing-Prüfungen laufen dennoch weiter.
    }

    // 2) contra_account_missing — Gegenkonto (Spalte 8) bliebe leer.
    if (config.defaultContraAccount.trim().isEmpty) {
      findings.add(const DatevExportFinding(
        code: 'contra_account_missing',
        severity: DatevFindingSeverity.error,
        message: 'Kein Gegenkonto hinterlegt — jede Buchungszeile bliebe ohne '
            'Gegenkonto. Bitte in der DATEV-Konfiguration setzen.',
      ));
    }

    // 3) je Buchung: unbekannte Kostenstelle/-art, fehlende Kontonummer.
    final unknownCenters = <String>{};
    final unknownTypes = <String>{};
    final typesWithoutNumber = <String>{};
    for (final e in yearEntries) {
      if (!centersById.containsKey(e.costCenterId)) {
        unknownCenters.add(e.costCenterId);
      }
      final type = typesById[e.costTypeId];
      if (type == null) {
        unknownTypes.add(e.costTypeId);
      } else if (_digitsOnly(type.number).isEmpty) {
        // An die Export-Normalisierung angleichen: der Builder jagt die Nummer
        // durch `_digits` (nur Ziffern). Ein nicht-numerischer Platzhalter wie
        // „TBD" ist zwar nicht leer, ergäbe aber eine leere Konto-Spalte —
        // also genau die kaputte Zeile, die dieser Befund abfängt.
        typesWithoutNumber.add(e.costTypeId);
      }
    }
    if (unknownCenters.isNotEmpty) {
      findings.add(DatevExportFinding(
        code: 'unknown_cost_center',
        severity: DatevFindingSeverity.error,
        message: 'Buchungen verweisen auf ${unknownCenters.length} unbekannte '
            'Kostenstelle(n).',
        affectedIds: unknownCenters.toList(),
      ));
    }
    if (unknownTypes.isNotEmpty) {
      findings.add(DatevExportFinding(
        code: 'unknown_cost_type',
        severity: DatevFindingSeverity.error,
        message: 'Buchungen verweisen auf ${unknownTypes.length} unbekannte '
            'Kostenart(en).',
        affectedIds: unknownTypes.toList(),
      ));
    }
    if (typesWithoutNumber.isNotEmpty) {
      findings.add(DatevExportFinding(
        code: 'cost_type_missing_number',
        severity: DatevFindingSeverity.error,
        message: '${typesWithoutNumber.length} Kostenart(en) ohne Kontonummer '
            '— die Konto-Spalte bliebe leer. Bitte Nummer ergänzen.',
        affectedIds: typesWithoutNumber.toList(),
      ));
    }

    // 4) Kassenabschluss-Prüfungen (nur wenn verfügbar).
    if (closings == null) {
      findings.add(const DatevExportFinding(
        code: 'closings_unavailable',
        severity: DatevFindingSeverity.info,
        message: 'Kassenabschlüsse konnten im aktuellen Speichermodus nicht '
            'geprüft werden (offline/lokal).',
      ));
    } else {
      final yearClosings = closings
          .where((c) => _businessYearOf(c.businessDay) == year)
          .toList(growable: false);

      // closing_unbooked — abgeschlossen, aber (noch) nicht ins Journal gebucht.
      final unbooked = yearClosings
          .where((c) => !c.bookedToFinance)
          .map((c) => c.businessDay)
          .toSet();
      if (unbooked.isNotEmpty) {
        findings.add(DatevExportFinding(
          code: 'closing_unbooked',
          severity: DatevFindingSeverity.warning,
          message: '${unbooked.length} Kassenabschluss/-abschlüsse noch nicht '
              'gebucht — deren Umsatz fehlt im Export.',
          affectedIds: unbooked.toList()..sort(),
        ));
      }

      // revenue_rate_unmapped — USt-Sätze mit Umsatz, aber ohne Erlöskonto
      // (die heutige stille Skip-Klasse beim Buchen).
      final unmappedRates = <int>{};
      for (final c in yearClosings) {
        for (final tax in c.taxes) {
          final rate = tax.ratePercent;
          if (rate == null) continue;
          if ((tax.netCents ?? 0) == 0) continue;
          if (!config.revenueAccountByRate.containsKey(rate)) {
            unmappedRates.add(rate);
          }
        }
      }
      if (unmappedRates.isNotEmpty) {
        final sorted = unmappedRates.toList()..sort();
        findings.add(DatevExportFinding(
          code: 'revenue_rate_unmapped',
          severity: DatevFindingSeverity.warning,
          message: 'USt-Sätze ohne Erlöskonto: '
              '${sorted.map((r) => '$r%').join(', ')} — diese Umsätze werden '
              'beim Buchen still übersprungen.',
          affectedIds: sorted.map((r) => '$r').toList(),
        ));
      }
    }

    return findings;
  }

  /// Nur die Ziffern (spiegelt `DatevExport`'s `_digits`-Normalisierung der
  /// Konto-Spalte).
  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Jahr aus dem `YYYY-MM-DD`-Geschäftstag (tolerant; -1 bei kaputtem Wert →
  /// matcht kein reales Jahr, wird also ignoriert).
  static int _businessYearOf(String businessDay) {
    if (businessDay.length >= 4) {
      final year = int.tryParse(businessDay.substring(0, 4));
      if (year != null) return year;
    }
    return -1;
  }
}
