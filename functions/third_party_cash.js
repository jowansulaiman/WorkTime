"use strict";

// Dritte-Hand-/Fremdgeld-Beträge (§8.7): pure Validierung/Normalisierung der
// vom Client gelieferten `thirdParty`-Liste, damit sie ohne Admin SDK/Emulator
// mit `node --test` prüfbar ist. Der Callable (kioskSaveCashCount) ruft dies
// und mappt einen Fehler auf HttpsError('invalid-argument').

const MAX_THIRD_PARTY_ITEMS = 20;

/**
 * Validiert + normalisiert die Fremdgeld-Liste zu camelCase-Doc-Feldern.
 *
 * @param {*} raw            Rohwert aus request.data.thirdParty (optional).
 * @param {object} [opts]
 * @param {boolean} [opts.blind=false]  Wenn true (Kiosk), wird expectedCents
 *                                      hart auf null gezwungen (Blind-Zwang).
 * @returns {Array<{typeId:string,typeName:string,amountCents:number,
 *                  expectedCents:(number|null),note:(string|null)}>}
 * @throws {Error} mit .invalidArgument=true bei ungültiger Eingabe.
 */
function parseThirdPartyAmounts(raw, opts) {
  const blind = !!(opts && opts.blind);
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw invalid("thirdParty muss eine Liste sein.");
  }
  if (raw.length > MAX_THIRD_PARTY_ITEMS) {
    throw invalid(
      `Zu viele Fremdgeld-Positionen (max. ${MAX_THIRD_PARTY_ITEMS}).`,
    );
  }
  return raw.map((entry, i) => {
    if (entry === null || typeof entry !== "object") {
      throw invalid(`Fremdgeld-Position ${i + 1} ist ungültig.`);
    }
    const typeId = typeof entry.typeId === "string" ? entry.typeId.trim() : "";
    if (!typeId) {
      throw invalid(`Fremdgeld-Position ${i + 1}: typeId fehlt.`);
    }
    const amountCents = Number(entry.amountCents);
    if (!Number.isFinite(amountCents) || amountCents < 0) {
      throw invalid(
        `Fremdgeld-Position "${typeId}": amountCents muss eine Zahl >= 0 sein.`,
      );
    }
    const typeName =
      typeof entry.typeName === "string" ? entry.typeName.trim() : "";
    const note =
      typeof entry.note === "string" && entry.note.trim() !== ""
        ? entry.note.trim()
        : null;
    let expectedCents = null;
    if (!blind && entry.expectedCents !== undefined &&
        entry.expectedCents !== null) {
      const exp = Number(entry.expectedCents);
      if (!Number.isFinite(exp) || exp < 0) {
        throw invalid(
          `Fremdgeld-Position "${typeId}": expectedCents ungültig.`,
        );
      }
      expectedCents = Math.round(exp);
    }
    return {
      typeId,
      typeName,
      amountCents: Math.round(amountCents),
      expectedCents,
      note,
    };
  });
}

function invalid(message) {
  const err = new Error(message);
  err.invalidArgument = true;
  return err;
}

module.exports = {parseThirdPartyAmounts, MAX_THIRD_PARTY_ITEMS};
