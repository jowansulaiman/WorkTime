"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  zeitkontoSnapshotId,
  istFestgeschrieben,
  festgeschriebenMeldung,
  jahrMonatVon,
} = require("../monats_lock.js");

test("zeitkontoSnapshotId: zero-padded Monat, Spiegel von buildId", () => {
  assert.equal(zeitkontoSnapshotId("emp-1", 2026, 6), "emp-1-2026-06");
  assert.equal(zeitkontoSnapshotId("emp-1", 2026, 12), "emp-1-2026-12");
});

test("istFestgeschrieben: nur explizites abgeschlossen===true sperrt", () => {
  assert.equal(istFestgeschrieben({abgeschlossen: true}), true);
  assert.equal(istFestgeschrieben({abgeschlossen: false}), false);
  assert.equal(istFestgeschrieben({}), false);
  assert.equal(istFestgeschrieben(null), false);
  assert.equal(istFestgeschrieben(undefined), false);
  // String 'true' aus kaputten Daten sperrt NICHT still (strikt boolesch).
  assert.equal(istFestgeschrieben({abgeschlossen: "true"}), false);
});

test("festgeschriebenMeldung: deutsch + zero-padded", () => {
  const msg = festgeschriebenMeldung(6, 2026);
  assert.match(msg, /06\/2026/);
  assert.match(msg, /festgeschrieben/);
  assert.match(msg, /Monatsabschluss/);
});

test("jahrMonatVon: UTC-Komponenten des Kalendertags, null bei Murks", () => {
  // parseDate('2026-06-15') => UTC-Mitternacht.
  assert.deepEqual(jahrMonatVon(new Date("2026-06-15")), {
    jahr: 2026,
    monat: 6,
  });
  // Monatsgrenze: 1. des Monats bleibt im Monat.
  assert.deepEqual(jahrMonatVon(new Date("2026-07-01")), {
    jahr: 2026,
    monat: 7,
  });
  assert.equal(jahrMonatVon(new Date("kaputt")), null);
  assert.equal(jahrMonatVon(null), null);
});
