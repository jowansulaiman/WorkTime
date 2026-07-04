"use strict";

// Passwortmanager-Krypto-Core (PM-M0, §9). Envelope-Verschlüsselung:
//   - pro Eintrag ein frischer Data Encryption Key (DEK), AES-256-GCM über den
//     Klartext ({u,p,n} als JSON), AAD = orgId|entryId (Confused-Deputy-Schutz).
//   - der DEK wird über einen KeyWrapper gewrappt. Prod = Cloud KMS (KEK bleibt
//     im HSM), Test = lokaler AES-Wrapper mit fixem Test-KEK → GESAMTE Daten-
//     Verschlüsselung offline mit `node --test` prüfbar, nur der Wrap-Schritt
//     ist im Test gemockt (die AAD-Semantik ist bei beiden identisch).
//
// Der Klartext-KEK ist bei der KMS-Variante zu KEINEM Zeitpunkt im Prozess.

const crypto = require("node:crypto");

const ENC_ALGO = "AES-256-GCM";

function aadFor(orgId, entryId) {
  return Buffer.from(`${orgId}|${entryId}`, "utf8");
}

/**
 * Verschlüsselt das Klartext-Secret-Objekt ({u,p,n}) und wrappt den DEK.
 * @returns {Promise<object>} camelCase-Doc-Felder (alles base64).
 */
async function encryptSecret(plainObject, {orgId, entryId, keyWrapper}) {
  const aad = aadFor(orgId, entryId);
  const dek = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  try {
    const cipher = crypto.createCipheriv("aes-256-gcm", dek, iv);
    cipher.setAAD(aad);
    const pt = Buffer.from(JSON.stringify(plainObject), "utf8");
    const ct = Buffer.concat([cipher.update(pt), cipher.final()]);
    const authTag = cipher.getAuthTag();
    const wrapped = await keyWrapper.wrap(dek, aad);
    return {
      ciphertext: ct.toString("base64"),
      iv: iv.toString("base64"),
      authTag: authTag.toString("base64"),
      wrappedDek: wrapped.wrappedDek,
      kmsKeyVersion: wrapped.keyVersion || null,
      encAlgo: ENC_ALGO,
    };
  } finally {
    // Klartext-DEK sofort aus dem Speicher tilgen.
    dek.fill(0);
  }
}

/**
 * Entschlüsselt ein passwordSecrets-Doc zurück zum Klartext-Objekt.
 * Wirft, wenn AAD/AuthTag nicht passen (Tamper/falscher Kontext).
 */
async function decryptSecret(record, {orgId, entryId, keyWrapper}) {
  const aad = aadFor(orgId, entryId);
  const dek = await keyWrapper.unwrap(record.wrappedDek, aad);
  try {
    const decipher = crypto.createDecipheriv(
      "aes-256-gcm", dek, Buffer.from(record.iv, "base64"));
    decipher.setAAD(aad);
    decipher.setAuthTag(Buffer.from(record.authTag, "base64"));
    const pt = Buffer.concat([
      decipher.update(Buffer.from(record.ciphertext, "base64")),
      decipher.final(),
    ]);
    return JSON.parse(pt.toString("utf8"));
  } finally {
    dek.fill(0);
  }
}

/**
 * Test-/Fallback-Wrapper: wrappt den DEK lokal per AES-256-GCM unter einem
 * fixen KEK. NUR für Tests / Emulator — im Prod-Betrieb kommt der KEK nie in
 * den Prozess (dann KmsKeyWrapper).
 */
class LocalAesKeyWrapper {
  constructor(kek) {
    if (!Buffer.isBuffer(kek) || kek.length !== 32) {
      throw new Error("LocalAesKeyWrapper: KEK muss 32 Byte sein.");
    }
    this._kek = kek;
  }

  async wrap(dek, aad) {
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv("aes-256-gcm", this._kek, iv);
    c.setAAD(aad);
    const ct = Buffer.concat([c.update(dek), c.final()]);
    const tag = c.getAuthTag();
    // Packen: iv(12) | tag(16) | ct
    const packed = Buffer.concat([iv, tag, ct]);
    return {wrappedDek: packed.toString("base64"), keyVersion: "local"};
  }

  async unwrap(wrappedDekB64, aad) {
    const packed = Buffer.from(wrappedDekB64, "base64");
    const iv = packed.subarray(0, 12);
    const tag = packed.subarray(12, 28);
    const ct = packed.subarray(28);
    const d = crypto.createDecipheriv("aes-256-gcm", this._kek, iv);
    d.setAAD(aad);
    d.setAuthTag(tag);
    return Buffer.concat([d.update(ct), d.final()]);
  }
}

/**
 * Prod-Wrapper: wrappt/unwrappt den DEK über Cloud KMS. Der KEK verlässt das
 * HSM nie. `@google-cloud/kms` wird LAZY geladen (fehlt in Offline-Tests).
 */
class KmsKeyWrapper {
  constructor(keyName) {
    if (!keyName) throw new Error("KmsKeyWrapper: keyName fehlt.");
    this._keyName = keyName;
    // eslint-disable-next-line global-require
    const {KeyManagementServiceClient} = require("@google-cloud/kms");
    this._client = new KeyManagementServiceClient();
  }

  async wrap(dek, aad) {
    const [resp] = await this._client.encrypt({
      name: this._keyName,
      plaintext: dek,
      additionalAuthenticatedData: aad,
    });
    return {
      wrappedDek: Buffer.from(resp.ciphertext).toString("base64"),
      keyVersion: resp.name || null,
    };
  }

  async unwrap(wrappedDekB64, aad) {
    const [resp] = await this._client.decrypt({
      name: this._keyName,
      ciphertext: Buffer.from(wrappedDekB64, "base64"),
      additionalAuthenticatedData: aad,
    });
    return Buffer.from(resp.plaintext);
  }
}

module.exports = {
  encryptSecret,
  decryptSecret,
  LocalAesKeyWrapper,
  KmsKeyWrapper,
  ENC_ALGO,
};
