"use strict";

// Reine, SDK-freie Push-Hilfsfunktionen (Empfaenger-Aufloesung, Dedupe-Key,
// Payload-Bau, Datum/Zeit-Formatierung, Stale-Token-Erkennung). In
// functions/index.js vom Admin SDK umschlossen; hier OHNE firebase-admin, damit
// per `node --test` offline unit-testbar (functions/test/push_notifications.test.js).
//
// Plan: plan/push-benachrichtigungen-plan.md (M2/M3).

// FCM-Fehlercodes, bei denen der Token endgueltig ungueltig ist und das
// Token-Doc geloescht werden soll (Pruning beim Versand).
const STALE_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

const TZ = "Europe/Berlin";

function truncate(text, max) {
  const value = typeof text === "string" ? text.trim() : "";
  if (value.length <= max) {
    return value;
  }
  return value.slice(0, max - 1).trimEnd() + "…";
}

// Deutsche Datums-/Zeitformatierung in lokaler Zeitzone (Functions laufen in UTC
// -> ohne timeZone waere die Uhrzeit verschoben).
function formatDe(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toLocaleDateString("de-DE", {
    timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric",
  });
}

function formatTimeDe(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toLocaleTimeString("de-DE", {
    timeZone: TZ, hour: "2-digit", minute: "2-digit",
  });
}

// Deterministischer Dedupe-Anker je logischem Ereignis + Empfaenger. Doc-ID in
// organizations/{orgId}/notifications -> .create() schlaegt fehl, wenn das
// Ereignis fuer diesen Nutzer schon zugestellt wurde (kein Doppel-Push).
function dedupeKey(eventType, entityId, recipientUid) {
  return `${entityId}:${eventType}:${recipientUid}`;
}

function uniqueUids(uids) {
  const seen = new Set();
  for (const uid of uids) {
    if (typeof uid === "string" && uid && !seen.has(uid)) {
      seen.add(uid);
    }
  }
  return [...seen];
}

// ALLE aktiven Mitarbeiter der Org (z.B. neuer Kundenwunsch).
// `users` = Liste {uid, isActive}.
function activeRecipientUids(users) {
  return uniqueUids(
    users.filter((u) => u && u.isActive === true).map((u) => u.uid),
  );
}

// Manager der Org = aktiv UND (Admin ODER effektives canEditSchedule). Deckt
// Genehmiger (Abwesenheit/Tausch), Feedback- und Bestands-Empfaenger ab
// (canManageInventory == isAdmin || canManageShifts). `records` =
// {uid, isActive, isAdmin, canEditSchedule} (Permissions in index.js aufgeloest).
function managerUids(records) {
  return uniqueUids(
    records
      .filter((r) => r && r.isActive === true && (r.isAdmin || r.canEditSchedule))
      .map((r) => r.uid),
  );
}

// --- Payload-Builder (deutsch, PII-arm) -----------------------------------
// Jede Push-Payload: {type, title, body, route, entityType, entityId, thread,
// priority}. `priority` steuert spaeter (M4) Channel/Interruption-Level.

function buildWishNotification({wishId, storeName, wishText}) {
  const store = typeof storeName === "string" && storeName.trim() ?
    storeName.trim() : "Laden";
  const excerpt = truncate(wishText, 80) || "Neuer Wunsch eingegangen";
  return {
    type: "customer_wish",
    title: "Neuer Kundenwunsch",
    body: `${store}: ${excerpt}. Bitte vorbereiten.`,
    route: "/kundenwuensche",
    entityType: "customerWish",
    entityId: wishId,
    thread: "wishes",
    priority: "normal",
  };
}

function buildFeedbackNotification({feedbackId, type, message}) {
  const labels = {
    complaint: "Beschwerde",
    suggestion: "Verbesserungsvorschlag",
    praise: "Lob",
  };
  const label = labels[type] || "Feedback";
  return {
    type: "customer_feedback",
    title: `Neues ${label}`,
    body: `${label}: ${truncate(message, 90) || "ohne Text"}`,
    route: "/feedback-eingang",
    entityType: "customerFeedback",
    entityId: feedbackId,
    thread: "feedback",
    priority: type === "complaint" ? "high" : "normal",
  };
}

function range(start, end) {
  return !end || start === end ? start : `${start}–${end}`;
}

