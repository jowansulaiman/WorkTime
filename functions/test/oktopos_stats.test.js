"use strict";

const test = require("node:test");
const assert = require("node:assert");
const stats = require("../oktopos_stats");

// Beleg-Fabrik: erzeugt ein posReceipts-artiges Objekt fuer computeDailyStats.
function receipt(overrides) {
  const type = overrides.type || "sales";
  return {
    siteId: "site-1",
    businessDay: overrides.businessDay ?? "2026-06-30",
    transactionDate: overrides.transactionDate ?? null,
    type,
    training: overrides.training === true,
    isRevenue: overrides.isRevenue ?? (type === "sales" || type === "refund"),
    grossCents: overrides.grossCents ?? null,
    taxes: overrides.taxes || [],
    payments: overrides.payments || [],
    lines: overrides.lines || [],
  };
}

test("ekNettoByProduct: netto uebernimmt EK 1:1", () => {
  const map = stats.ekNettoByProduct(
    [{id: "a", purchasePriceCents: 100, taxRatePercent: 19}],
    {purchasePricesIncludeVat: false},
  );
  assert.strictEqual(map.get("a"), 100);
});

test("ekNettoByProduct: brutto normalisiert ueber taxRatePercent", () => {
  const map = stats.ekNettoByProduct(
    [
      {id: "a", purchasePriceCents: 119, taxRatePercent: 19}, // -> 100
      {id: "b", purchasePriceCents: 107, taxRatePercent: 7}, // -> 100
      {id: "c", purchasePriceCents: 50, taxRatePercent: null}, // unbewertet
    ],
    {purchasePricesIncludeVat: true},
  );
  assert.strictEqual(map.get("a"), 100);
  assert.strictEqual(map.get("b"), 100);
  assert.strictEqual(map.has("c"), false);
});

test("ekNettoByProduct: EK 0 ist gueltig, fehlender EK wird uebersprungen", () => {
  const map = stats.ekNettoByProduct(
    [
      {id: "a", purchasePriceCents: 0, taxRatePercent: 19},
      {id: "b", purchasePriceCents: null, taxRatePercent: 19},
    ],
    {purchasePricesIncludeVat: false},
  );
  assert.strictEqual(map.get("a"), 0);
  assert.strictEqual(map.has("b"), false);
});

test("computeDailyStats: Umsatz brutto/netto, Steuer-Split, Zahlarten", () => {
  const out = stats.computeDailyStats([
    receipt({
      grossCents: 1190,
      taxes: [{ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190}],
      payments: [{method: "bar", amountCents: 1190}],
    }),
    receipt({
      grossCents: 107,
      taxes: [{ratePercent: 7, netCents: 100, taxCents: 7, grossCents: 107}],
      payments: [{method: "karte", amountCents: 107}],
    }),
  ], new Map());

  assert.strictEqual(out.length, 1);
  const s = out[0];
  assert.strictEqual(s.businessDay, "2026-06-30");
  assert.strictEqual(s.salesCount, 2);
  assert.strictEqual(s.revenueGrossCents, 1297);
  assert.strictEqual(s.revenueNetCents, 1100);
  assert.strictEqual(s.netUncoveredGrossCents, 0);
  // Steuer-Eimer absteigend nach Satz.
  assert.strictEqual(s.taxes[0].ratePercent, 19);
  assert.strictEqual(s.taxes[1].ratePercent, 7);
  assert.strictEqual(s.paymentsByMethod.bar, 1190);
  assert.strictEqual(s.paymentsByMethod.karte, 107);
});

test("computeDailyStats: cash/training zaehlen nicht zum Umsatz", () => {
  const out = stats.computeDailyStats([
    receipt({grossCents: 500}),
    receipt({type: "cash", grossCents: -2000, isRevenue: false}),
    receipt({grossCents: 999, training: true}),
  ], new Map());
  const s = out[0];
  assert.strictEqual(s.salesCount, 1);
  assert.strictEqual(s.revenueGrossCents, 500);
  assert.strictEqual(s.cashMovementCents, -2000);
});

test("computeDailyStats: fehlende Steuerzeile -> nettoUnsicher, nicht geraten", () => {
  const out = stats.computeDailyStats([
    receipt({grossCents: 500}), // keine taxes
  ], new Map());
  assert.strictEqual(out[0].revenueNetCents, 0);
  assert.strictEqual(out[0].netUncoveredGrossCents, 500);
});

