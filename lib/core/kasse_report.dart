import '../models/pos_daily_stat.dart';
import '../models/pos_receipt.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import 'order_frequency.dart' show startOfIsoWeek, startOfMonth;

/// **Kassen-Modul §4.1 — Kassenbericht-Engine.** Bucketet Tagesaggregate
/// ([PosDailyStat]) und Bestellungen in ISO-Wochen / Monate / Jahre und liefert
/// je Periode Umsatz (brutto/netto), Käufe, Wareneinsatz und Rohertrag samt
/// Vergleich zur Vorperiode und zur Vorjahresperiode.
///
/// **Pure / offline-testbar** (kein IO, kein `now()` — der Stichtag wird
/// injiziert). Kennzahlen-Definitionen sind §8 des Plans:
/// - Umsatz brutto  = Σ `revenueGrossCents` (Erstattungen vorzeichenbehaftet, A8).
/// - Umsatz netto   = Σ `revenueNetCents` (Untergrenze); nicht bestimmbare
///   Anteile stehen offen in [KassenPeriode.nettoUnsicherCents].
/// - Käufe netto/brutto = Σ `PurchaseOrder.totalNetCents`/`totalGrossCents`
///   (M6-B, schalterabhängig `purchasePricesIncludeVat` §3.4), Status ≠
///   Entwurf/Storno, Periodenzuordnung `orderedAt ?? createdAt` (Datumsregel
///   wie Bestell-Auswertung; der Entwurf-Ausschluss ist eine bewusste
///   Abweichung — Entwürfe sind keine Käufe).
/// - Wareneinsatz   = Σ `cogsCents` (Netto-EK, Richtwert — A3).
/// - Rohertrag netto (die „Gewinn"-Zahl) = Umsatz netto − Wareneinsatz;
///   Rohertrag brutto nur als Vergleichswert (enthält USt).
enum ReportGranularity { week, month, year }

extension ReportGranularityX on ReportGranularity {
  String get label => switch (this) {
        ReportGranularity.week => 'Woche',
        ReportGranularity.month => 'Monat',
        ReportGranularity.year => 'Jahr',
      };

  /// Standard-Anzahl Perioden im Bericht (12 KW / 12 Monate / 3 Jahre).
  int get defaultBucketCount => switch (this) {
        ReportGranularity.week => 12,
        ReportGranularity.month => 12,
        ReportGranularity.year => 3,
      };
}

/// Eine Berichts-Periode (ISO-Woche, Kalendermonat oder Kalenderjahr).
/// [start] ist der date-only Beginn (Montag / Monatserster / 1. Januar);
/// das deutsche Label (z. B. „KW 27 2026") baut erst die UI (`de_DE`).
class KassenPeriode {
  const KassenPeriode({
    required this.start,
    required this.hatDaten,
    required this.belege,
    required this.erstattungen,
    required this.positiveErstattungen,
    required this.umsatzBruttoCents,
    required this.umsatzNettoCents,
    required this.nettoUnsicherCents,
    required this.kaeufeNettoCents,
    required this.kaeufeBruttoCents,
    required this.wareneinsatzCents,
    required this.wareneinsatzAbdeckungPct,
    required this.rohertragNettoCents,
    required this.rohertragBruttoCents,
    required this.deltaVorperiodePct,
    required this.deltaVorjahrPct,
  });

  final DateTime start;

  /// `false` = kein einziger Kassen-Tag im Fenster (UI zeigt „keine Daten",
  /// nie eine stille 0 — Käufe können trotzdem gefüllt sein).
  final bool hatDaten;

  final int belege;
  final int erstattungen;

  /// Erstattungs-Belege mit POSITIVEM Brutto (Vorzeichen-Verdacht A8) —
  /// > 0 ⇒ Datenqualitäts-Hinweis „positive Erstattungs-Belege erkannt".
  final int positiveErstattungen;

  final int umsatzBruttoCents;
  final int umsatzNettoCents;