function buildAbsenceSubmittedNotification({absenceId, employeeName, typeLabel, start, end}) {
  return {
    type: "absence_submitted",
    title: "Neuer Abwesenheitsantrag",
    body: `${employeeName || "Mitarbeiter"}: ${typeLabel} ${range(start, end)}`.trim(),
    route: "/anfragen",
    entityType: "absenceRequest",
    entityId: absenceId,
    thread: `absence_${absenceId}`,
    priority: "normal",
  };
}

function buildAbsenceDecisionNotification({absenceId, typeLabel, start, end, approved}) {
  return {
    type: "absence_decision",
    title: approved ? "Antrag genehmigt" : "Antrag abgelehnt",
    body: `Dein Antrag (${typeLabel} ${range(start, end)}) wurde ` +
      `${approved ? "genehmigt" : "abgelehnt"}.`,
    route: "/zeit/abwesenheiten",
    entityType: "absenceRequest",
    entityId: absenceId,
    thread: `absence_${absenceId}`,
    priority: "normal",
  };
}

// Schichttausch-Lebenszyklus. `phase` bestimmt Typ (=> eigener Dedupe-Key) und
// Empfaenger (in index.js).
function buildSwapNotification(phase, {swapId, requesterName, targetName, shiftDate}) {
  const base = {
    entityType: "shiftSwapRequest",
    entityId: swapId,
    thread: `swap_${swapId}`,
    route: "/anfragen",
    priority: "high",
  };
  const when = shiftDate ? ` (${shiftDate})` : "";
  switch (phase) {
    case "request":
      return {...base, type: "shift_swap_request", title: "Tauschanfrage",
        body: `${requesterName || "Ein Kollege"} möchte mit dir tauschen${when}.`};
    case "accepted":
      return {...base, type: "shift_swap_accepted", title: "Tausch bestätigen",
        body: `${targetName || "Ein Kollege"} hat den Tausch angenommen. Bitte bestätigen.`};
    case "declined":
      return {...base, type: "shift_swap_declined", title: "Tausch abgelehnt",
        priority: "normal",
        body: `${targetName || "Der Kollege"} hat deine Tauschanfrage abgelehnt.`};
    case "confirmed":
      return {...base, type: "shift_swap_confirmed", title: "Tausch bestätigt",
        route: "/plan",
        body: `Dein Tausch${shiftDate ? ` am ${shiftDate}` : ""} ist bestätigt.`};
    case "rejected":
      return {...base, type: "shift_swap_rejected", title: "Tausch abgelehnt",
        priority: "normal",
        body: `Der Tausch${shiftDate ? ` am ${shiftDate}` : ""} wurde nicht durchgeführt.`};
    default:
      return null;
  }
}

function buildShiftPublishedNotification({shiftId, siteName, date, weekLabel}) {
  const where = siteName ? ` (${siteName})` : "";
  // Wöchentlich gebündelt (M7): ein Push je Mitarbeiter & Woche statt je Schicht.
  const body = weekLabel ?
    `Dein Plan für ${weekLabel}${where} steht fest.` :
    `Deine Schicht am ${date}${where} steht fest.`;
  return {
    type: "shift_published",
    title: "Schichtplan veröffentlicht",
    body,
    route: "/plan",
    entityType: "shift",
    entityId: shiftId,
    thread: "plan",
    priority: "high",
  };
}

