"use strict";

// Roundtrip-Tests für das Shift-Feld overtimeMinutes durch die drei
// Serialisierungs-Stellen in index.js (parseShift snake_case ->
// toFirestoreShift camelCase -> fromFirestoreShift). toFirestoreShift ist
// destruktiv: fehlt ein Feld in der Schreib-Map, wird es bei jedem
// Callable-Update gelöscht — deshalb wird die Schreib-Map explizit geprüft.

const test = require("node:test");
const assert = require("node:assert/strict");

const {parseShift, toFirestoreShift, fromFirestoreShift} =
  require("../index.js")._testables;

// Minimaler snake_case-Callable-Payload (Client-Format toMap()).
function rawShift(overrides = {}) {
  return {
    id: "shift-1",
    org_id: "org-1",
    user_id: "user-1",
    employee_name: "Anna",
    title: "Spätdienst",
    start_time: "2026-04-01T14:00:00.000",
    end_time: "2026-04-01T22:00:00.000",
    break_minutes: 30,
    status: "planned",
    ...overrides,
  };
}

test("parseShift: overtime_minutes wird tolerant gelesen (Zahl)", () => {
  const shift = parseShift(rawShift({overtime_minutes: 90}), 0, "org-1");
  assert.equal(shift.overtimeMinutes, 90);
});

test("parseShift: overtime_minutes fehlt -> Default 0", () => {
  const shift = parseShift(rawShift(), 0, "org-1");
  assert.equal(shift.overtimeMinutes, 0);
});

test("parseShift: overtime_minutes tolerant bei String/Murks", () => {
  assert.equal(
    parseShift(rawShift({overtime_minutes: "45"}), 0, "org-1").overtimeMinutes,
    45,
  );
  assert.equal(
    parseShift(rawShift({overtime_minutes: 30.9}), 0, "org-1").overtimeMinutes,
    30,
  );
  assert.equal(
    parseShift(rawShift({overtime_minutes: "kaputt"}), 0, "org-1")
      .overtimeMinutes,
    0,
  );
  assert.equal(
    parseShift(rawShift({overtime_minutes: null}), 0, "org-1").overtimeMinutes,
    0,
  );
});

test("toFirestoreShift: overtimeMinutes steht in der Schreib-Map (camelCase)", () => {
  const shift = parseShift(rawShift({overtime_minutes: 60}), 0, "org-1");
  const map = toFirestoreShift(shift, "caller-uid", null);
  assert.equal(map.overtimeMinutes, 60);
});

test("toFirestoreShift: fehlendes Feld schreibt 0 (destruktive Map bleibt vollständig)", () => {
  const shift = parseShift(rawShift(), 0, "org-1");
  const map = toFirestoreShift(shift, "caller-uid", null);
  assert.equal(map.overtimeMinutes, 0);
});

test("Roundtrip parseShift -> toFirestoreShift -> fromFirestoreShift erhält overtimeMinutes", () => {
  const parsed = parseShift(rawShift({overtime_minutes: 75}), 0, "org-1");
  const written = toFirestoreShift(parsed, "caller-uid", null);
  const restored = fromFirestoreShift({id: "shift-1", data: () => written});
  assert.equal(restored.overtimeMinutes, 75);
});

test("fromFirestoreShift: Alt-Dokument ohne overtimeMinutes -> Default 0", () => {
  const restored = fromFirestoreShift({
    id: "shift-legacy",
    data: () => ({
      orgId: "org-1",
      userId: "user-1",
      employeeName: "Anna",
      title: "Frühdienst",
      startTime: "2026-04-01T08:00:00.000Z",
      endTime: "2026-04-01T16:00:00.000Z",
      status: "planned",
    }),
  });
  assert.equal(restored.overtimeMinutes, 0);
});
