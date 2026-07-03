import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;
import 'pos_receipt.dart';

/// **Kassen-Modul §3.3 — Tagesaggregat je (Standort, Geschäftstag).** Verdichtet
/// die `posReceipts` eines Tages zu EINEM Dokument, damit Monats-/Jahres-Sichten
/// nicht zehntausende Beleg-Reads kosten. Doc-ID deterministisch
/// `{businessDay}-{siteId}` unter `organizations/{orgId}/posDailyStats`.
///
/// **Cloud-only wie [PosReceipt]** (serverseitig vom OktoPOS-Sync geschrieben,
/// Client read-only, kein lokaler Cache) — daher bewusst nur die
/// Firestore-Serialisierung (camelCase), keine snake_case/`toMap`-Form.
///
/// Idempotenz-Hinweis (Plan §3.3): Alle beleg-abgeleiteten Felder sind bei
/// Re-Aggregation stabil; [cogsCents] wird mit dem jeweils AKTUELLEN Netto-EK
/// bewertet (kein EK-Verlauf) und ist ein Richtwert.
class PosDailyStat {
  const PosDailyStat({
    this.id,
    required this.orgId,
    required this.siteId,
    required this.businessDay,
    this.salesCount = 0,
    this.refundCount = 0,
    this.positiveRefundCount = 0,
    this.revenueGrossCents = 0,
    this.revenueNetCents = 0,
    this.netUncoveredGrossCents = 0,
    this.taxes = const [],
    this.paymentsByMethod = const {},
    this.cashMovementCents = 0,
    this.cogsCents,
    this.cogsCoveredGrossCents = 0,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String siteId;

  /// Geschäftstag `YYYY-MM-DD` (aus der Kasse bzw. Fallback aus
  /// `transactionDate`, gleiche Regel wie `computeDailyClosings`).
  final String businessDay;

  final int salesCount;
  final int refundCount;

  /// Erstattungs-Belege mit POSITIVEM Brutto — Vorzeichen-Verdacht (Plan A8):
  /// kommen Refunds nicht vorzeichenbehaftet aus der Kasse, wären Umsatz und
  /// Soll-Bargeld still überhöht. Die UI zeigt das als Datenqualitäts-Signal.
  final int positiveRefundCount;

  /// Brutto-Umsatz (sales + refund, vorzeichenbehaftet) in Cent.
  final int revenueGrossCents;

  /// Netto-Umsatz = Σ `taxes[].netCents` der Belege (Untergrenze — Belege ohne
  /// belastbare Steuerzeilen stecken stattdessen in [netUncoveredGrossCents]).
  final int revenueNetCents;

  /// Brutto-Anteil, dessen Netto NICHT bestimmbar war (Beleg ohne/mit
  /// unvollständigen Steuerzeilen) — offen ausweisen, nicht raten.
  final int netUncoveredGrossCents;

  /// USt-Aufschlüsselung je Satz (aggregiert), gleiche Form wie am Beleg.
  /// **Bewusster Overlap** (wie `computeDailyClosings`): Steuerzeilen von
  /// Belegen, deren Netto teilweise unbestimmbar war, stecken tolerant hier
  /// UND deren volles Brutto in [netUncoveredGrossCents] — Steuer-Split und
  /// `nettoUnsicher` daher nie einfach addieren.
  final List<ReceiptTax> taxes;

  /// Zahlart → Betrag in Cent (bar/Karte/…, `unbekannt` als eigener Eimer).
  final Map<String, int> paymentsByMethod;

  /// Summe der `type='cash'`-Belege (Ein-/Auszahlungen) in Cent.
  final int cashMovementCents;

  /// Wareneinsatz der verkauften Zeilen in Cent (Netto-EK × Menge, §8);
  /// `null` = an diesem Tag keine einzige bewertbare Zeile — nicht 0.
  final int? cogsCents;

  /// Umsatzanteil (Zeilen-Brutto) mit EK-Bewertung — Zähler der EK-Abdeckung.
  final int cogsCoveredGrossCents;

  final DateTime? updatedAt;

  factory PosDailyStat.fromFirestore(String id, Map<String, dynamic> map) {
    final rawPayments = map['paymentsByMethod'];
    final payments = <String, int>{};
    if (rawPayments is Map) {
      rawPayments.forEach((key, value) {
        final cents = parse.toInt(value);
        if (cents != null) payments[key.toString()] = cents;
      });
    }
    return PosDailyStat(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      siteId: (map['siteId'] ?? '').toString(),
      businessDay: (map['businessDay'] ?? '').toString(),
      salesCount: parse.toInt(map['salesCount']) ?? 0,
      refundCount: parse.toInt(map['refundCount']) ?? 0,
      positiveRefundCount: parse.toInt(map['positiveRefundCount']) ?? 0,
      revenueGrossCents: parse.toInt(map['revenueGrossCents']) ?? 0,
      revenueNetCents: parse.toInt(map['revenueNetCents']) ?? 0,
      netUncoveredGrossCents: parse.toInt(map['netUncoveredGrossCents']) ?? 0,
      taxes: _readTaxes(map['taxes']),
      paymentsByMethod: payments,
      cashMovementCents: parse.toInt(map['cashMovementCents']) ?? 0,
      cogsCents: parse.toInt(map['cogsCents']),
      cogsCoveredGrossCents: parse.toInt(map['cogsCoveredGrossCents']) ?? 0,
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'orgId': orgId,
        'siteId': siteId,
        'businessDay': businessDay,
        'salesCount': salesCount,
        'refundCount': refundCount,
        'positiveRefundCount': positiveRefundCount,
        'revenueGrossCents': revenueGrossCents,
        'revenueNetCents': revenueNetCents,
        'netUncoveredGrossCents': netUncoveredGrossCents,
        'taxes': taxes.map((t) => t.toFirestoreMap()).toList(),
        'paymentsByMethod': paymentsByMethod,
        'cashMovementCents': cashMovementCents,
        'cogsCents': cogsCents,
        'cogsCoveredGrossCents': cogsCoveredGrossCents,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static List<ReceiptTax> _readTaxes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ReceiptTax.fromFirestore(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
