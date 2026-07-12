"use strict";

// Regressionstests fuer zwei Sicherheits-/Spiegel-Fixes (Sicherheits-Audit
// 2026-07 / Probleme/gb_prob_2026-07-12.md):
//
// K3  — Cross-Tenant-Schicht-Schreiben: parseShift uebernimmt ein
//       client-geliefertes org_id; enforceShiftOrg muss es vor dem
//       Admin-SDK-Write hart auf die gegen den Caller geprueften orgId setzen.
// H7  — Split-Shift-Guard: singleRestGapViolations darf zwei getrennte
//       Ein-Tages-Schichten am selben Kalendertag NICHT als Ruhezeit-Verstoss
//       werten (Dart-Spiegel _shouldEnforceRestGap prueft das im Schicht-Pfad).

const test = require("node:test");
const assert = require("node:assert/strict");

const {parseShift, enforceShiftOrg, singleRestGapViolations, shouldEnforceRestGap} =
  require("../index.js")._testables;

function rawShift(overrides = {}) {
  return {
    id: "shift-1",
    org_id: "org-1",
    user_id: "user-1",
    employee_name: "Anna",
    title: "Fruehdienst",
    start_time: "2026-04-01T08:00:00.000",
    end_time: "2026-04-01T12:00:00.000",
    break_minutes: 0,
    status: "planned",
    ...overrides,
  };
}

test("K3: parseShift uebernimmt fremdes org_id aus dem Payload (Angriffsvektor)", () => {
  const shift = parseShift(rawShift({org_id: "org-fremd"}), 0, "org-1");
  assert.equal(shift.orgId, "org-fremd",
    "parseShift selbst bleibt tolerant — genau deshalb MUSS enforceShiftOrg greifen");
});

test("K3: enforceShiftOrg erzwingt die Caller-Org auf jeder Schicht", () => {
  const shifts = enforceShiftOrg(
    [
      parseShift(rawShift({org_id: "org-fremd", id: "opfer-schicht"}), 0, "org-1"),
      parseShift(rawShift({id: "shift-2"}), 1, "org-1"),
    ],
    "org-1",
  );
  assert.ok(shifts.every((shift) => shift.orgId === "org-1"),
    "kein manipuliertes org_id darf den Ziel-Pfad des Admin-SDK-Writes bestimmen");
  assert.equal(shifts[0].id, "opfer-schicht", "uebrige Felder bleiben erhalten");
});

const ruleSet = {minRestMinutes: 660};

function shift(id, startIso, endIso) {
  return {
    id,
    orgId: "org-1",
    userId: "user-1",
    siteId: "site-1",
    startTime: new Date(startIso),
    endTime: new Date(endIso),
    breakMinutes: 0,
  };
}

test("H7: Split-Shift am selben Tag loest KEIN rest_time aus (Guard, Dart-Spiegel)", () => {
  const violations = singleRestGapViolations({
    earlier: shift("s-1", "2026-04-01T08:00:00", "2026-04-01T12:00:00"),
    later: shift("s-2", "2026-04-01T14:00:00", "2026-04-01T18:00:00"),
    ruleSet,
    travelTimeRules: [],
    siteAssignments: [],
    contract: null,
  });
  assert.deepEqual(violations, [],
    "geteilter Dienst (Luecke 120 min am selben Tag) ist legitime Planung");
});

test("H7: Ruhezeit zwischen zwei Arbeitstagen wird weiterhin geprueft", () => {
  const violations = singleRestGapViolations({
    earlier: shift("s-1", "2026-04-01T14:00:00", "2026-04-01T22:00:00"),
    later: shift("s-2", "2026-04-02T06:00:00", "2026-04-02T14:00:00"),
    ruleSet,
    travelTimeRules: [],
    siteAssignments: [],
    contract: null,
  });
  assert.ok(violations.some((violation) => violation.code === "rest_time"),
    "8h Luecke ueber Nacht < 660 min muss weiterhin blocken");
});

test("H7: shouldEnforceRestGap-Grenzfaelle bleiben stabil", () => {
  // Uebernacht-Schicht endet am Folgetag -> Ruhe zum naechsten Start zaehlt.
  assert.equal(
    shouldEnforceRestGap(
      new Date("2026-04-01T22:00:00"),
      new Date("2026-04-02T06:00:00"),
      new Date("2026-04-02T14:00:00"),
    ),
    true,
  );
  // Zwei Ein-Tages-Bloecke am selben Tag -> keine Tagesruhe dazwischen.
  assert.equal(
    shouldEnforceRestGap(
      new Date("2026-04-01T08:00:00"),
      new Date("2026-04-01T12:00:00"),
      new Date("2026-04-01T14:00:00"),
    ),
    false,
  );
});
