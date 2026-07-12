"use strict";

// Pure Helfer der Konto-Löschung (Plan plan/account-loeschung.md). Bewusst gegen
// das Modul selbst (kein index.js -> kein admin.initializeApp), damit rein.

const test = require("node:test");
const assert = require("node:assert/strict");

const ad = require("../account_deletion");

test("anonSentinel: stabil pro uid, präfixiert, nicht die uid", () => {
  const a = ad.anonSentinel("user-1");
  assert.equal(a, ad.anonSentinel("user-1"));
  assert.match(a, /^geloescht:[0-9a-f]{12}$/);
  assert.notEqual(a, "user-1");
  assert.notEqual(a, ad.anonSentinel("user-2"));
});

test("computeAnonymizeUpdate: nur passende Link-Felder werden ersetzt", () => {
  const s = "geloescht:abc";
  // requester gelöscht -> requesterUid ersetzt, fremdes targetUid bleibt.
  assert.deepEqual(
    ad.computeAnonymizeUpdate(
      {requesterUid: "u1", targetUid: "u2"}, "u1", s,
      ["requesterUid", "targetUid"]),
    {requesterUid: s},
  );
  // kein Treffer -> leeres Update (keine falschen Feld-Anlagen).
  assert.deepEqual(
    ad.computeAnonymizeUpdate({userId: "other"}, "u1", s, ["userId"]),
    {},
  );
  // beide Link-Felder == uid.
  assert.deepEqual(
    ad.computeAnonymizeUpdate(
      {userId: "u1", createdByUid: "u1"}, "u1", s,
      ["userId", "createdByUid"]),
    {userId: s, createdByUid: s},
  );
  // defensiv: null/kaputte Daten.
  assert.deepEqual(ad.computeAnonymizeUpdate(null, "u1", s, ["userId"]), {});
});

test("inviteDocId spiegelt Dart _inviteDocId (trim/lowercase/slash->_)", () => {
  assert.equal(ad.inviteDocId("  Foo/Bar@Mail.DE "), "foo_bar@mail.de");
  assert.equal(ad.inviteDocId(null), "");
});

test("Klassifikation: keine Collection ist zugleich Hard-Delete UND Anonymisieren", () => {
  const deleted = new Set([
    ...ad.DOC_ID_DELETE,
    ...ad.FIELD_DELETE.map((f) => f.collection),
  ]);
  for (const entry of ad.ANONYMIZE) {
    assert.equal(
      deleted.has(entry.collection), false,
      `${entry.collection} sowohl gelöscht als auch anonymisiert`);
  }
  // Retention-kritische Collections MÜSSEN anonymisiert (nicht gelöscht) werden.
  const anon = new Set(ad.ANONYMIZE.map((e) => e.collection));
  for (const must of ["workEntries", "payrollRecords", "employmentContracts",
    "clockEntries", "cashClosings", "urlaubskontoJahre"]) {
    assert.equal(anon.has(must), true, `${must} muss anonymisiert werden`);
  }
  // urlaubskontoJahre darf NICHT (mehr) hart gelöscht werden (Retention, Plan C).
  assert.equal(deleted.has("urlaubskontoJahre"), false);
});

test("Anonymisierung erfasst Fremd-Referenz-uids (Freigeber/Ersteller/Korrektor)", () => {
  const byName = Object.fromEntries(ad.ANONYMIZE.map((e) => [e.collection, e.fields]));
  assert.deepEqual(byName.workEntries.sort(),
    ["approvedByUid", "correctedByUid", "userId"]);
  assert.deepEqual(byName.clockEntries.sort(),
    ["createdByUid", "korrigiertVonUid", "userId"]);
});

test("priceHistory läuft über den collectionGroup-Pass, nicht die org-Top-Level-Liste", () => {
  const anon = new Set(ad.ANONYMIZE.map((e) => e.collection));
  assert.equal(anon.has("priceHistory"), false);
  const groups = ad.SUBCOLLECTION_ANONYMIZE.map((e) => e.group);
  assert.ok(groups.includes("priceHistory"));
  const ph = ad.SUBCOLLECTION_ANONYMIZE.find((e) => e.group === "priceHistory");
  assert.equal(ph.orgField, "orgId");
  assert.deepEqual(ph.fields, ["changedByUid"]);
});
