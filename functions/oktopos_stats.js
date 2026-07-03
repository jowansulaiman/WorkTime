"use strict";

// ===========================================================================
// Kassen-Modul M5 — posDailyStats-Aggregation (pure, node:test-testbar)
// ---------------------------------------------------------------------------
// **Spiegel von `dailyStatsFromReceipts` in lib/core/kasse_report.dart**
// (Kassen-Modul §3.3/§11.11). Verdichtet die Kassenbelege eines Standorts zu
// EINEM Tagesaggregat je Geschaeftstag. Aenderung der Rechenlogik hier IMMER
// mit dem Dart-Pendant mitziehen (gleiche Disziplin wie compliance_service.dart
// <-> functions/index.js).
//
// Idempotenz-Hinweis: Alle beleg-abgeleiteten Felder sind bei Re-Aggregation
// stabil; `cogsCents` wird mit dem jeweils AKTUELLEN Netto-EK bewertet (kein
// EK-Verlauf) und ist ein Richtwert — eine EK-Aenderung zwischen zwei Laeufen
// AENDERT cogsCents bewusst (dokumentiert, kein Idempotenz-Bruch).
// ===========================================================================

// 'YYYY-MM-DD' aus einem JS-Date. Fallback fuer Belege ohne `businessDay`
// (selten — echte OktoPOS-Belege tragen ihn). UTC-basiert; der Dart-Client
// nutzt die lokale Geraetezeit — fuer Belege MIT businessDay (Normalfall)
// identisch, nur der null-businessDay-Rand kann bei Zeitzonen abweichen.
function dayOf(date) {
  if (!date) return null;
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

// Netto-EK je Produkt-ID (spiegelt kasse_report.dart §3.4). Bei brutto-Schalter
// wird ueber `taxRatePercent` normalisiert; Artikel ohne Satz gelten dann als
// unbewertet (kein stilles Raten). Erwartet Produkte als
// {id, purchasePriceCents, taxRatePercent}.
function ekNettoByProduct(products, opts) {
  const includeVat = opts && opts.purchasePricesIncludeVat === true;
  const map = new Map();
  for (const p of products || []) {
    const id = p && p.id;
    const ek = p && p.purchasePriceCents;
    if (id == null || ek == null) continue;
    if (!includeVat) {
      map.set(id, ek);
      continue;
    }
    const rate = p.taxRatePercent;
    if (rate == null || rate < 0) continue; // unbewertet
    map.set(id, Math.round(ek / (1 + rate / 100)));
  }
  return map;
}

function newAgg(siteId, day) {
  return {
    siteId,
    day,
    sales: 0,
    refunds: 0,
    positiveRefunds: 0,
    gross: 0,
    net: 0,
    netUncovered: 0,
    cashMovement: 0,
    cogs: 0,
    anyCogs: false,
    cogsCoveredGross: 0,
    // ratePercent (oder -1 fuer unbekannt) -> [net, tax, gross]
    taxByRate: new Map(),
    payments: new Map(),
  };
}

// Verdichtet Belege zu Tagesaggregaten. `receipts`: Objekte mit
// {siteId, businessDay, transactionDate(Date|null), type, training, isRevenue,
//  grossCents, taxes[], payments[], lines[]}. `ekNettoById`: Map (s.o.).
// Gibt ein Array von Stat-Objekten zurueck (je (siteId, Geschaeftstag) eins).
function computeDailyStats(receipts, ekNettoById) {
  const ekMap = ekNettoById instanceof Map ? ekNettoById : new Map();
  const agg = new Map(); // "siteId|day"
  for (const r of receipts || []) {
    if (r == null || r.training === true) continue;
    const bd = typeof r.businessDay === "string" ? r.businessDay.trim() : "";
    const day = bd || dayOf(r.transactionDate);
    if (!day) continue;
    const key = `${r.siteId}|${day}`;
    let a = agg.get(key);
    if (!a) {
      a = newAgg(r.siteId, day);
      agg.set(key, a);
    }

    const type = String(r.type || "").toLowerCase();
    if (type === "cash") {
      a.cashMovement += r.grossCents || 0;
      continue;
    }
    if (r.isRevenue !== true) continue;

    if (type === "refund") {
      a.refunds += 1;
      // Vorzeichen-Verdacht (A8): Erstattungen sollten negativ ankommen.
      if ((r.grossCents || 0) > 0) a.positiveRefunds += 1;
    } else {
      a.sales += 1;
    }
    a.gross += r.grossCents || 0;

    const taxes = Array.isArray(r.taxes) ? r.taxes : [];
    // Netto nur aus VOLLSTAENDIGEN Steuerzeilen; sonst offen ausweisen.
    if (taxes.length === 0 || taxes.some((t) => t == null || t.netCents == null)) {
      a.netUncovered += r.grossCents || 0;
    } else {
      a.net += taxes.reduce((s, t) => s + (t.netCents || 0), 0);
    }
    for (const t of taxes) {
      if (t == null) continue;
      const rate = t.ratePercent == null ? -1 : t.ratePercent;
      let b = a.taxByRate.get(rate);
      if (!b) {
        b = [0, 0, 0];
        a.taxByRate.set(rate, b);
      }
      b[0] += t.netCents || 0;
      b[1] += t.taxCents || 0;
      b[2] += t.grossCents || 0;
    }
    const payments = Array.isArray(r.payments) ? r.payments : [];
    for (const p of payments) {
      if (p == null) continue;
      const method = typeof p.method === "string" && p.method.trim()
        ? p.method.trim() : "unbekannt";
      a.payments.set(method, (a.payments.get(method) || 0) + (p.amountCents || 0));
    }
    const lines = Array.isArray(r.lines) ? r.lines : [];
    for (const line of lines) {
      if (line == null) continue;
      const pid = line.productId;
      const qty = line.quantity || 0;
      if (pid == null || qty === 0) continue;
      const ekNetto = ekMap.get(pid);
      if (ekNetto == null) continue;
      a.anyCogs = true;
      a.cogs += qty * ekNetto;
      const unit = line.unitPriceCents == null
        ? null : line.unitPriceCents - (line.discountCents || 0);
      if (unit != null && unit >= 0) a.cogsCoveredGross += qty * unit;
    }
  }

  const out = [];
  for (const a of agg.values()) {
    const taxes = [...a.taxByRate.entries()]
      .map(([rate, v]) => ({
        ratePercent: rate < 0 ? null : rate,
        netCents: v[0],
        taxCents: v[1],
        grossCents: v[2],
      }))
      .sort((x, y) => (y.ratePercent == null ? -1 : y.ratePercent) -
        (x.ratePercent == null ? -1 : x.ratePercent));
    const paymentsByMethod = {};
    for (const [m, c] of a.payments) paymentsByMethod[m] = c;
    out.push({
      siteId: a.siteId,
      businessDay: a.day,
      salesCount: a.sales,
      refundCount: a.refunds,
      positiveRefundCount: a.positiveRefunds,
      revenueGrossCents: a.gross,
      revenueNetCents: a.net,
      netUncoveredGrossCents: a.netUncovered,
      taxes,
      paymentsByMethod,
      cashMovementCents: a.cashMovement,
      cogsCents: a.anyCogs ? a.cogs : null,
      cogsCoveredGrossCents: a.cogsCoveredGross,
    });
  }
  // Deterministische Reihenfolge (Geschaeftstag desc) — hilft Tests + Logs.
  out.sort((x, y) => (x.businessDay < y.businessDay ? 1 : (x.businessDay > y.businessDay ? -1 : 0)));
  return out;
}

module.exports = {
  dayOf,
  ekNettoByProduct,
  computeDailyStats,
};
