"use strict";

const {test} = require("node:test");
const assert = require("node:assert");
const {
  pickClosestShiftId,
  SHIFT_MATCH_WINDOW_MS,
} = require("../kiosk_shift");

const NOW = 1_700_000_000_000; // fixer Stempelzeitpunkt (ms)

test("leere/ungültige Kandidaten → null", () => {
  assert.equal(pickClosestShiftId([], NOW), null);
  assert.equal(pickClosestShiftId(null, NOW), null);
  assert.equal(pickClosestShiftId(undefined, NOW), null);
});

test("nicht-endliches nowMs → null", () => {
  assert.equal(
    pickClosestShiftId([{id: "s1", startMs: NOW}], Number.NaN),
    null,
  );
});

test("wählt die Schicht mit geringstem Abstand zu jetzt", () => {
  const candidates = [
    {id: "morgens", startMs: NOW - 5 * 3600 * 1000}, // 5 h her
    {id: "gleich", startMs: NOW + 30 * 60 * 1000}, // in 30 min
    {id: "abends", startMs: NOW + 8 * 3600 * 1000}, // in 8 h
  ];
  assert.equal(pickClosestShiftId(candidates, NOW), "gleich");
});

test("gerade begonnene Schicht (kurz vor jetzt) gewinnt", () => {
  const candidates = [
    {id: "laeuft", startMs: NOW - 5 * 60 * 1000}, // vor 5 min begonnen
    {id: "spaeter", startMs: NOW + 3 * 3600 * 1000},
  ];
  assert.equal(pickClosestShiftId(candidates, NOW), "laeuft");
});

test("überspringt Einträge ohne id oder ohne endlichen Start", () => {
  const candidates = [
    {id: "", startMs: NOW}, // leere id → skip
    {id: "kaputt", startMs: null}, // kein Start → skip
    {id: "ok", startMs: NOW + 2 * 3600 * 1000},
  ];
  assert.equal(pickClosestShiftId(candidates, NOW), "ok");
});

test("nur ungültige Kandidaten → null", () => {
  const candidates = [
    {id: "", startMs: NOW},
    {startMs: NOW},
    {id: "x", startMs: "keineZahl"},
  ];
  assert.equal(pickClosestShiftId(candidates, NOW), null);
});

test("bei Gleichstand gewinnt der zuerst gelistete (stabile Sortierung)", () => {
  const candidates = [
    {id: "frueher", startMs: NOW - 60 * 60 * 1000},
    {id: "spaeter", startMs: NOW + 60 * 60 * 1000}, // gleicher Abstand
  ];
  assert.equal(pickClosestShiftId(candidates, NOW), "frueher");
});

test("Fenster-Konstante ist ±12 h", () => {
  assert.equal(SHIFT_MATCH_WINDOW_MS, 12 * 60 * 60 * 1000);
});
