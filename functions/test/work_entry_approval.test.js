"use strict";

// Z6 (plan/zeit-schichtbindung-freigabe.md): serverseitige Durchsetzung des
// Freigabe-Workflows auf dem Callable-Pfad. Getestet wird die PURE
// Entscheidungsfunktion resolveWorkEntryApproval (ohne IO) + isReviewer.

const test = require("node:test");
const assert = require("node:assert/strict");

const {resolveWorkEntryApproval, isReviewer} =
  require("../index.js")._testables;

function caller(overrides = {}) {
  return {
    uid: "u-caller",
    isAdmin: false,
    permissions: {canEditSchedule: false, canEditTimeEntries: true},
    ...overrides,
  };
}

function entry(overrides = {}) {
  return {
    userId: "u-caller",
    status: "approved",
    correctionReason: null,
    approvedByUid: null,
    ...overrides,
  };
}

test("isReviewer: admin oder canEditSchedule", () => {
  assert.equal(isReviewer({isAdmin: true, permissions: {}}), true);
  assert.equal(isReviewer({isAdmin: false, permissions: {canEditSchedule: true}}), true);
  assert.equal(isReviewer({isAdmin: false, permissions: {canEditSchedule: false}}), false);
  assert.equal(isReviewer({isAdmin: false, permissions: {}}), false);
});

test("Eigen, Nicht-Admin: approved wird submitted + Freigabe geleert", () => {
  const d = resolveWorkEntryApproval({
    caller: caller(),
    entry: entry({status: "approved", approvedByUid: "x"}),
    existingStatus: null,
    materialChanged: false,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, true);
  assert.equal(d.status, "submitted");
  assert.equal(d.approvedByUid, null);
  assert.equal(d.clearApprovedAt, true);
  assert.equal(d.approvedAtServer, false);
});

test("Eigen, Admin: approved bleibt approved (ausgenommen)", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({isAdmin: true}),
    entry: entry({status: "approved", approvedByUid: "adm"}),
    existingStatus: "approved",
    materialChanged: true,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, true);
  assert.equal(d.status, "approved");
});

test("Eigen, Nicht-Admin: Korrektur eines genehmigten Eintrags ohne Grund → Fehler", () => {
  const d = resolveWorkEntryApproval({
    caller: caller(),
    entry: entry({status: "approved", correctionReason: "  "}),
    existingStatus: "approved",
    materialChanged: true,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, false);
  assert.equal(d.code, "failed-precondition");
});

test("Eigen, Nicht-Admin: Korrektur mit Grund → submitted", () => {
  const d = resolveWorkEntryApproval({
    caller: caller(),
    entry: entry({status: "approved", correctionReason: "Pause vergessen"}),
    existingStatus: "approved",
    materialChanged: true,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, true);
  assert.equal(d.status, "submitted");
});

test("Fremd, kein Freigeber → permission-denied", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({uid: "u-mgr"}),
    entry: entry({userId: "u-emp", status: "approved"}),
    existingStatus: "submitted",
    materialChanged: false,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, false);
  assert.equal(d.code, "permission-denied");
});

test("Fremd, Freigeber, Zielperson Admin → permission-denied", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({uid: "u-mgr", permissions: {canEditSchedule: true}}),
    entry: entry({userId: "u-adm", status: "approved"}),
    existingStatus: "submitted",
    materialChanged: false,
    targetIsAdmin: true,
  });
  assert.equal(d.ok, false);
  assert.equal(d.code, "permission-denied");
});

test("Fremd, Freigeber, Zielprofil fehlt (null) → permission-denied (fail-closed)", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({uid: "u-mgr", permissions: {canEditSchedule: true}}),
    entry: entry({userId: "u-emp", status: "approved"}),
    existingStatus: "submitted",
    materialChanged: false,
    targetIsAdmin: null,
  });
  assert.equal(d.ok, false);
  assert.equal(d.code, "permission-denied");
});

test("Fremd, Freigeber, Zielperson Nicht-Admin: approve → Genehmiger + Serverzeit", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({uid: "u-mgr", permissions: {canEditSchedule: true}}),
    entry: entry({userId: "u-emp", status: "approved"}),
    existingStatus: "submitted",
    materialChanged: false,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, true);
  assert.equal(d.status, "approved");
  assert.equal(d.approvedByUid, "u-mgr");
  assert.equal(d.approvedAtServer, true);
});

test("Fremd, Freigeber, Nicht-Admin-Ziel: submitted zurueckweisen → Freigabe leer", () => {
  const d = resolveWorkEntryApproval({
    caller: caller({uid: "u-mgr", permissions: {canEditSchedule: true}}),
    entry: entry({userId: "u-emp", status: "submitted"}),
    existingStatus: "approved",
    materialChanged: false,
    targetIsAdmin: false,
  });
  assert.equal(d.ok, true);
  assert.equal(d.status, "submitted");
  assert.equal(d.approvedByUid, null);
  assert.equal(d.clearApprovedAt, true);
});