  /// Brutto-Anteil ohne bestimmbares Netto (Datenqualität, offen ausweisen).
  final int nettoUnsicherCents;

  /// Einkaufsvolumen der Periode, netto (Σ Bestell-Netto). Bestellungen ohne
  /// USt-Satz zählen mit ihrem erfassten Preis (netto = brutto).
  final int kaeufeNettoCents;

  /// Einkaufsvolumen brutto (netto + USt je Position). Gleich netto, solange
  /// keine Bestellposition einen Steuersatz trägt (M6-B).
  final int kaeufeBruttoCents;

  /// `null` = keine einzige bewertbare Verkaufszeile in der Periode.
  final int? wareneinsatzCents;

  /// EK-Abdeckung in % (bewerteter Zeilen-Umsatz ÷ Brutto-Umsatz);
  /// `null` ohne Umsatz.
  final double? wareneinsatzAbdeckungPct;

  /// „Gewinn": Umsatz netto − Wareneinsatz; `null` wenn Wareneinsatz fehlt.
  final int? rohertragNettoCents;

  /// Nur Vergleichswert (enthält USt) — UI klein + Tooltip.
  final int? rohertragBruttoCents;

  /// Δ Umsatz brutto zur Vorperiode in %; `null` ohne Vergleichsbasis.
  final double? deltaVorperiodePct;

  /// Δ Umsatz brutto zur gleichen Periode des Vorjahres in %;
  /// `null` ohne geladene Vorjahres-Daten.
  final double? deltaVorjahrPct;
}

class _PeriodAgg {
  int sales = 0;
  int refunds = 0;
  int positiveRefunds = 0;
  int gross = 0;
  int net = 0;
  int netUncovered = 0;
  int cogs = 0;
  bool anyCogs = false;
  int cogsCoveredGross = 0;
  int statDays = 0;
}

/// Berechnet den Kassenbericht: die letzten [bucketCount] Perioden (Default
/// [ReportGranularityX.defaultBucketCount]), endend mit der Periode von [now],
/// älteste zuerst. [stats] dürfen mehr Tage enthalten als das Fenster — ältere
/// Tage speisen dann die Vorperioden-/Vorjahres-Vergleiche.
///
/// [coverageFrom] = Beginn des GELADENEN Datenfensters (M4: `now − 92 Tage`).
/// Beginnt eine Vergleichsperiode davor, wäre ihr Wert am Fensterrand
/// abgeschnitten — die Δ-Werte werden dann `null` statt grob falsch.
List<KassenPeriode> computeKassenbericht({
  required List<PosDailyStat> stats,
  required List<PurchaseOrder> orders,
  required ReportGranularity granularity,
  required DateTime now,
  int? bucketCount,
  String? siteId,
  DateTime? coverageFrom,
  // Org-Schalter §3.4: ob die erfassten Einkaufspreise MwSt enthalten. Steuert
  // die Netto/Brutto-Aufteilung der Käufe (M6-B) — konsistent mit dem EK für
  // den Wareneinsatz.
  bool purchasePricesIncludeVat = false,
}) {
  final count = (bucketCount ?? granularity.defaultBucketCount).clamp(1, 1000);

  // ALLE Stats bucketen (auch außerhalb des Fensters) — Basis der Vergleiche.
  final aggByStart = <DateTime, _PeriodAgg>{};
  for (final stat in stats) {
    if (siteId != null && siteId.isNotEmpty && stat.siteId != siteId) continue;
    final day = DateTime.tryParse(stat.businessDay);
    if (day == null) continue;
    final agg = aggByStart.putIfAbsent(
      _bucketStart(day, granularity),
      () => _PeriodAgg(),
    );
    agg.statDays += 1;
    agg.sales += stat.salesCount;
    agg.refunds += stat.refundCount;
    agg.positiveRefunds += stat.positiveRefundCount;
    agg.gross += stat.revenueGrossCents;
    agg.net += stat.revenueNetCents;
    agg.netUncovered += stat.netUncoveredGrossCents;
    final cogs = stat.cogsCents;
    if (cogs != null) {
      agg.anyCogs = true;
      agg.cogs += cogs;
      agg.cogsCoveredGross += stat.cogsCoveredGrossCents;
    }
  }

  final kaeufeNettoByStart = <DateTime, int>{};
  final kaeufeBruttoByStart = <DateTime, int>{};
  for (final order in orders) {
    if (order.status == PurchaseOrderStatus.draft ||
        order.status == PurchaseOrderStatus.cancelled) {
      continue;
    }
    if (siteId != null && siteId.isNotEmpty && order.siteId != siteId) continue;
    final when = order.orderedAt ?? order.createdAt;
    if (when == null) continue;
    final start = _bucketStart(when, granularity);
    kaeufeNettoByStart[start] = (kaeufeNettoByStart[start] ?? 0) +
        order.totalNetCents(priceIncludesVat: purchasePricesIncludeVat);
    kaeufeBruttoByStart[start] = (kaeufeBruttoByStart[start] ?? 0) +
        order.totalGrossCents(priceIncludesVat: purchasePricesIncludeVat);
  }

  final starts = <DateTime>[];
  final currentStart = _bucketStart(now, granularity);
  for (var i = count - 1; i >= 0; i--) {
    starts.add(_shiftBuckets(currentStart, -i, granularity));
  }

  // Vergleichsperioden nur werten, wenn sie VOLLSTÄNDIG im geladenen
  // Fenster liegen (sonst null-Δ statt Vergleich gegen einen Randstummel).
  _PeriodAgg? covered(DateTime refStart) {
    if (coverageFrom != null && refStart.isBefore(coverageFrom)) return null;
    return aggByStart[refStart];
  }

  return [
    for (final start in starts)
      _buildPeriode(
        start: start,
        agg: aggByStart[start],
        kaeufeNettoCents: kaeufeNettoByStart[start] ?? 0,
        kaeufeBruttoCents: kaeufeBruttoByStart[start] ?? 0,
        vorperiode: covered(_shiftBuckets(start, -1, granularity)),
        vorjahr: covered(_previousYearStart(start, granularity)),
      ),
  ];
}

