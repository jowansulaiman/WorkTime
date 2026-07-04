"use strict";

const test = require("node:test");
const assert = require("node:assert");
const crypto = require("node:crypto");
const {
  encryptSecret,
  decryptSecret,
  LocalAesKeyWrapper,
} = require("../password_crypto");

// Fixer Test-KEK (deterministisch) — nur für die lokale Wrap-Variante.
const TEST_KEK = crypto.createHash("sha256").update("worktime-test-kek").digest();
const wrapper = new LocalAesKeyWrapper(TEST_KEK);

const secret = {u: "kvg-user", p: "S3cr3t!pass", n: "Notiz mit Details"};
const ctx = {orgId: "org-1", entryId: "entry-1", keyWrapper: wrapper};

test("Roundtrip: encrypt -> decrypt liefert exakt das Klartext-Objekt", async () => {
  const rec = await encryptSecret(secret, ctx);
  const back = await decryptSecret(rec, ctx);
  assert.deepStrictEqual(back, secret);
});

test("kein Klartext im Ciphertext-Record", async () => {
  const rec = await encryptSecret(secret, ctx);
  const blob = JSON.stringify(rec);
  assert.ok(!blob.includes("S3cr3t!pass"));
  assert.ok(!blob.includes("kvg-user"));
  assert.strictEqual(rec.encAlgo, "AES-256-GCM");
});

test("AAD-Bindung: Entschlüsselung mit fremdem entryId schlägt fehl", async () => {
  const rec = await encryptSecret(secret, ctx);
  await assert.rejects(() =>
    decryptSecret(rec, {orgId: "org-1", entryId: "OTHER", keyWrapper: wrapper}));
});

test("AAD-Bindung: fremde orgId schlägt fehl (Cross-Tenant)", async () => {
  const rec = await encryptSecret(secret, ctx);
  await assert.rejects(() =>
    decryptSecret(rec, {orgId: "OTHER", entryId: "entry-1", keyWrapper: wrapper}));
});

test("IV-Einzigartigkeit: zweimal verschlüsseln -> verschiedene iv/ciphertext",
  async () => {
    const a = await encryptSecret(secret, ctx);
    const b = await encryptSecret(secret, ctx);
    assert.notStrictEqual(a.iv, b.iv);
    assert.notStrictEqual(a.ciphertext, b.ciphertext);
    assert.notStrictEqual(a.wrappedDek, b.wrappedDek);
  });

test("falscher KEK: Unwrap/Entschlüsselung schlägt fehl", async () => {
  const rec = await encryptSecret(secret, ctx);
  const otherKek =
    crypto.createHash("sha256").update("anderer-kek").digest();
  const otherWrapper = new LocalAesKeyWrapper(otherKek);
  await assert.rejects(() =>
    decryptSecret(rec, {orgId: "org-1", entryId: "entry-1", keyWrapper: otherWrapper}));
});

test("verfälschter AuthTag schlägt fehl (Tamper-Schutz)", async () => {
  const rec = await encryptSecret(secret, ctx);
  const tag = Buffer.from(rec.authTag, "base64");
  tag[0] ^= 0xff;
  const tampered = {...rec, authTag: tag.toString("base64")};
  await assert.rejects(() => decryptSecret(tampered, ctx));
});

test("KEK-Rotation-Analogie: verschiedene Wrapper, gleiche DEK-Semantik",
  async () => {
    // Vertragstest: beide Wrapper erzwingen dieselbe AAD-Bindung.
    const w2 = new LocalAesKeyWrapper(
      crypto.createHash("sha256").update("kek-v2").digest());
    const aad = Buffer.from("org-1|entry-1", "utf8");
    const dek = crypto.randomBytes(32);
    const wrapped = await w2.wrap(dek, aad);
    const back = await w2.unwrap(wrapped.wrappedDek, aad);
    assert.deepStrictEqual(back, dek);
    // fremde AAD -> Fehler
    await assert.rejects(() =>
      w2.unwrap(wrapped.wrappedDek, Buffer.from("x|y", "utf8")));
  });