// ISO-8601-Kalenderwoche eines Datums (pur). Für die wöchentliche Bündelung der
// „Schichtplan veröffentlicht"-Pushes (Dedupe je Mitarbeiter & Woche).
function isoWeek(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return null;
  }
  const d = new Date(Date.UTC(
      date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = (d.getUTCDay() + 6) % 7; // Mo=0 … So=6
  d.setUTCDate(d.getUTCDate() - dayNum + 3); // Donnerstag dieser Woche
  const firstThursday = Date.UTC(d.getUTCFullYear(), 0, 4);
  const week = 1 + Math.round(
      ((d.getTime() - firstThursday) / 86400000 -
        3 + ((new Date(firstThursday).getUTCDay() + 6) % 7)) / 7);
  return {year: d.getUTCFullYear(), week};
}

function buildShiftOpenNotification({shiftId, siteName, date}) {
  const where = siteName ? ` in ${siteName}` : "";
  return {
    type: "shift_open",
    title: "Schicht offen",
    body: `Die Schicht am ${date}${where} ist offen — bitte neu besetzen.`,
    route: "/plan",
    entityType: "shift",
    entityId: shiftId,
    thread: "plan",
    priority: "high",
  };
}

function buildLowStockNotification({productId, productName, currentStock, minStock, siteName}) {
  return {
    type: "low_stock",
    title: siteName ? `Nachbestellen · ${siteName}` : "Nachbestellen",
    body: `${productName || "Artikel"}: nur noch ${currentStock} ` +
      `(Meldebestand ${minStock}).`,
    route: "/warenwirtschaft?tab=korb",
    entityType: "product",
    entityId: productId,
    thread: "lowstock",
    priority: "normal",
  };
}

// MHD-/Ablauf-Warnung: eine Warencharge laeuft bald ab (oder ist abgelaufen).
// `daysUntilExpiry` = ganze Kalendertage bis zum MHD (negativ = abgelaufen).
function buildExpiryNotification({batchId, productName, siteName, daysUntilExpiry}) {
  const where = typeof siteName === "string" && siteName.trim() ?
    ` · ${siteName.trim()}` : "";
  const days = typeof daysUntilExpiry === "number" ? daysUntilExpiry : null;
  const when = days === null ? "läuft bald ab" :
    days < 0 ? `ist seit ${-days} ${-days === 1 ? "Tag" : "Tagen"} abgelaufen` :
    days === 0 ? "läuft heute ab" :
    days === 1 ? "läuft morgen ab" :
    `läuft in ${days} Tagen ab`;
  return {
    type: "expiry",
    title: `Läuft bald ab${where}`,
    body: `${productName || "Artikel"} ${when}.`,
    route: "/warenwirtschaft",
    entityType: "productBatch",
    entityId: batchId,
    thread: "expiry",
    priority: "normal",
  };
}

// Neues (sichtbares) Dokument in der Personalakte -> an genau den Mitarbeiter
// (PA-3.5). Kanal vorerst `aufgaben` (channelIdForType default) — bewusst KEIN
// eigener `personal`-Kanal, um die 6 Kopplungsstellen der Kanal-Taxonomie nicht
// mitzuziehen; leicht nachrüstbar. Deep-Link auf „Meine Akte".
function buildDocumentNotification({docId, title}) {
  return {
    type: "personal_document",
    title: "Neues Dokument in deiner Personalakte",
    body: truncate(
      typeof title === "string" && title.trim() ?
        title.trim() : "Ein Dokument wurde für dich hinterlegt.",
      120,
    ),
    route: "/meine-akte",
    entityType: "Personaldokument",
    entityId: docId,
    dedupeId: docId,
    thread: "personal",
  };
}

// Lohnabrechnung freigegeben -> an den Mitarbeiter (PA-7.4). Deep-Link „Meine
// Akte". Kanal `aufgaben` (default) — bewusst kein eigener Lohn-Kanal.
function buildPayrollReleasedNotification({recordId, monthLabel}) {
  return {
    type: "payroll_released",
    title: "Lohnabrechnung verfügbar",
    body: typeof monthLabel === "string" && monthLabel ?
      `Deine Abrechnung für ${monthLabel} ist freigegeben.` :
      "Eine neue Lohnabrechnung ist freigegeben.",
    route: "/meine-akte",
    entityType: "Lohnabrechnung",
    entityId: recordId,
    dedupeId: recordId,
    thread: "payroll",
  };
}

// Stempel automatisch zur Klärung gelegt (vergessenes Ausstempeln, ZV-2.3b/ZV-7)
// -> an den betroffenen Mitarbeiter. Kanal `aufgaben` (default), thread
// `personal`. Deep-Link auf den Stempel-Bereich.
function buildAutoKlaerungNotification({clockEntryId, dayLabel}) {
  return {
    type: "clock_auto_klaerung",
    title: "Stempelung braucht Klärung",
    body: typeof dayLabel === "string" && dayLabel ?
      `Deine Buchung vom ${dayLabel} wurde nicht ausgestempelt und zur ` +
        "Klärung gelegt." :
      "Eine Buchung wurde nicht ausgestempelt und zur Klärung gelegt.",
    route: "/zeit/stempeln",
    entityType: "Stempelzeit",
    entityId: clockEntryId,
    dedupeId: `klaerung:${clockEntryId}`,
    thread: "personal",
  };
}

// Klärungsfall vom Manager gelöst (ZV-7) -> an den betroffenen Mitarbeiter,
// als Abschluss/Bestätigung zum vorherigen Auto-Klärungs-Push. Kanal `aufgaben`
// (default), thread `personal`. Deep-Link auf den Stempel-Bereich.
function buildKlaerungResolvedNotification({clockEntryId, dayLabel, hours}) {
  const stunden = typeof hours === "number" && hours > 0 ?
    ` (${hours.toFixed(1).replace(".", ",")} h)` : "";
  return {
    type: "clock_klaerung_resolved",
    title: "Stempelung korrigiert",
    body: typeof dayLabel === "string" && dayLabel ?
      `Deine Buchung vom ${dayLabel} wurde geklärt und übernommen${stunden}.` :
      `Deine offene Buchung wurde geklärt und übernommen${stunden}.`,
    route: "/zeit/stempeln",
    entityType: "Stempelzeit",
    entityId: clockEntryId,
    dedupeId: `klaerung-resolved:${clockEntryId}`,
    thread: "personal",
  };
}

// --- Präferenzen (M5) -----------------------------------------------------
// Ordnet einen Ereignis-`type` dem Channel/der Kategorie zu (= App-Schalter +
// Android-Channel; deckungsgleich mit Dart `channelIdForType`).
function channelIdForType(type) {
  switch (type) {
    case "absence_submitted":
    case "absence_decision":
    case "shift_swap_request":
    case "shift_swap_accepted":
    case "shift_swap_declined":
    case "shift_swap_confirmed":
    case "shift_swap_rejected":
      return "genehmigungen";
    case "shift_published":
    case "shift_open":
      return "schichtplan";
    case "customer_wish":
      return "kundenwuensche";
    case "low_stock":
    case "expiry":
      return "bestand";
    case "customer_feedback":
    default:
      return "aufgaben";
  }
}

function _prefBool(prefs, camel, snake, fallback) {
  const value = prefs[camel] !== undefined ? prefs[camel] : prefs[snake];
  return typeof value === "boolean" ? value : fallback;
}

function _prefInt(prefs, camel, snake, fallback) {
  const value = prefs[camel] !== undefined ? prefs[camel] : prefs[snake];
  return typeof value === "number" ? value : fallback;
}

// Liegt `nowMinutes` (Minuten seit Mitternacht, lokal) im Ruhezeit-Fenster?
// Unterstützt Fenster über Mitternacht (z. B. 22:00–06:00).
function inQuietWindow(nowMinutes, startMinutes, endMinutes) {
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes < endMinutes;
}

// Darf an diesen Empfaenger ein SYSTEM-Push raus? (Das In-App-Inbox-Doc wird
// unabhaengig davon geschrieben.) `prefs` = rohe notificationPrefs vom User-Doc
// (oder null/undefined = Default an). `nowMinutes` = lokale Uhrzeit (Berlin).
function pushAllowed(prefs, type, nowMinutes) {
  if (!prefs || typeof prefs !== "object") return true;
  if (_prefBool(prefs, "masterEnabled", "master_enabled", true) === false) {
    return false;
  }
  const channel = channelIdForType(type);
  const categoryOn = typeof prefs[channel] === "boolean" ? prefs[channel] : true;
  if (categoryOn === false) return false;
  // Genehmigungen sind zeitkritisch -> auch in der Ruhezeit zustellen.
  if (channel !== "genehmigungen" &&
      _prefBool(prefs, "quietHoursEnabled", "quiet_hours_enabled", false)) {
    const start = _prefInt(prefs, "quietStartMinutes", "quiet_start_minutes", 1320);
    const end = _prefInt(prefs, "quietEndMinutes", "quiet_end_minutes", 360);
    if (inQuietWindow(nowMinutes, start, end)) return false;
  }
  return true;
}

// Aus der sendEachForMulticast-Antwort die Indizes der zu loeschenden Tokens
// bestimmen (`responses` ist index-parallel zur gesendeten Token-Liste).
function stalePruneIndices(responses) {
  const dead = [];
  responses.forEach((res, i) => {
    if (!res.success && res.error && STALE_TOKEN_CODES.has(res.error.code)) {
      dead.push(i);
    }
  });
  return dead;
}

module.exports = {
  STALE_TOKEN_CODES,
  truncate,
  formatDe,
  formatTimeDe,
  dedupeKey,
  uniqueUids,
  activeRecipientUids,
  managerUids,
  buildWishNotification,
  buildFeedbackNotification,
  buildAbsenceSubmittedNotification,
  buildAbsenceDecisionNotification,
  buildSwapNotification,
  buildShiftPublishedNotification,
  buildShiftOpenNotification,
  buildLowStockNotification,
  buildExpiryNotification,
  buildDocumentNotification,
  buildPayrollReleasedNotification,
  buildAutoKlaerungNotification,
  buildKlaerungResolvedNotification,
  isoWeek,
  channelIdForType,
  inQuietWindow,
  pushAllowed,
  stalePruneIndices,
};
