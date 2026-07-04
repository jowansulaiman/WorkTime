"use strict";

const test = require("node:test");
const assert = require("node:assert");
const push = require("../push_notifications");

test("dedupeKey ist deterministisch und empfaengerspezifisch", () => {
  assert.strictEqual(
    push.dedupeKey("customer_wish", "w1", "u1"),
    "w1:customer_wish:u1",
  );
  assert.strictEqual(
    push.dedupeKey("customer_wish", "w1", "u1"),
    push.dedupeKey("customer_wish", "w1", "u1"),
  );
  assert.notStrictEqual(
    push.dedupeKey("customer_wish", "w1", "u1"),
    push.dedupeKey("customer_wish", "w1", "u2"),
  );
});

test("activeRecipientUids: nur aktive, dedupliziert, ohne Leer/null", () => {
  const uids = push.activeRecipientUids([
    {uid: "u1", isActive: true},
    {uid: "u2", isActive: false},
    {uid: "u1", isActive: true},
    {uid: "u3", isActive: true},
    {uid: "", isActive: true},
    null,
  ]);
  assert.deepStrictEqual(uids.sort(), ["u1", "u3"]);
});

test("buildWishNotification: deutsch, mit Laden, OHNE Kundenname (PII)", () => {
  const n = push.buildWishNotification({
    wishId: "w9",
    storeName: "Tabak Börse",
    wishText: "Bitte Sammelfigur Edition 7 besorgen",
    customerName: "Anna Schmidt",
  });
  assert.strictEqual(n.title, "Neuer Kundenwunsch");
  assert.strictEqual(n.type, "customer_wish");
  assert.strictEqual(n.route, "/kundenwuensche");
  assert.strictEqual(n.entityType, "customerWish");
  assert.strictEqual(n.entityId, "w9");
  assert.match(n.body, /Tabak Börse/);
  assert.ok(!/Anna/.test(n.body), "Kundenname darf NICHT im Body stehen");
});

test("buildWishNotification: leerer Laden/Wunsch -> sinnvolle Defaults", () => {
  const n = push.buildWishNotification({wishId: "w1", storeName: "", wishText: ""});
  assert.match(n.body, /^Laden: Neuer Wunsch eingegangen\./);
});

test("buildWishNotification kuerzt langen Wunschtext (Lock-Screen-Limit)", () => {
  const n = push.buildWishNotification({
    wishId: "w1",
    storeName: "S",
    wishText: "x".repeat(200),
  });
  assert.ok(n.body.length < 140, "Body zu lang");
  assert.ok(n.body.includes("…"), "kein Kuerzungs-Ellipsis");
});

test("stalePruneIndices: nur endgueltig ungueltige Tokens (nicht transiente)", () => {
  const responses = [
    {success: true},
    {success: false, error: {code: "messaging/registration-token-not-registered"}},
    {success: false, error: {code: "messaging/internal-error"}},
    {success: false, error: {code: "messaging/invalid-registration-token"}},
  ];
  assert.deepStrictEqual(push.stalePruneIndices(responses), [1, 3]);
});

// --- M3 ---

test("managerUids: aktiv UND (Admin ODER canEditSchedule), dedupliziert", () => {
  const uids = push.managerUids([
    {uid: "admin", isActive: true, isAdmin: true, canEditSchedule: false},
    {uid: "lead", isActive: true, isAdmin: false, canEditSchedule: true},
    {uid: "emp", isActive: true, isAdmin: false, canEditSchedule: false},
    {uid: "inactiveLead", isActive: false, isAdmin: false, canEditSchedule: true},
    {uid: "admin", isActive: true, isAdmin: true, canEditSchedule: false},
  ]);
  assert.deepStrictEqual(uids.sort(), ["admin", "lead"]);
});

test("formatDe/formatTimeDe: Berlin-Zeitzone (Sommerzeit +2)", () => {
  const d = new Date("2026-07-03T08:30:00Z"); // 10:30 Berlin
  assert.strictEqual(push.formatDe(d), "03.07.2026");
  assert.strictEqual(push.formatTimeDe(d), "10:30");
  assert.strictEqual(push.formatDe(null), "");
});

test("buildFeedbackNotification: Beschwerde = high, Lob = normal, kein PII", () => {
  const c = push.buildFeedbackNotification({feedbackId: "f1", type: "complaint", message: "Schlechte Beratung durch Mitarbeiter"});
  assert.strictEqual(c.priority, "high");
  assert.strictEqual(c.route, "/feedback-eingang");
  assert.match(c.title, /Beschwerde/);
  const p = push.buildFeedbackNotification({feedbackId: "f2", type: "praise", message: "x"});
  assert.strictEqual(p.priority, "normal");
  assert.match(p.title, /Lob/);
});

