"use strict";

// Regressionstests fuer die OktoPOS-Sicherheits-/Integritaets-Fixes
// (Probleme/gb_prob_2026-07-12.md K4/H2/H3/H6, Audit K2/H3/H4/M4):
// Host-Allowlist gegen Key-Exfiltration, kein */default-Key-Fallback,
// stabile Idempotenz-IDs (siteId-Scope statt aenderbarer cashRegisterId)
// und der Zeilen-Diskriminator gegen movementId-Kollisionen.

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assertOktoposHostAllowed,
  resolveOktoposApiKey,
  buildOktoposMovementId,
  buildOktoposReceiptId,
  oktoposLineDiscriminator,
} = require("../index.js")._testables;

test("K4: leere Allowlist blockt jeden Host (fail-closed)", () => {
  assert.throws(
    () => assertOktoposHostAllowed("https://kasse.example.de", ""),
    /OKTOPOS_ALLOWED_HOSTS/,
  );
});

test("K4: fremder Host wird abgewiesen, gelisteter Host passiert", () => {
  assert.throws(
    () => assertOktoposHostAllowed(
      "https://attacker.example", "kasse.example.de",
    ),
    /Allowlist/,
  );
  assert.doesNotThrow(() => assertOktoposHostAllowed(
    "https://kasse.example.de", "kasse.example.de, kasse2.example.de",
  ));
});

test("K4: private/lokale Adressen sind unabhaengig von der Allowlist tabu", () => {
  for (const url of [
    "https://localhost/api",
    "https://127.0.0.1/api",
    "https://10.0.0.5/api",
    "https://192.168.1.10/api",
    "https://172.16.0.1/api",
    "https://169.254.1.1/api",
  ]) {
    assert.throws(
      () => assertOktoposHostAllowed(url, "localhost,127.0.0.1,10.0.0.5"),
      /private|lokale/,
      url,
    );
  }
});

test("H2: JSON-Key-Map hat KEINEN */default-Fallback mehr", () => {
  const keys = JSON.stringify({"site-1": "key-1", "*": "wildcard", "default": "def"});
  assert.equal(resolveOktoposApiKey(keys, "site-1"), "key-1");
  assert.throws(
    () => resolveOktoposApiKey(keys, "site-unbekannt"),
    /expliziten Eintrag/,
    "eine unbekannte siteId darf nie einen echten Key erhalten",
  );
});

test("H6: Receipt-/Movement-IDs haengen am stabilen Standort, nicht an der Kassen-Nr.", () => {
  // Frueher steckte cashRegisterId in der ID -> Konfig-Wechsel = neue IDs =
  // Doppelbuchung beim Lookback. Jetzt ist die siteId der Scope.
  const receiptId = buildOktoposReceiptId("site-1", "BON-42");
  assert.match(receiptId, /^site-1-BON-42-/);
  assert.equal(receiptId, buildOktoposReceiptId("site-1", "BON-42"),
    "deterministisch bei gleichem Input");

  const movementId = buildOktoposMovementId("site-1", "BON-42", "7");
  assert.match(movementId, /^oktopos-site-1-BON-42-.*-7$/);
});

test("H3: fehlende/0-item.id kollabiert nicht mehr auf eine movementId", () => {
  const first = buildOktoposMovementId(
    "site-1", "BON-42", oktoposLineDiscriminator({id: null}, 0),
  );
  const second = buildOktoposMovementId(
    "site-1", "BON-42", oktoposLineDiscriminator({id: 0}, 1),
  );
  assert.notEqual(first, second,
    "zwei Zeilen ohne item.id muessen verschiedene Bewegungs-IDs bekommen");
  // Echte Zeilen-IDs bleiben stabil (Re-Pull-Idempotenz).
  assert.equal(oktoposLineDiscriminator({id: 7}, 3), "7");
  assert.equal(oktoposLineDiscriminator({id: "7"}, 3), "7");
});

// M9/GB: Kiosk-WorkEntry.date wird auf Berliner Mittagszeit normalisiert.
const {berlinNoonDate} = require("../index.js")._testables;

test("M9: berlinNoonDate legt den Stempel auf 12:00 Berlin (Sommer/Winter/Tagesgrenze)", () => {
  // Sommer (DST): 11.07. 23:30 Berlin = 21:30Z -> Mittag = 10:00Z am 11.07.
  assert.equal(
    berlinNoonDate(new Date("2026-07-11T21:30:00Z")).toISOString(),
    "2026-07-11T10:00:00.000Z",
  );
  // Winter: 15.01. 00:30 Berlin = 14.01. 23:30Z -> Mittag = 11:00Z am 15.01.
  assert.equal(
    berlinNoonDate(new Date("2026-01-14T23:30:00Z")).toISOString(),
    "2026-01-15T11:00:00.000Z",
  );
});
