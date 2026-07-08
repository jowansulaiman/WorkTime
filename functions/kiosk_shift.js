"use strict";

// Kiosk-Schichtbindung (ZV-2.1): reine Auswahl der zum Stempelzeitpunkt
// passendsten Schicht. Läuft server-seitig, weil das bewusst niedrig-
// privilegierte Geräte-Konto `shifts` NICHT lesen darf (firestore.rules
// verlangt canManageShifts/canViewSchedule) — ein Client-Read würde immer
// scheitern und die Schicht nie binden. Die Rechenlogik ist pur/ohne Admin SDK,
// damit sie ohne Emulator per `node --test` prüfbar ist (der Firestore-Query
// selbst lebt im Callable kioskClockPunch).

// Kandidaten-Fenster um den Stempelzeitpunkt (±12 h): grenzt die Firestore-
// Abfrage ein (nutzt den bestehenden Index shifts(userId, startTime)). „Nächste
// Schicht zu jetzt" auf absoluten Zeitstempeln ist zeitzonen-unabhängig — das
// Fenster ist damit nur eine Kandidaten-Grenze, keine Tagesgrenzen-Mathematik.
const SHIFT_MATCH_WINDOW_MS = 12 * 60 * 60 * 1000;

/**
 * Wählt aus Kandidaten-Schichten die id derjenigen, deren Beginn dem
 * Stempelzeitpunkt am nächsten liegt. Ungültige Einträge (keine id / kein
 * endlicher Startzeitpunkt) werden übersprungen; bei Gleichstand gewinnt der
 * zuerst gelistete (stabile Vorsortierung nach startTime im Callable).
 *
 * @param {Array<{id:string, startMs:(number|null)}>} candidates
 * @param {number} nowMs  Stempelzeitpunkt (ms seit Epoch).
 * @returns {string|null} id der nächstliegenden Schicht oder null.
 */
function pickClosestShiftId(candidates, nowMs) {
  if (!Array.isArray(candidates) || !Number.isFinite(nowMs)) return null;
  let bestId = null;
  let bestDelta = Infinity;
  for (const c of candidates) {
    if (!c || typeof c.id !== "string" || c.id === "") continue;
    const startMs = Number(c.startMs);
    if (!Number.isFinite(startMs)) continue;
    const delta = Math.abs(startMs - nowMs);
    if (delta < bestDelta) {
      bestDelta = delta;
      bestId = c.id;
    }
  }
  return bestId;
}

module.exports = {pickClosestShiftId, SHIFT_MATCH_WINDOW_MS};
