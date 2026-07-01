import 'dart:math' as math;

import '../models/pos_receipt.dart';

/// **P3.2 — Storno-/Refund-Anomalie je Kassierer.** Erkennt statistisch
/// auffällige Erstattungs-/Storno-Quoten je Kassierer im Vergleich zum
/// Standort-Schnitt (z-Wert). Zielt auf ein bekanntes Kiosk-Schwundmuster
/// (kassieren → stornieren → Bargeld behalten).
///
/// **WICHTIG — rechtliche/ethische Leitplanken (im Plan verankert):**
/// - Ergebnis ist ein **Verdachtshinweis aus Statistik**, **niemals** eine
///   Schuldfeststellung oder Grundlage einer automatischen Sanktion.
/// - **Mindest-Fallzahl** ([minTransactions]) verhindert Fehlalarme bei wenigen
///   Vorgängen; ein z-Wert braucht **mindestens zwei** vergleichbare Kassierer.
/// - **Strikt admin-only**, **Zweckbindung** (Verlustprävention), nur auf
///   Kassierer-Ebene. **Einführung/Nutzung erfordert Mitbestimmung (BetrVG) &
///   DSGVO-Klärung** — dies ist nur die Analyse-Logik, kein Freibrief.
///
/// **Pure / offline-testbar.**
class CashierStat {
  const CashierStat({
    required this.cashierId,
    required this.totalTransactions,
    required this.refundTransactions,
    required this.refundRate,
    required this.zScore,
    required this.isFlagged,
  });

  final String cashierId;

  /// Umsatz-Vorgänge (sales + refund, kein training/cash) des Kassierers.
  final int totalTransactions;
  final int refundTransactions;

  /// Anteil Erstattungen/Stornos an den Vorgängen (0..1).
  final double refundRate;

  /// z-Wert der Quote ggü. dem Standort-Schnitt; `null`, wenn keine belastbare
  /// Vergleichsbasis (< 2 qualifizierte Kassierer oder Streuung 0).
  final double? zScore;

  /// Statistisch auffällig (z >= Schwelle). **Verdachtshinweis, kein Urteil.**
  final bool isFlagged;
}

class CashierAnomalyReport {
  const CashierAnomalyReport({
    required this.stats,
    required this.siteRefundRateMean,
    required this.minTransactions,
    required this.zThreshold,
  });

  /// Qualifizierte Kassierer (>= Mindest-Fallzahl), z-Wert absteigend.
  final List<CashierStat> stats;
  final double siteRefundRateMean;
  final int minTransactions;
  final double zThreshold;

  /// Auffällige Kassierer (nur Verdachtshinweise zur Prüfung).
  List<CashierStat> get flagged =>
      stats.where((s) => s.isFlagged).toList(growable: false);
}

/// Berechnet die [CashierAnomalyReport] aus Belegen.
///
/// - [minTransactions]: Mindest-Fallzahl, ab der ein Kassierer überhaupt bewertet
///   wird (Schutz vor Prozent-Rauschen / Vorverurteilung bei Kleinmengen).
/// - [zThreshold]: ab welchem z-Wert ein Hinweis als „auffällig" markiert wird.
CashierAnomalyReport computeCashierAnomalies({
  required List<PosReceipt> receipts,
  int minTransactions = 30,
  double zThreshold = 2.0,
}) {
  final total = <String, int>{};
  final refunds = <String, int>{};
  for (final r in receipts) {
    if (r.training || !r.isRevenue) continue;
    final id = r.cashierId;
    if (id == null || id.trim().isEmpty) continue;
    total[id] = (total[id] ?? 0) + 1;
    if ((r.type ?? '').toLowerCase() == 'refund') {
      refunds[id] = (refunds[id] ?? 0) + 1;
    }
  }

  // Nur Kassierer mit ausreichender Fallzahl bewerten.
  final qualified = <String>[
    for (final id in total.keys)
      if (total[id]! >= minTransactions) id,
  ];
  final rateOf = <String, double>{
    for (final id in qualified) id: (refunds[id] ?? 0) / total[id]!,
  };

  double mean = 0;
  double? stddev;
  if (qualified.isNotEmpty) {
    mean = rateOf.values.reduce((a, b) => a + b) / qualified.length;
    if (qualified.length >= 2) {
      final variance = rateOf.values
              .map((r) => (r - mean) * (r - mean))
              .reduce((a, b) => a + b) /
          qualified.length;
      final sd = math.sqrt(variance);
      stddev = sd > 0 ? sd : null;
    }
  }

  final stats = <CashierStat>[];
  for (final id in qualified) {
    final rate = rateOf[id]!;
    final z = stddev == null ? null : (rate - mean) / stddev;
    stats.add(CashierStat(
      cashierId: id,
      totalTransactions: total[id]!,
      refundTransactions: refunds[id] ?? 0,
      refundRate: rate,
      zScore: z,
      isFlagged: z != null && z >= zThreshold,
    ));
  }
  stats.sort((a, b) {
    final za = a.zScore ?? double.negativeInfinity;
    final zb = b.zScore ?? double.negativeInfinity;
    final c = zb.compareTo(za);
    return c != 0 ? c : a.cashierId.compareTo(b.cashierId);
  });

  return CashierAnomalyReport(
    stats: stats,
    siteRefundRateMean: mean,
    minTransactions: minTransactions,
    zThreshold: zThreshold,
  );
}
