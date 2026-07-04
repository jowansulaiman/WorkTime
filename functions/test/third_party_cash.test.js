"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {parseThirdPartyAmounts, MAX_THIRD_PARTY_ITEMS} =
  require("../third_party_cash");

test("undefined/null -> leere Liste (streng optional, alte Clients)", () => {
  assert.deepStrictEqual(parseThirdPartyAmounts(undefined), []);
  assert.deepStrictEqual(parseThirdPartyAmounts(null), []);
});

test("normalisiert gültige Einträge zu camelCase-Feldern", () => {
  const out = parseThirdPartyAmounts([
    {typeId: "lotto", typeName: "Lotto", amountCents: 4500, note: " ok "},
    {typeId: "post", typeName: "Post", amountCents: 0},
  ]);
  assert.strictEqual(out.length, 2);
  assert.deepStrictEqual(out[0], {
    typeId: "lotto",
    typeName: "Lotto",
    amountCents: 4500,
    expectedCents: null,
    note: "ok",
  });
  assert.strictEqual(out[1].amountCents, 0);
  assert.strictEqual(out[1].note, null);
});

test("Blind-Zwang: expectedCents wird am Kiosk hart auf null gesetzt", () => {
  const out = parseThirdPartyAmounts(
    [{typeId: "lotto", typeName: "Lotto", amountCents: 100, expectedCents: 90}],
    {blind: true},
  );
  assert.strictEqual(out[0].expectedCents, null);
});

test("ohne blind: gültiges expectedCents wird übernommen", () => {
  const out = parseThirdPartyAmounts(
    [{typeId: "lotto", typeName: "Lotto", amountCents: 100, expectedCents: 90}],
    {blind: false},
  );
  assert.strictEqual(out[0].expectedCents, 90);
});

test("rundet Beträge", () => {
  const out = parseThirdPartyAmounts([
    {typeId: "x", typeName: "X", amountCents: 12.6},
  ]);
  assert.strictEqual(out[0].amountCents, 13);
});

test("wirft invalidArgument bei nicht-Liste", () => {
  assert.throws(
    () => parseThirdPartyAmounts({}),
    (e) => e.invalidArgument === true,
  );
});

test("wirft bei fehlendem typeId", () => {
  assert.throws(
    () => parseThirdPartyAmounts([{typeName: "X", amountCents: 1}]),
    (e) => e.invalidArgument === true,
  );
});

test("wirft bei negativem Betrag", () => {
  assert.throws(
    () => parseThirdPartyAmounts([{typeId: "x", amountCents: -5}]),
    (e) => e.invalidArgument === true,
  );
});

test("wirft bei nicht-endlichem Betrag", () => {
  assert.throws(
    () => parseThirdPartyAmounts([{typeId: "x", amountCents: "abc"}]),
    (e) => e.invalidArgument === true,
  );
});

test("wirft bei zu vielen Positionen (> MAX)", () => {
  const many = Array.from({length: MAX_THIRD_PARTY_ITEMS + 1}, (_, i) => ({
    typeId: `t${i}`,
    amountCents: 1,
  }));
  assert.throws(
    () => parseThirdPartyAmounts(many),
    (e) => e.invalidArgument === true,
  );
});
