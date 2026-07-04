"use strict";

const test = require("node:test");
const assert = require("node:assert");
const pa = require("../password_access");

const admin = {uid: "admin", role: "admin", isAdmin: true};
const emp = {uid: "u1", role: "employee", isAdmin: false};
const lead = {uid: "u2", role: "teamlead", isAdmin: false};

test("personal: nur Owner (oder Admin) sieht", () => {
  const entry = {scope: "personal", ownerUid: "u1"};
  assert.ok(pa.canViewEntry(entry, emp, []));
  assert.ok(pa.canViewEntry(entry, admin, []));
  assert.ok(!pa.canViewEntry(entry, lead, []));
});

test("shared: Sichtbarkeit über audienceUids", () => {
  const entry = {scope: "shared", audienceUids: ["u1"], audienceRoles: [], audienceSiteIds: []};
  assert.ok(pa.canViewEntry(entry, emp, []));
  assert.ok(!pa.canViewEntry(entry, lead, []));
});

test("shared: Sichtbarkeit über Rolle", () => {
  const entry = {scope: "shared", audienceUids: [], audienceRoles: ["teamlead"], audienceSiteIds: []};
  assert.ok(pa.canViewEntry(entry, lead, []));
  assert.ok(!pa.canViewEntry(entry, emp, []));
});

test("shared: Sichtbarkeit über LIVE-Filialzuordnung", () => {
  const entry = {scope: "shared", audienceUids: [], audienceRoles: [], audienceSiteIds: ["site-1"]};
  assert.ok(pa.canViewEntry(entry, emp, ["site-1"]));
  // Filiale entzogen (leere callerSiteIds) -> NICHT mehr sichtbar (B3-Fix).
  assert.ok(!pa.canViewEntry(entry, emp, []));
});

test("canManageEntry personal: Owner darf, Fremder nicht", () => {
  const entry = {scope: "personal", ownerUid: "u1"};
  assert.ok(pa.canManageEntry(entry, emp, [], {}));
  assert.ok(!pa.canManageEntry(entry, lead, [], {}));
});

test("canManageEntry shared: nur Admin (Flag aus)", () => {
  const entry = {scope: "shared", siteId: "site-1"};
  assert.ok(pa.canManageEntry(entry, admin, [], {teamleadEnabled: false}));
  assert.ok(!pa.canManageEntry(entry, lead, ["site-1"], {teamleadEnabled: false}));
});

test("canManageEntry shared: teamlead eigene Filiale nur bei Flag", () => {
  const entry = {scope: "shared", siteId: "site-1"};
  assert.ok(pa.canManageEntry(entry, lead, ["site-1"], {teamleadEnabled: true}));
  // fremde Filiale
  assert.ok(!pa.canManageEntry(entry, lead, ["site-2"], {teamleadEnabled: true}));
});

test("parseEntryPayload: snake_case -> camelCase + Validierung", () => {
  const entry = pa.parseEntryPayload({
    org_id: "org-1",
    title: " KVG ",
    category: "kvg",
    scope: "shared",
    owner_uid: "u1",
    site_id: "site-1",
    audience_uids: ["u2"],
    audience_roles: ["teamlead"],
    audience_site_ids: ["site-1"],
    url: "https://x",
  });
  assert.strictEqual(entry.title, "KVG");
  assert.strictEqual(entry.scope, "shared");
  assert.deepStrictEqual(entry.audienceUids, ["u2"]);
  assert.strictEqual(entry.siteId, "site-1");
});

test("parseEntryPayload: leerer Titel wirft invalidArgument", () => {
  assert.throws(
    () => pa.parseEntryPayload({org_id: "o", title: "  ", scope: "personal"}),
    (e) => e.invalidArgument === true,
  );
});

test("parseEntryPayload: unbekannter scope -> personal", () => {
  const entry = pa.parseEntryPayload({org_id: "o", title: "x", scope: "quatsch"});
  assert.strictEqual(entry.scope, "personal");
});

test("parseSecretPayload: extrahiert u/p/n, begrenzt Länge", () => {
  const s = pa.parseSecretPayload({
    plain_username: "user",
    plain_password: "pw",
    plain_notes: "note",
  });
  assert.deepStrictEqual(s, {u: "user", p: "pw", n: "note"});
  assert.throws(
    () => pa.parseSecretPayload({plain_password: "x".repeat(5000)}),
    (e) => e.invalidArgument === true,
  );
});