KassenPeriode _buildPeriode({
  required DateTime start,
  required _PeriodAgg? agg,
  required int kaeufeNettoCents,
  required int kaeufeBruttoCents,
  required _PeriodAgg? vorperiode,
  required _PeriodAgg? vorjahr,
}) {
  final hatDaten = agg != null && agg.statDays > 0;
  final gross = agg?.gross ?? 0;
  final net = agg?.net ?? 0;
  final cogs = (agg != null && agg.anyCogs) ? agg.cogs : null;
  return KassenPeriode(
    start: start,
    hatDaten: hatDaten,
    belege: agg?.sales ?? 0,
    erstattungen: agg?.refunds ?? 0,
    positiveErstattungen: agg?.positiveRefunds ?? 0,
    umsatzBruttoCents: gross,
    umsatzNettoCents: net,
    nettoUnsicherCents: agg?.netUncovered ?? 0,
    kaeufeNettoCents: kaeufeNettoCents,
    kaeufeBruttoCents: kaeufeBruttoCents,
    wareneinsatzCents: cogs,
    wareneinsatzAbdeckungPct: (agg != null && gross > 0)
        ? (agg.cogsCoveredGross / gross * 100).clamp(0, 100).toDouble()
        : null,
    rohertragNettoCents: cogs == null ? null : net - cogs,
    rohertragBruttoCents: cogs == null ? null : gross - cogs,
    deltaVorperiodePct: _deltaPct(gross, hatDaten, vorperiode),
    deltaVorjahrPct: _deltaPct(gross, hatDaten, vorjahr),
  );
}

double? _deltaPct(int currentGross, bool hatDaten, _PeriodAgg? reference) {
  if (!hatDaten || reference == null || reference.statDays == 0) return null;
  // Referenz <= 0 (kein Umsatz bzw. refund-lastige Periode): eine Division
  // würde das Vorzeichen invertieren — lieber kein Δ als ein irreführendes.
  if (reference.gross <= 0) return null;
  return (currentGross - reference.gross) / reference.gross * 100;
}