test("buildAbsenceDecisionNotification: genehmigt/abgelehnt deutsch", () => {
  const ok = push.buildAbsenceDecisionNotification({absenceId: "a1", typeLabel: "Urlaub", start: "12.07.2026", end: "19.07.2026", approved: true});
  assert.match(ok.title, /genehmigt/);
  assert.match(ok.body, /genehmigt/);
  assert.strictEqual(ok.route, "/zeit/abwesenheiten");
  const no = push.buildAbsenceDecisionNotification({absenceId: "a1", typeLabel: "Urlaub", start: "12.07.2026", approved: false});
  assert.match(no.title, /abgelehnt/);
});

test("buildSwapNotification: jede Phase eigener type (=> eigener Dedupe-Key)", () => {
  const phases = ["request", "accepted", "declined", "confirmed", "rejected"];
  const types = phases.map((p) => push.buildSwapNotification(p, {swapId: "s1", requesterName: "Peter", targetName: "Maria", shiftDate: "03.07.2026"}).type);
  assert.strictEqual(new Set(types).size, phases.length, "Phasen-Typen nicht eindeutig");
  // verschiedene Phasen -> verschiedene Dedupe-Keys fuer denselben Nutzer
  const keys = types.map((t) => push.dedupeKey(t, "s1", "u1"));
  assert.strictEqual(new Set(keys).size, phases.length);
  assert.strictEqual(push.buildSwapNotification("confirmed", {swapId: "s1"}).route, "/plan");
});

test("buildExpiryNotification: MHD-Text nach Restlaufzeit + Standort + type", () => {
  const soon = push.buildExpiryNotification({
    batchId: "b1", productName: "Cola 0,33l", siteName: "Tabak Börse",
    daysUntilExpiry: 2,
  });
  assert.strictEqual(soon.type, "expiry");
  assert.strictEqual(soon.entityType, "productBatch");
  assert.strictEqual(soon.entityId, "b1");
  assert.match(soon.title, /Tabak Börse/);
  assert.match(soon.body, /Cola 0,33l/);
  assert.match(soon.body, /in 2 Tagen ab/);

  assert.match(push.buildExpiryNotification({batchId: "b", daysUntilExpiry: 0}).body, /heute ab/);
  assert.match(push.buildExpiryNotification({batchId: "b", daysUntilExpiry: 1}).body, /morgen ab/);
  assert.match(push.buildExpiryNotification({batchId: "b", daysUntilExpiry: -2}).body, /seit 2 Tagen abgelaufen/);
  assert.match(push.buildExpiryNotification({batchId: "b", daysUntilExpiry: -1}).body, /seit 1 Tag abgelaufen/);
});

// --- M5: Präferenzen ---

test("channelIdForType (JS) deckt sich mit der Dart-Zuordnung", () => {
  assert.strictEqual(push.channelIdForType("absence_decision"), "genehmigungen");
  assert.strictEqual(push.channelIdForType("shift_published"), "schichtplan");
  assert.strictEqual(push.channelIdForType("customer_wish"), "kundenwuensche");
  assert.strictEqual(push.channelIdForType("low_stock"), "bestand");
  assert.strictEqual(push.channelIdForType("expiry"), "bestand");
  assert.strictEqual(push.channelIdForType("customer_feedback"), "aufgaben");
  assert.strictEqual(push.channelIdForType("xx"), "aufgaben");
});

test("inQuietWindow: über Mitternacht (22:00–06:00)", () => {
  assert.strictEqual(push.inQuietWindow(23 * 60, 1320, 360), true); // 23:00
  assert.strictEqual(push.inQuietWindow(2 * 60, 1320, 360), true); // 02:00
  assert.strictEqual(push.inQuietWindow(12 * 60, 1320, 360), false); // 12:00
  assert.strictEqual(push.inQuietWindow(6 * 60, 1320, 360), false); // genau Ende
});