test("computeDailyStats: positive Erstattung als A8-Vorzeichen-Verdacht", () => {
  const out = stats.computeDailyStats([
    receipt({type: "refund", grossCents: 300}),
    receipt({type: "refund", grossCents: -100}),
  ], new Map());
  assert.strictEqual(out[0].refundCount, 2);
  assert.strictEqual(out[0].positiveRefundCount, 1);
});

test("computeDailyStats: COGS mit Netto-EK, unbewertete Zeile senkt Abdeckung", () => {
  const ek = new Map([["a", 100]]); // b fehlt
  const out = stats.computeDailyStats([
    receipt({
      grossCents: 900,
      lines: [
        {productId: "a", quantity: 2, unitPriceCents: 300, discountCents: 0},
        {productId: "b", quantity: 1, unitPriceCents: 300, discountCents: 0},
      ],
    }),
  ], ek);
  assert.strictEqual(out[0].cogsCents, 200); // 2 x 100
  assert.strictEqual(out[0].cogsCoveredGrossCents, 600); // 2 x 300
});

test("computeDailyStats: Refund senkt COGS auch bei positiver Rohmenge (M8)", () => {
  const ek = new Map([["a", 100]]);
  const out = stats.computeDailyStats([
    receipt({
      grossCents: 900,
      lines: [{productId: "a", quantity: 3, unitPriceCents: 300}],
    }),
    receipt({
      type: "refund",
      grossCents: -300,
      // OktoPOS liefert die Erstattungsmenge i.d.R. POSITIV.
      lines: [{productId: "a", quantity: 1, unitPriceCents: 300}],
    }),
  ], ek);
  assert.strictEqual(out[0].cogsCents, 200,
    "3x Verkauf (300) minus 1x Erstattung (100) = 200 — frueher stieg der " +
    "Wareneinsatz bei Refunds faelschlich auf 400");
  assert.strictEqual(out[0].cogsCoveredGrossCents, 600); // 900 - 300
});

test("computeDailyStats: kein bewertbarer Posten -> cogsCents null", () => {
  const out = stats.computeDailyStats([
    receipt({grossCents: 100, lines: [{productId: "x", quantity: 1, unitPriceCents: 100}]}),
  ], new Map());
  assert.strictEqual(out[0].cogsCents, null);
});

test("computeDailyStats: Fallback auf transactionDate-Kalendertag", () => {
  const out = stats.computeDailyStats([
    receipt({businessDay: null, transactionDate: new Date("2026-06-30T18:45:00Z"), grossCents: 100}),
  ], new Map());
  assert.strictEqual(out[0].businessDay, "2026-06-30");
});

test("computeDailyStats: trennt Geschaeftstage, sortiert absteigend", () => {
  const out = stats.computeDailyStats([
    receipt({businessDay: "2026-06-29", grossCents: 100}),
    receipt({businessDay: "2026-06-30", grossCents: 200}),
  ], new Map());
  assert.strictEqual(out.length, 2);
  assert.strictEqual(out[0].businessDay, "2026-06-30"); // neuester zuerst
});

test("computeDailyStats: Idempotenz — zweifache Aggregation identisch", () => {
  const input = [
    receipt({
      grossCents: 1190,
      taxes: [{ratePercent: 19, netCents: 1000, taxCents: 190, grossCents: 1190}],
      lines: [{productId: "a", quantity: 1, unitPriceCents: 1190}],
    }),
  ];
  const ek = new Map([["a", 600]]);
  const a = stats.computeDailyStats(input, ek);
  const b = stats.computeDailyStats(input, ek);
  assert.deepStrictEqual(a, b);
  // Belege gleich, aber EK geaendert -> COGS aendert sich bewusst (Richtwert).
  const c = stats.computeDailyStats(input, new Map([["a", 700]]));
  assert.strictEqual(a[0].cogsCents, 600);
  assert.strictEqual(c[0].cogsCents, 700);
  // Beleg-abgeleitete Felder bleiben stabil.
  assert.strictEqual(a[0].revenueGrossCents, c[0].revenueGrossCents);
  assert.strictEqual(a[0].revenueNetCents, c[0].revenueNetCents);
});