DateTime _bucketStart(DateTime date, ReportGranularity granularity) =>
    switch (granularity) {
      ReportGranularity.week => startOfIsoWeek(date),
      ReportGranularity.month => startOfMonth(date),
      ReportGranularity.year => DateTime(date.year, 1, 1),
    };

DateTime _shiftBuckets(
  DateTime start,
  int buckets,
  ReportGranularity granularity,
) =>
    switch (granularity) {
      // Über die Tagesdifferenz statt add(Duration) — DST-sicher date-only.
      ReportGranularity.week => DateTime(
          start.year,
          start.month,
          start.day + 7 * buckets,
        ),
      ReportGranularity.month => DateTime(start.year, start.month + buckets, 1),
      ReportGranularity.year => DateTime(start.year + buckets, 1, 1),
    };

/// Beginn der Vorjahres-Vergleichsperiode. Für Wochen: −364 Tage (52 Wochen,
/// gleicher Wochentag → in Jahren ohne KW 53 exakt dieselbe ISO-KW; bewusste,
/// dokumentierte Näherung). Monat/Jahr: Kalender-Vorjahr.
DateTime _previousYearStart(DateTime start, ReportGranularity granularity) =>
    switch (granularity) {
      ReportGranularity.week =>
        DateTime(start.year, start.month, start.day - 364),
      ReportGranularity.month => DateTime(start.year - 1, start.month, 1),
      ReportGranularity.year => DateTime(start.year - 1, 1, 1),
    };