test("pushAllowed: Master/Kategorie/Ruhezeit + Genehmigungen-Ausnahme", () => {
  // keine Prefs -> erlaubt
  assert.strictEqual(push.pushAllowed(null, "customer_wish", 0), true);
  // Master aus -> alles blockiert
  assert.strictEqual(
    push.pushAllowed({masterEnabled: false}, "customer_wish", 0), false);
  // Kategorie aus
  assert.strictEqual(
    push.pushAllowed({kundenwuensche: false}, "customer_wish", 0), false);
  // Ruhezeit blockiert normale Kategorie ...
  const quiet = {quietHoursEnabled: true, quietStartMinutes: 1320, quietEndMinutes: 360};
  assert.strictEqual(push.pushAllowed(quiet, "customer_wish", 23 * 60), false);
  // ... aber NICHT Genehmigungen (zeitkritisch)
  assert.strictEqual(push.pushAllowed(quiet, "absence_decision", 23 * 60), true);
  // ausserhalb der Ruhezeit normal erlaubt
  assert.strictEqual(push.pushAllowed(quiet, "customer_wish", 12 * 60), true);
});

// --- M7: Bündelung ---

test("isoWeek: gleiche Woche → gleicher Schlüssel, Folgewoche → anderer", () => {
  const wed = push.isoWeek(new Date("2026-07-01T10:00:00Z")); // Mi KW27
  const fri = push.isoWeek(new Date("2026-07-03T10:00:00Z")); // Fr KW27
  const nextMon = push.isoWeek(new Date("2026-07-06T10:00:00Z")); // Mo KW28
  assert.deepStrictEqual(wed, fri, "Mi und Fr sollten dieselbe KW sein");
  assert.notStrictEqual(`${fri.year}-${fri.week}`, `${nextMon.year}-${nextMon.week}`);
  assert.ok(wed.week >= 1 && wed.week <= 53);
  assert.strictEqual(push.isoWeek(null), null);
});

test("buildShiftPublishedNotification: wöchentlicher Text bei weekLabel", () => {
  const bundled = push.buildShiftPublishedNotification({
    shiftId: "s1", siteName: "Tabak Börse", date: "03.07.2026", weekLabel: "KW 27",
  });
  assert.match(bundled.body, /KW 27/);
  assert.ok(!/03\.07/.test(bundled.body), "gebündelt: kein Einzeldatum");
  const single = push.buildShiftPublishedNotification({
    shiftId: "s1", siteName: "", date: "03.07.2026",
  });
  assert.match(single.body, /03\.07\.2026/);
});

test("buildShiftPublishedNotification + buildLowStockNotification: Inhalt/Route", () => {
  const s = push.buildShiftPublishedNotification({shiftId: "sh1", siteName: "Tabak Börse", date: "03.07.2026"});
  assert.strictEqual(s.route, "/plan");
  assert.match(s.body, /Tabak Börse/);
  assert.match(s.body, /03\.07\.2026/);
  const l = push.buildLowStockNotification({productId: "p1", productName: "Cola 0,33", currentStock: 2, minStock: 6, siteName: ""});
  assert.strictEqual(l.route, "/warenwirtschaft?tab=korb");
  assert.match(l.body, /nur noch 2/);
  assert.match(l.body, /Meldebestand 6/);
});

test("buildAutoKlaerungNotification: Route/Thread/Dedupe + Datum im Text", () => {
  const n = push.buildAutoKlaerungNotification({
    clockEntryId: "ce1", dayLabel: "01.07.",
  });
  assert.strictEqual(n.type, "clock_auto_klaerung");
  assert.strictEqual(n.route, "/zeit/stempeln");
  assert.strictEqual(n.thread, "personal");
  assert.strictEqual(n.dedupeId, "klaerung:ce1");
  assert.match(n.body, /01\.07\./);
  // Fällt auf den Default-Channel (kein eigener personal-Channel, wie Dokument-Push).
  assert.strictEqual(push.channelIdForType("clock_auto_klaerung"),
    push.channelIdForType("personal_document"));
});

test("buildKlaerungResolvedNotification: Route/Thread/Dedupe + Stunden im Text", () => {
  const n = push.buildKlaerungResolvedNotification({
    clockEntryId: "ce9", dayLabel: "01.07.2026", hours: 8,
  });
  assert.strictEqual(n.type, "clock_klaerung_resolved");
  assert.strictEqual(n.route, "/zeit/stempeln");
  assert.strictEqual(n.thread, "personal");
  assert.strictEqual(n.dedupeId, "klaerung-resolved:ce9");
  assert.match(n.body, /01\.07\.2026/);
  assert.match(n.body, /8,0 h/);
  // Ohne Stunden: kein Klammer-Zusatz.
  const noHours = push.buildKlaerungResolvedNotification({
    clockEntryId: "ce9", dayLabel: "01.07.2026",
  });
  assert.ok(!/\(/.test(noHours.body));
});