/// **Übergangs-Adapter (M4, bis die serverseitigen `posDailyStats` deployt
/// sind):** berechnet dieselben Tagesaggregate clientseitig aus einem
/// begrenzten Belege-Fenster (≤ 92 Tage laden!). Gleiche Tageszuordnung wie
/// `computeDailyClosings` (`businessDay` ?? Kalendertag aus `transactionDate`).
///
/// [purchasePricesIncludeVat] = Org-Schalter §3.4: bei `true` werden EK-Preise
/// als brutto interpretiert und über `Product.taxRatePercent` auf netto
/// normalisiert; Artikel ohne Steuersatz gelten dann als unbewertet.
List<PosDailyStat> dailyStatsFromReceipts(
  List<PosReceipt> receipts,
  List<Product> products, {
  required bool purchasePricesIncludeVat,
}) {
  final ekNettoById = <String, int>{};
  for (final product in products) {
    final id = product.id;
    final ek = product.purchasePriceCents;
    if (id == null || ek == null) continue;
    if (!purchasePricesIncludeVat) {
      ekNettoById[id] = ek;
      continue;
    }
    final rate = product.taxRatePercent;
    if (rate == null || rate < 0) continue; // unbewertet, kein stilles Raten
    // Kopplung Plan §11.11: identische Netto-Normalisierung muss ab M5 im
    // Server-COGS (functions/index.js, posDailyStats-Fortschreibung)
    // gespiegelt werden — Formel-Änderung immer an beiden Stellen.
    ekNettoById[id] = (ek / (1 + rate / 100)).round();
  }

  // key: "siteId|businessDay"
  final agg = <String, _DayAgg>{};
  for (final r in receipts) {
    if (r.training) continue;
    final day = (r.businessDay != null && r.businessDay!.trim().isNotEmpty)
        ? r.businessDay!.trim()
        : _dayOf(r.transactionDate);
    if (day == null) continue;
    final a = agg.putIfAbsent(
      '${r.siteId}|$day',
      () => _DayAgg(orgId: r.orgId, siteId: r.siteId, businessDay: day),
    );

    final type = (r.type ?? '').toLowerCase();
    if (type == 'cash') {
      a.cashMovement += r.grossCents ?? 0;
      continue;
    }
    if (!r.isRevenue) continue;

    if (type == 'refund') {
      a.refunds += 1;
      // Vorzeichen-Verdacht (A8): Erstattungen sollten negativ ankommen.
      if ((r.grossCents ?? 0) > 0) a.positiveRefunds += 1;
    } else {
      a.sales += 1;
    }
    a.gross += r.grossCents ?? 0;

    // Netto: nur aus vollständigen Steuerzeilen; sonst offen ausweisen.
    // Die Steuer-Eimer darunter bleiben bewusst tolerant gefüllt (Overlap,
    // gleiche Semantik wie computeDailyClosings — siehe PosDailyStat.taxes).
    if (r.taxes.isEmpty || r.taxes.any((t) => t.netCents == null)) {
      a.netUncovered += r.grossCents ?? 0;
    } else {
      a.net += r.taxes.fold<int>(0, (s, t) => s + t.netCents!);
    }
    for (final t in r.taxes) {
      final key = t.ratePercent ?? -1;
      final bucket = a.taxByRate.putIfAbsent(key, () => [0, 0, 0]);
      bucket[0] += t.netCents ?? 0;
      bucket[1] += t.taxCents ?? 0;
      bucket[2] += t.grossCents ?? 0;
    }
    for (final p in r.payments) {
      final method = (p.method == null || p.method!.trim().isEmpty)
          ? 'unbekannt'
          : p.method!.trim();
      a.payments[method] = (a.payments[method] ?? 0) + (p.amountCents ?? 0);
    }
    for (final line in r.lines) {
      final pid = line.productId;
      if (pid == null || line.quantity == 0) continue;
      final ekNetto = ekNettoById[pid];
      if (ekNetto == null) continue;
      a.anyCogs = true;
      a.cogs += line.quantity * ekNetto;
      final unit = line.realizedUnitPriceCents;
      if (unit != null && unit >= 0) {
        a.cogsCoveredGross += line.quantity * unit;
      }
    }
  }

  final result = agg.values.map((a) {
    final taxes = a.taxByRate.entries
        .map((e) => ReceiptTax(
              ratePercent: e.key < 0 ? null : e.key,
              netCents: e.value[0],
              taxCents: e.value[1],
              grossCents: e.value[2],
            ))
        .toList()
      ..sort((x, y) => (y.ratePercent ?? -1).compareTo(x.ratePercent ?? -1));
    return PosDailyStat(
      orgId: a.orgId,
      siteId: a.siteId,
      businessDay: a.businessDay,
      salesCount: a.sales,
      refundCount: a.refunds,
      positiveRefundCount: a.positiveRefunds,
      revenueGrossCents: a.gross,
      revenueNetCents: a.net,
      netUncoveredGrossCents: a.netUncovered,
      taxes: taxes,
      paymentsByMethod: Map<String, int>.unmodifiable(a.payments),
      cashMovementCents: a.cashMovement,
      cogsCents: a.anyCogs ? a.cogs : null,
      cogsCoveredGrossCents: a.cogsCoveredGross,
    );
  }).toList()
    ..sort((x, y) {
      final c = y.businessDay.compareTo(x.businessDay);
      return c != 0 ? c : x.siteId.compareTo(y.siteId);
    });
  return result;
}

class _DayAgg {
  _DayAgg({required this.orgId, required this.siteId, required this.businessDay});

  final String orgId;
  final String siteId;
  final String businessDay;
  int sales = 0;
  int refunds = 0;
  int positiveRefunds = 0;
  int gross = 0;
  int net = 0;
  int netUncovered = 0;
  int cashMovement = 0;
  int cogs = 0;
  bool anyCogs = false;
  int cogsCoveredGross = 0;
  // ratePercent (oder -1 für unbekannt) -> [net, tax, gross]
  final Map<int, List<int>> taxByRate = {};
  final Map<String, int> payments = {};
}

String? _dayOf(DateTime? tx) {
  if (tx == null) return null;
  return '${tx.year}-${tx.month.toString().padLeft(2, '0')}-'
      '${tx.day.toString().padLeft(2, '0')}';
}
