"use strict";

const crypto = require("node:crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated, onDocumentWritten} =
  require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const push = require("./push_notifications");

admin.initializeApp();

const db = admin.firestore();
// firebase-admin v13: FieldValue/Timestamp NICHT mehr zuverlaessig ueber den
// Namespace `admin.firestore.FieldValue` (kann undefined sein) -> Subpath-Import.
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const REGION = "europe-west3";

// OktoPOS-Kassen-API-Schluessel (HTTP-Header X-API-KEY). Ein Secret — NIE im
// Client-Bundle, NIE in Firestore, NIE per dart-define. Wert ist entweder ein
// einzelner Key-String (alle Standorte teilen ihn) ODER ein JSON-Objekt
// {"<siteId>": "<key>"} fuer einen Key je Standort/Division. Setzen via:
//   firebase functions:secrets:set OKTOPOS_API_KEYS
const OKTOPOS_API_KEYS = defineSecret("OKTOPOS_API_KEYS");

// Mindestversion des Callable-Payload-Vertrags (no-api-contract-versioning).
// Wird sie erhoeht, lehnt der Server zu alte Clients mit APP_UPDATE_REQUIRED ab.
const MIN_SUPPORTED_API_VERSION = 1;

// Vertragsversion pruefen: fehlt/unparsbar -> tolerieren (Backwards-Compat fuer
// Clients vor Einfuehrung des Feldes); nur eine ausdruecklich zu alte Version
// wird mit failed-precondition (APP_UPDATE_REQUIRED) blockiert.
function assertSupportedVersion(request) {
  const raw = request.data?.apiVersion;
  const version = typeof raw === "number" ? raw : Number.parseInt(raw, 10);
  if (Number.isFinite(version) && version < MIN_SUPPORTED_API_VERSION) {
    throw new HttpsError(
      "failed-precondition",
      "APP_UPDATE_REQUIRED",
      {minApiVersion: MIN_SUPPORTED_API_VERSION},
    );
  }
}

// Korrelations-/Trace-ID (no-distributed-tracing) des Clients uebernehmen ODER
// serverseitig erzeugen, damit Server-Logs mit Client-Fehlern verknuepfbar sind
// und JEDE Folge-Logzeile derselben Invocation dieselbe ID traegt. Loggt nie PII
// (kein uid/E-Mail), nur ob ueberhaupt authentifiziert.
function traceCallable(name, request) {
  const clientId = stringOrNull(request.data?._request_id);
  const requestId = clientId || crypto.randomUUID();
  logger.info("callable_start", {
    event: "callable_start",
    fn: name,
    requestId,
    requestIdSource: clientId ? "client" : "server",
    hasAuth: Boolean(request.auth),
  });
  return requestId;
}

// Einheitlicher Logging-Wrapper um jede Callable: zieht/erzeugt die Request-ID
// (Start-Log via traceCallable), reicht {requestId, fn} an den Handler durch und
// loggt Ende+Dauer bzw. Fehler+Code strukturiert (Fehler wird unveraendert
// re-thrown). Erwartbare HttpsError (Vertrag/Recht/Compliance/unavailable) als
// warn, unerwartete (kein HttpsError bzw. internal/unknown) als error. Loggt nie
// PII/Secrets; Fehlertext wird via truncateError gekappt.
function callable(name, options, handler) {
  return onCall(options, async (request) => {
    const requestId = traceCallable(name, request);
    const startedAt = Date.now();
    try {
      const result = await handler(request, {requestId, fn: name});
      logger.info("callable_done", {
        event: "callable_done",
        fn: name,
        requestId,
        durationMs: Date.now() - startedAt,
      });
      return result;
    } catch (error) {
      const code = error instanceof HttpsError ? error.code : "internal";
      const entry = {
        event: "callable_error",
        fn: name,
        requestId,
        durationMs: Date.now() - startedAt,
        code,
        message: truncateError(error),
      };
      if (error instanceof HttpsError && code !== "internal" &&
          code !== "unknown") {
        logger.warn("callable_error", entry);
      } else {
        logger.error("callable_error", entry);
      }
      throw error;
    }
  });
}

// === Push-Benachrichtigungen (Plan push-benachrichtigungen-plan.md) =========
// Firestore-Trigger statt Callable: erfasst JEDEN Write (Callable, Direkt-Write,
// anonymer oeffentlicher Pfad), den eine an die Callable gehaengte Logik
// verpassen wuerde.

// Logging-/Korrelations-Wrapper um einen onDocumentCreated-Trigger (analog zu
// callable()). Push-Fehler werden nach dem Log GESCHLUCKT (best-effort, kein
// Endlos-Retry) — die Idempotenz schuetzt ohnehin gegen Doppelversand.
function documentCreatedTrigger(name, options, handler) {
  return onDocumentCreated(options, async (event) => {
    const requestId = crypto.randomUUID();
    const startedAt = Date.now();
    logger.info("trigger_start", {event: "trigger_start", fn: name, requestId});
    try {
      await handler(event, {requestId, fn: name});
      logger.info("trigger_done", {
        event: "trigger_done", fn: name, requestId,
        durationMs: Date.now() - startedAt,
      });
    } catch (error) {
      logger.error("trigger_error", {
        event: "trigger_error", fn: name, requestId,
        durationMs: Date.now() - startedAt, message: truncateError(error),
      });
    }
  });
}

// Gemeinsamer Fan-out: je Empfaenger ein idempotentes Inbox-Doc anlegen
// (.create() = Dedupe-Anker), Tokens sammeln, per Multicast senden, ungueltige
// Tokens prunen. Loggt nie Token/PII.
// Aktuelle Uhrzeit (Berlin) als Minuten seit Mitternacht — fuer Ruhezeiten.
function nowMinutesBerlin() {
  const parts = new Intl.DateTimeFormat("de-DE", {
    timeZone: "Europe/Berlin", hour: "2-digit", minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  let hour = 0;
  let minute = 0;
  for (const part of parts) {
    if (part.type === "hour") hour = Number(part.value) % 24;
    if (part.type === "minute") minute = Number(part.value);
  }
  return hour * 60 + minute;
}

async function fanOutPush({orgId, recipientUids, notif, requestId}) {
  const notifCol = db.collection("organizations").doc(orgId)
    .collection("notifications");
  const tokenEntries = []; // {ref, token}
  const nowMinutes = nowMinutesBerlin();
  let suppressed = 0;

  for (const uid of recipientUids) {
    const key = push.dedupeKey(notif.type, notif.dedupeId || notif.entityId, uid);
    try {
      await notifCol.doc(key).create({
        recipientUid: uid,
        category: notif.type,
        title: notif.title,
        body: notif.body,
        route: notif.route,
        entityType: notif.entityType,
        entityId: notif.entityId,
        dedupeKey: key,
        readAt: null,
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // .create() schlaegt fehl, wenn das Inbox-Doc schon existiert -> dieses
      // Ereignis wurde fuer den Nutzer bereits zugestellt, NICHT erneut senden.
      continue;
    }
    // Push-Praeferenzen (M5): das In-App-Inbox-Doc oben wird IMMER geschrieben;
    // der System-Push wird unterdrueckt, wenn Master/Kategorie aus oder Ruhezeit.
    const userSnap = await db.collection("users").doc(uid).get();
    const prefs = userSnap.exists ? userSnap.get("notificationPrefs") : null;
    if (!push.pushAllowed(prefs, notif.type, nowMinutes)) {
      suppressed += 1;
      continue;
    }
    const tokensSnap = await db.collection("users").doc(uid)
      .collection("fcmTokens").get();
    tokensSnap.forEach((t) => {
      const token = t.get("token");
      if (typeof token === "string" && token) {
        tokenEntries.push({ref: t.ref, token});
      }
    });
  }

  if (tokenEntries.length === 0) {
    logger.info("push_sent", {
      fn: "fanOutPush", requestId, recipients: recipientUids.length,
      tokens: 0, suppressed,
    });
    return;
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens: tokenEntries.map((e) => e.token),
    notification: {title: notif.title, body: notif.body},
    data: {
      type: notif.type,
      entityId: String(notif.entityId || ""),
      deepLink: notif.route,
      orgId,
      thread: notif.thread,
      _request_id: requestId,
    },
  });

  const dead = push.stalePruneIndices(response.responses);
  await Promise.all(
    dead.map((i) => tokenEntries[i].ref.delete().catch(() => {})),
  );

  logger.info("push_sent", {
    fn: "fanOutPush", requestId,
    recipients: recipientUids.length,
    tokens: tokenEntries.length,
    sent: response.successCount,
    failed: response.failureCount,
    pruned: dead.length,
    suppressed,
  });
}

// Neuer Kundenwunsch (oeffentlich/anonym via /wunsch) -> ALLE aktiven
// Mitarbeiter der Org benachrichtigen ("bitte vorbereiten").
exports.onCustomerWishCreated = documentCreatedTrigger(
  "onCustomerWishCreated",
  {region: REGION, document: "organizations/{orgId}/customerWishes/{wishId}"},
  async (event, ctx) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }
    const orgId = event.params.orgId;
    const data = snapshot.data() || {};

    const notif = push.buildWishNotification({
      wishId: event.params.wishId,
      storeName: stringFromEither(data, "storeName", "store_name"),
      wishText: stringFromEither(data, "wishText", "wish_text"),
    });

    const usersSnap = await db.collection("users")
      .where("orgId", "==", orgId).get();
    const users = usersSnap.docs.map((doc) => ({
      uid: doc.id,
      isActive: isTruthy(valueFromEither(doc.data(), "isActive", "is_active")),
    }));
    const recipientUids = push.activeRecipientUids(users);

    if (recipientUids.length === 0) {
      logger.info("push_no_recipients", {
        fn: ctx.fn, requestId: ctx.requestId, orgId,
      });
      return;
    }

    await fanOutPush({
      orgId, recipientUids, notif, requestId: ctx.requestId,
    });
  },
);

// onDocumentWritten-Variante des Logging-Wrappers (Status-Uebergaenge).
function documentWrittenTrigger(name, options, handler) {
  return onDocumentWritten(options, async (event) => {
    const requestId = crypto.randomUUID();
    const startedAt = Date.now();
    logger.info("trigger_start", {event: "trigger_start", fn: name, requestId});
    try {
      await handler(event, {requestId, fn: name});
      logger.info("trigger_done", {
        event: "trigger_done", fn: name, requestId,
        durationMs: Date.now() - startedAt,
      });
    } catch (error) {
      logger.error("trigger_error", {
        event: "trigger_error", fn: name, requestId,
        durationMs: Date.now() - startedAt, message: truncateError(error),
      });
    }
  });
}

// Org-Nutzer als normalisierte Datensaetze fuer die Empfaenger-Aufloesung
// (Permissions/Rolle hier aufgeloest -> push_notifications.js bleibt pur).
async function loadOrgUserRecords(orgId) {
  const snapshot = await db.collection("users")
    .where("orgId", "==", orgId).get();
  return snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const permissions = resolvePermissions(data);
    return {
      uid: doc.id,
      isActive: isTruthy(valueFromEither(data, "isActive", "is_active")),
      isAdmin: normalizeRole(data.role) === "admin",
      canEditSchedule: permissions.canEditSchedule,
    };
  });
}

function readTriggerDate(data, primaryKey, legacyKey) {
  const value = valueFromEither(data, primaryKey, legacyKey);
  if (value && typeof value.toDate === "function") {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function numberFromEither(data, primaryKey, legacyKey) {
  const value = valueFromEither(data, primaryKey, legacyKey);
  if (typeof value === "number") {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

const ABSENCE_TYPE_LABELS = {
  vacation: "Urlaub",
  sickness: "Krankmeldung",
  child_sick: "Kind krank",
  unavailable: "Nicht verfügbar",
  special_leave: "Sonderurlaub",
  unpaid_leave: "Unbezahlt",
  time_off: "Zeitausgleich",
  parental_leave: "Elternzeit",
  maternity: "Mutterschutz",
  vocational_school: "Berufsschule",
  volunteering: "Ehrenamt",
  short_time_work: "Kurzarbeit",
};

function absenceTypeLabel(value) {
  return ABSENCE_TYPE_LABELS[stringOrEmpty(value)] || "Abwesenheit";
}

// Neues Feedback/Beschwerde (oeffentlich/anonym) -> Manager.
exports.onCustomerFeedbackCreated = documentCreatedTrigger(
  "onCustomerFeedbackCreated",
  {region: REGION, document: "organizations/{orgId}/customerFeedback/{feedbackId}"},
  async (event, ctx) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }
    const orgId = event.params.orgId;
    const data = snapshot.data() || {};
    const notif = push.buildFeedbackNotification({
      feedbackId: event.params.feedbackId,
      type: stringOrEmpty(data.type),
      message: stringFromEither(data, "message", "message"),
    });
    const recipientUids = push.managerUids(await loadOrgUserRecords(orgId));
    if (recipientUids.length === 0) {
      return;
    }
    await fanOutPush({orgId, recipientUids, notif, requestId: ctx.requestId});
  },
);

// Abwesenheit: eingereicht -> Manager; genehmigt/abgelehnt -> Antragsteller.
exports.onAbsenceRequestWritten = documentWrittenTrigger(
  "onAbsenceRequestWritten",
  {region: REGION, document: "organizations/{orgId}/absenceRequests/{absenceId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const absenceId = event.params.absenceId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const beforeStatus = before ? stringOrEmpty(before.status) : null;
    const afterStatus = stringOrEmpty(after.status);
    const typeLabel = absenceTypeLabel(after.type);
    const start = push.formatDe(readTriggerDate(after, "startDate", "start_date"));
    const end = push.formatDe(readTriggerDate(after, "endDate", "end_date"));

    if (afterStatus === "pending" && beforeStatus !== "pending") {
      const recipientUids = push.managerUids(await loadOrgUserRecords(orgId));
      if (recipientUids.length === 0) {
        return;
      }
      const notif = push.buildAbsenceSubmittedNotification({
        absenceId,
        employeeName: stringFromEither(after, "employeeName", "employee_name"),
        typeLabel, start, end,
      });
      await fanOutPush({orgId, recipientUids, notif, requestId: ctx.requestId});
      return;
    }

    if (beforeStatus === "pending" &&
        (afterStatus === "approved" || afterStatus === "rejected")) {
      const requester = stringFromEither(after, "userId", "user_id");
      if (!requester) {
        return;
      }
      const notif = push.buildAbsenceDecisionNotification({
        absenceId, typeLabel, start, end, approved: afterStatus === "approved",
      });
      await fanOutPush({
        orgId, recipientUids: [requester], notif, requestId: ctx.requestId,
      });
    }
  },
);

// Schichttausch-Lebenszyklus: phasenabhaengige Empfaenger.
exports.onShiftSwapRequestWritten = documentWrittenTrigger(
  "onShiftSwapRequestWritten",
  {region: REGION, document: "organizations/{orgId}/shiftSwapRequests/{swapId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const swapId = event.params.swapId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const beforeStatus = before ? stringOrEmpty(before.status) : null;
    const afterStatus = stringOrEmpty(after.status);
    if (afterStatus === beforeStatus) {
      return;
    }
    const requesterUid = stringFromEither(after, "requesterUid", "requester_uid");
    const targetUid = stringFromEither(after, "targetUid", "target_uid");
    const meta = {
      swapId,
      requesterName: stringFromEither(after, "requesterName", "requester_name"),
      targetName: stringFromEither(after, "targetName", "target_name"),
      shiftDate: "",
    };

    let phase = null;
    let recipients = [];
    if (afterStatus === "pending" && !beforeStatus) {
      phase = "request";
      recipients = [targetUid];
    } else if (afterStatus === "accepted_by_colleague") {
      phase = "accepted";
      recipients = push.managerUids(await loadOrgUserRecords(orgId));
    } else if (afterStatus === "declined_by_colleague") {
      phase = "declined";
      recipients = [requesterUid];
    } else if (afterStatus === "confirmed") {
      phase = "confirmed";
      recipients = [requesterUid, targetUid];
    } else if (afterStatus === "rejected_by_manager") {
      phase = "rejected";
      recipients = [requesterUid, targetUid];
    } else if (afterStatus === "cancelled") {
      phase = "rejected";
      recipients = [targetUid];
    }
    if (!phase) {
      return;
    }
    const notif = push.buildSwapNotification(phase, meta);
    const recipientUids = push.uniqueUids(recipients);
    if (notif && recipientUids.length > 0) {
      await fanOutPush({orgId, recipientUids, notif, requestId: ctx.requestId});
    }
  },
);

// Schicht: veroeffentlicht (planned->confirmed) -> zugewiesene(r) MA; frei
// geworden (z.B. Krankmeldung) -> Manager (neu besetzen).
exports.onShiftWritten = documentWrittenTrigger(
  "onShiftWritten",
  {region: REGION, document: "organizations/{orgId}/shifts/{shiftId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const shiftId = event.params.shiftId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const beforeStatus = before ? stringOrEmpty(before.status) : null;
    const afterStatus = stringOrEmpty(after.status);
    const beforeUser = before ?
      stringFromEither(before, "userId", "user_id") : "";
    const afterUser = stringFromEither(after, "userId", "user_id");
    const siteName = stringFromEither(after, "siteName", "site_name");
    const date = push.formatDe(readTriggerDate(after, "startTime", "start_time"));

    if (beforeStatus !== "confirmed" && afterStatus === "confirmed" && afterUser) {
      const week = push.isoWeek(readTriggerDate(after, "startTime", "start_time"));
      const notif = push.buildShiftPublishedNotification({
        shiftId, siteName, date,
        weekLabel: week ? `KW ${week.week}` : null,
      });
      // Bündelung (M7): EIN Push je Mitarbeiter & Woche statt einer je Schicht
      // (publishShiftBatch bestätigt bis zu 50 Schichten auf einmal).
      if (week) {
        notif.dedupeId = `${afterUser}:${week.year}-${week.week}`;
      }
      await fanOutPush({
        orgId, recipientUids: [afterUser], notif, requestId: ctx.requestId,
      });
      return;
    }

    if (beforeUser && !afterUser && afterStatus !== "cancelled") {
      const recipientUids = push.managerUids(await loadOrgUserRecords(orgId));
      if (recipientUids.length === 0) {
        return;
      }
      const notif = push.buildShiftOpenNotification({shiftId, siteName, date});
      await fanOutPush({orgId, recipientUids, notif, requestId: ctx.requestId});
    }
  },
);

// Bestand: faellt unter Meldebestand (Flanke) -> Bestands-/Inventar-Manager.
exports.onProductWritten = documentWrittenTrigger(
  "onProductWritten",
  {region: REGION, document: "organizations/{orgId}/products/{productId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const productId = event.params.productId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const needsReorder = (data) => {
      const min = numberFromEither(data, "minStock", "min_stock");
      const cur = numberFromEither(data, "currentStock", "current_stock");
      return min > 0 && cur <= min;
    };
    const beforeNeeds = before ? needsReorder(before) : false;
    if (beforeNeeds || !needsReorder(after)) {
      return; // nur die Flanke "jetzt unter Meldebestand" loest aus
    }
    const recipientUids = push.managerUids(await loadOrgUserRecords(orgId));
    if (recipientUids.length === 0) {
      return;
    }
    const notif = push.buildLowStockNotification({
      productId,
      productName: stringFromEither(after, "name", "name"),
      currentStock: numberFromEither(after, "currentStock", "current_stock"),
      minStock: numberFromEither(after, "minStock", "min_stock"),
      siteName: stringFromEither(after, "siteName", "site_name"),
    });
    // Taeglicher Re-Alert-Bucket: nach Restock + erneutem Unterschreiten darf an
    // einem anderen Tag wieder gepusht werden, am selben Tag nicht doppelt.
    notif.dedupeId =
      `${productId}:${new Date().toISOString().slice(0, 10)}`;
    await fanOutPush({orgId, recipientUids, notif, requestId: ctx.requestId});
  },
);

// Token-GC (M7) — Backstop zum Send-Pruning: entfernt Geräte-Tokens, die seit
// >270 Tagen nicht aktualisiert wurden (FCM verfällt ohnehin). Braucht den
// COLLECTION_GROUP-Index auf fcmTokens.updatedAt (firestore.indexes.json).
exports.pruneStaleFcmTokens = onSchedule(
  {region: REGION, schedule: "every day 03:30", timeZone: "Europe/Berlin"},
  async () => {
    const requestId = crypto.randomUUID();
    const cutoff = Timestamp.fromMillis(
      Date.now() - 270 * 24 * 60 * 60 * 1000);
    const snapshot = await db.collectionGroup("fcmTokens")
      .where("updatedAt", "<", cutoff).get();
    const refs = snapshot.docs.map((doc) => doc.ref);
    let deleted = 0;
    for (let i = 0; i < refs.length; i += 400) {
      const batch = db.batch();
      for (const ref of refs.slice(i, i + 400)) {
        batch.delete(ref);
      }
      await batch.commit();
      deleted += Math.min(400, refs.length - i);
    }
    logger.info("fcm_token_gc", {requestId, deleted});
  },
);

// MHD-/Ablauf-Warnung (zeitbasiert -> Scheduler, NICHT Trigger: kein Schreib-
// Ereignis feuert „in 3 Tagen"). Findet je Org die aktiven Warenchargen, deren
// Mindesthaltbarkeitsdatum in <= EXPIRY_LEAD_DAYS Kalendertagen liegt (oder schon
// abgelaufen ist), und benachrichtigt die aktiven Mitarbeiter. Idempotenz:
// dedupeId = `${batchId}:${expiryDay}` -> je Charge genau EIN Push (fanOutPush
// .create()-Dedupe), kein taegliches Wiederholen. Braucht den Composite-Index
// productBatches(status, expiryDay) (firestore.indexes.json) + Blaze (Scheduler).
const EXPIRY_LEAD_DAYS = 3;

// „YYYY-MM-DD" (Berlin) fuer heute + offsetDays. Der lexikographische Vergleich
// gegen das String-Feld expiryDay ist == chronologisch (deshalb das Feld).
function berlinDayString(offsetDays) {
  const base = new Date(Date.now() + (offsetDays || 0) * 24 * 60 * 60 * 1000);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(base);
  let y = "";
  let m = "";
  let d = "";
  for (const p of parts) {
    if (p.type === "year") y = p.value;
    if (p.type === "month") m = p.value;
    if (p.type === "day") d = p.value;
  }
  return `${y}-${m}-${d}`;
}

// Ganze Kalendertage zwischen zwei „YYYY-MM-DD"-Strings (UTC-basiert ->
// DST-robust). null bei ungueltiger Eingabe.
function daysBetweenDayStrings(fromDay, toDay) {
  const a = Date.parse(`${fromDay}T00:00:00Z`);
  const b = Date.parse(`${toDay}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / 86400000);
}

exports.expiryWarningNightly = onSchedule(
  {region: REGION, schedule: "every day 07:00", timeZone: "Europe/Berlin"},
  async () => {
    const requestId = crypto.randomUUID();
    const todayStr = berlinDayString(0);
    const thresholdStr = berlinDayString(EXPIRY_LEAD_DAYS);
    const orgsSnap = await db.collection("organizations").limit(50).get();
    let orgsProcessed = 0;
    let warned = 0;
    for (const orgDoc of orgsSnap.docs) {
      const orgId = orgDoc.id;
      let batchesSnap;
      try {
        batchesSnap = await db.collection("organizations").doc(orgId)
          .collection("productBatches")
          .where("status", "==", "active")
          .where("expiryDay", "<=", thresholdStr)
          .get();
      } catch (error) {
        logger.error("expiry_query_error", {
          event: "expiry_query_error", fn: "expiryWarningNightly",
          requestId, orgId, message: truncateError(error),
        });
        continue;
      }
      if (batchesSnap.empty) {
        continue;
      }
      const recipientUids = push.activeRecipientUids(
        await loadOrgUserRecords(orgId));
      if (recipientUids.length === 0) {
        continue;
      }
      // Standortnamen einmal je Org aufloesen (Chargen tragen nur die siteId).
      const siteNameById = {};
      try {
        const sitesSnap = await db.collection("organizations").doc(orgId)
          .collection("sites").get();
        sitesSnap.forEach((s) => {
          siteNameById[s.id] = stringOrEmpty((s.data() || {}).name);
        });
      } catch (error) {
        // Ohne Namen wird trotzdem gewarnt (nur ohne Ladennamen im Text).
      }
      orgsProcessed += 1;
      for (const doc of batchesSnap.docs) {
        const data = doc.data() || {};
        const expiryDay = stringOrEmpty(data.expiryDay);
        if (!expiryDay) continue;
        const notif = push.buildExpiryNotification({
          batchId: doc.id,
          productName: stringOrEmpty(data.productName),
          siteName: siteNameById[stringOrEmpty(data.siteId)] || "",
          daysUntilExpiry: daysBetweenDayStrings(todayStr, expiryDay),
        });
        // Je Charge genau ein Push (unabhaengig vom Lauf-Tag).
        notif.dedupeId = `${doc.id}:${expiryDay}`;
        await fanOutPush({orgId, recipientUids, notif, requestId});
        warned += 1;
      }
    }
    logger.info("expiry_warning_done", {
      event: "expiry_warning_done", fn: "expiryWarningNightly",
      requestId, orgsProcessed, warned,
    });
  },
);

exports.upsertShiftBatch = callable("upsertShiftBatch", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  assertScheduler(caller);

  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const rawShifts = asArray(request.data?.shifts);
  if (rawShifts.length === 0) {
    return {savedIds: [], issues: []};
  }

  if (rawShifts.length > 50) {
    throw new HttpsError(
      "resource-exhausted",
      "Batch Limit ueberschritten (max 50 Schichten)."
    );
  }

  const shifts = rawShifts.map((item, index) => parseShift(item, index, orgId));
  const issues = await validateShiftBatch({orgId, shifts});
  if (issues.some((issue) => issue.violations.some(isBlockingViolation))) {
    throw new HttpsError(
      "failed-precondition",
      "Es wurden Regelverletzungen fuer den Schichtplan gefunden.",
      {issues},
    );
  }

  const savedIds = await writeShiftBatch({
    callerUid: caller.uid,
    shifts,
  });
  return {savedIds, issues};
});

exports.publishShiftBatch = callable("publishShiftBatch", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  assertScheduler(caller);

  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const status = requiredString(request.data?.status, "status");
  const rawShifts = asArray(request.data?.shifts);
  if (rawShifts.length === 0) {
    return {savedIds: [], issues: []};
  }

  if (rawShifts.length > 50) {
    throw new HttpsError(
      "resource-exhausted",
      "Batch Limit ueberschritten (max 50 Schichten)."
    );
  }

  const shifts = rawShifts
    .map((item, index) => parseShift(item, index, orgId))
    .map((shift) => ({...shift, status}));
  const issues = await validateShiftBatch({orgId, shifts});
  if (issues.some((issue) => issue.violations.some(isBlockingViolation))) {
    throw new HttpsError(
      "failed-precondition",
      "Es wurden Regelverletzungen fuer den Schichtplan gefunden.",
      {issues},
    );
  }

  const savedIds = await writeShiftBatch({
    callerUid: caller.uid,
    shifts,
  });
  return {savedIds, issues};
});

exports.upsertWorkEntry = callable("upsertWorkEntry", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  assertTimeEntryEditor(caller);
  const entry = parseWorkEntry(request.data?.entry);
  assertSameOrg(caller, entry.orgId);
  if (caller.uid !== entry.userId && !caller.isAdmin) {
    throw new HttpsError(
      "permission-denied",
      "Nur Admins duerfen Zeiteintraege fuer andere Mitarbeiter aendern.",
    );
  }

  const validation = await validateWorkEntry({callerUid: caller.uid, entry});
  if (validation.violations.some(isBlockingViolation)) {
    throw new HttpsError(
      "failed-precondition",
      "Es wurden Regelverletzungen fuer den Zeiteintrag gefunden.",
      validation,
    );
  }

  const collection = organizationCollection(entry.orgId, "workEntries");
  const docId = entry.id ?? buildWorkEntryDocumentId(entry);
  const docRef = collection.doc(docId);
  const snapshot = await docRef.get();
  await docRef.set(
    {
      ...toFirestoreWorkEntry(entry, caller.uid),
      ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    },
    {merge: true},
  );

  return {
    savedId: docId,
    violations: validation.violations,
  };
});

exports.upsertWorkEntryBatch = callable("upsertWorkEntryBatch", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  assertTimeEntryEditor(caller);
  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const rawEntries = asArray(request.data?.entries);
  if (rawEntries.length === 0) {
    return {savedIds: [], validations: []};
  }

  if (rawEntries.length > 50) {
    throw new HttpsError(
      "resource-exhausted",
      "Batch Limit ueberschritten (max 50 Eintraege)."
    );
  }

  const entries = rawEntries.map((item) => parseWorkEntry(item));
  for (const entry of entries) {
    assertSameOrg(caller, entry.orgId);
    if (caller.uid !== entry.userId && !caller.isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Nur Admins duerfen Zeiteintraege fuer andere Mitarbeiter aendern.",
      );
    }
  }

  const validations = [];
  for (const entry of entries) {
    const validation = await validateWorkEntry({callerUid: caller.uid, entry});
    validations.push(validation);
  }
  if (validations.some((item) => item.violations.some(isBlockingViolation))) {
    throw new HttpsError(
      "failed-precondition",
      "Es wurden Regelverletzungen fuer die Zeiteintraege gefunden.",
      {validations},
    );
  }

  const savedIds = await writeWorkEntryBatch({
    callerUid: caller.uid,
    entries,
  });
  return {savedIds, validations};
});

exports.previewCompliance = callable("previewCompliance", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);

  if (Array.isArray(request.data?.shifts) && request.data.shifts.length > 0) {
    // Gleiches Rollen-Gate wie der Schreibpfad upsertShiftBatch, damit die
    // Preview keine Personaldaten an Nicht-Planer preisgibt (Information
    // Disclosure / API05 Function-Level-Authorization).
    assertScheduler(caller);
    const shifts = request.data.shifts.map((item, index) =>
      parseShift(item, index, orgId),
    );
    const issues = await validateShiftBatch({orgId, shifts});
    return {issues};
  }

  if (request.data?.entry != null) {
    assertTimeEntryEditor(caller);
    const entry = parseWorkEntry(request.data.entry);
    assertSameOrg(caller, entry.orgId);
    if (caller.uid !== entry.userId && !caller.isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Nur Admins duerfen Compliance fuer fremde Zeiteintraege pruefen.",
      );
    }
    const validation = await validateWorkEntry({callerUid: caller.uid, entry});
    return validation;
  }

  throw new HttpsError(
    "invalid-argument",
    "Es wurde weder ein Schichtpaket noch ein Zeiteintrag uebergeben.",
  );
});

// === Arbeitsmodus / Laden-Tablet (Kiosk) ====================================
// Server-gepruefte PIN fuer das geteilte Tablet (Plan
// plan/arbeitsmodus-laden-tablet.md, Increment 2). PIN-Hash liegt in einer fuer
// Clients UNLESBAREN Collection (organizations/{orgId}/userSecrets/{uid},
// firestore.rules: read/write if false) — nur diese Functions (Admin SDK)
// lesen/schreiben ihn. Der Mitarbeiter setzt die PIN auf dem EIGENEN Handy
// (setKioskPin, request.auth = Mitarbeiter); das Kiosk-Geraet meldet ihn per
// PIN an (kioskBeginSession, request.auth = Geraete-Konto).
const KIOSK_PIN_REGEX = /^\d{4,8}$/;
const KIOSK_MAX_PIN_ATTEMPTS = 5;
const KIOSK_LOCKOUT_MS = 5 * 60 * 1000; // 5 Minuten Sperre nach zu vielen Fehlern
const KIOSK_SESSION_TTL_MS = 10 * 60 * 1000; // harte Server-Obergrenze der Session

// PIN-Hash: scrypt mit zufaelligem Salt (NIE Klartext, NIE Client-SHA1 — Plan E1).
// Format "scrypt$<saltHex>$<hashHex>".
function hashKioskPin(pin) {
  const salt = crypto.randomBytes(16);
  const derived = crypto.scryptSync(pin, salt, 64);
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}`;
}

function verifyKioskPin(pin, stored) {
  if (typeof stored !== "string") return false;
  const parts = stored.split("$");
  if (parts.length !== 3 || parts[0] !== "scrypt") return false;
  const salt = Buffer.from(parts[1], "hex");
  const expected = Buffer.from(parts[2], "hex");
  const derived = crypto.scryptSync(pin, salt, expected.length);
  return derived.length === expected.length &&
    crypto.timingSafeEqual(derived, expected);
}

// setKioskPin: der Mitarbeiter setzt/aendert seine Kiosk-PIN auf dem eigenen
// Handy. request.auth == Mitarbeiter; Hash landet in userSecrets/{uid}.
exports.setKioskPin = callable("setKioskPin", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  const pin = stringOrNull(request.data?.pin);
  if (!pin || !KIOSK_PIN_REGEX.test(pin)) {
    throw new HttpsError(
      "invalid-argument",
      "Die PIN muss aus 4 bis 8 Ziffern bestehen.",
    );
  }
  await organizationCollection(caller.orgId, "userSecrets").doc(caller.uid).set({
    orgId: caller.orgId,
    uid: caller.uid,
    pinHash: hashKioskPin(pin),
    pinAlgo: "scrypt",
    failedAttempts: 0,
    lockedUntil: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

// resetKioskPin: ein Admin loescht die PIN eines Mitarbeiters (erzwingt Neu-
// Setzen) und hebt eine Sperre auf.
exports.resetKioskPin = callable("resetKioskPin", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  if (!caller.isAdmin) {
    throw new HttpsError(
      "permission-denied",
      "Nur Admins duerfen PINs zuruecksetzen.",
    );
  }
  const employeeId = stringOrNull(request.data?.employeeId);
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "employeeId fehlt.");
  }
  await organizationCollection(caller.orgId, "userSecrets")
    .doc(employeeId).delete();
  return {ok: true};
});

// kioskBeginSession: das Kiosk-Geraet meldet einen Mitarbeiter per PIN an.
// request.auth == Geraete-Konto. Prueft PIN serverseitig (scrypt) + Rate-Limit/
// Lockout + gleiche Org, legt eine kurzlebige Session an und gibt deren `sid`
// zurueck. App Check erzwungen (nur die echte App darf anmelden).
exports.kioskBeginSession = callable(
  "kioskBeginSession",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request); // Geraete-Konto
    const employeeId = stringOrNull(request.data?.employeeId);
    const pin = stringOrNull(request.data?.pin);
    const deviceId = stringOrNull(request.data?.deviceId);
    if (!employeeId || !pin) {
      throw new HttpsError("invalid-argument", "employeeId oder PIN fehlt.");
    }

    const empSnap = await db.collection("users").doc(employeeId).get();
    if (!empSnap.exists) {
      throw new HttpsError("not-found", "Mitarbeiter unbekannt.");
    }
    const empData = empSnap.data() || {};
    const empOrg = stringFromEither(empData, "orgId", "org_id");
    // Geraet und Mitarbeiter MUESSEN in derselben Org sein (Mandantengrenze).
    assertSameOrg(caller, empOrg);
    if (!isTruthy(valueFromEither(empData, "isActive", "is_active"))) {
      throw new HttpsError("permission-denied", "Mitarbeiter ist deaktiviert.");
    }

    const secretRef = organizationCollection(empOrg, "userSecrets")
      .doc(employeeId);
    const secretSnap = await secretRef.get();
    if (!secretSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Fuer diesen Mitarbeiter ist noch keine PIN hinterlegt.",
      );
    }
    const secret = secretSnap.data() || {};
    const lockedUntilMs = secret.lockedUntil?.toMillis?.() ?? 0;
    if (lockedUntilMs > Date.now()) {
      throw new HttpsError(
        "resource-exhausted",
        "Zu viele Fehlversuche. Bitte spaeter erneut versuchen.",
      );
    }

    if (!verifyKioskPin(pin, secret.pinHash)) {
      const attempts = (Number(secret.failedAttempts) || 0) + 1;
      const update = {failedAttempts: attempts};
      if (attempts >= KIOSK_MAX_PIN_ATTEMPTS) {
        update.failedAttempts = 0;
        update.lockedUntil = Timestamp.fromMillis(Date.now() + KIOSK_LOCKOUT_MS);
      }
      await secretRef.set(update, {merge: true});
      throw new HttpsError("permission-denied", "Falsche PIN.");
    }

    // Erfolg: Zaehler zuruecksetzen, Session anlegen.
    await secretRef.set({failedAttempts: 0, lockedUntil: null}, {merge: true});
    const sid = crypto.randomUUID();
    await organizationCollection(empOrg, "kioskSessions").doc(sid).set({
      sid,
      orgId: empOrg,
      employeeId,
      deviceId: deviceId || null,
      createdByUid: caller.uid,
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + KIOSK_SESSION_TTL_MS),
      revokedAt: null,
    });
    return {sid, expiresInMs: KIOSK_SESSION_TTL_MS};
  },
);

// kioskEndSession: Session serverseitig beenden (Logout/„Fertig").
exports.kioskEndSession = callable(
  "kioskEndSession",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    const caller = await loadCallerProfile(request);
    const sid = stringOrNull(request.data?.sid);
    if (!sid) throw new HttpsError("invalid-argument", "sid fehlt.");
    await organizationCollection(caller.orgId, "kioskSessions").doc(sid).set(
      {revokedAt: FieldValue.serverTimestamp()},
      {merge: true},
    );
    return {ok: true};
  },
);

// Laedt und prueft eine aktive Kiosk-Session (nicht abgelaufen/widerrufen) und
// stellt sicher, dass sie zum aufrufenden Geraet (gleiche Org) gehoert.
async function requireKioskSession(caller, sid) {
  if (!sid) throw new HttpsError("invalid-argument", "sid fehlt.");
  const ref = organizationCollection(caller.orgId, "kioskSessions").doc(sid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "Kiosk-Session ungueltig.");
  }
  const data = snap.data() || {};
  const expiresMs = data.expiresAt?.toMillis?.() ?? 0;
  if (data.revokedAt || expiresMs < Date.now()) {
    throw new HttpsError("permission-denied", "Kiosk-Session abgelaufen.");
  }
  if (data.orgId !== caller.orgId) {
    throw new HttpsError("permission-denied", "Kiosk-Session fremd.");
  }
  return data;
}

// kioskClockPunch: Stempeln (Kommen/Gehen) am Kiosk fuer den Session-Mitarbeiter.
// Schreibt eine ClockEntry ALS der Mitarbeiter (Admin SDK) — autorisiert ueber
// die Session, nicht ueber self/admin. `direction` = "in" (offene Session
// anlegen) | "out" (offene Session schliessen).
//
// HINWEIS (emulator-pending): die volle WorkEntry-/ArbZG-Generierung wie im
// Client-`ClockService`/`upsertWorkEntry` ist hier bewusst NOCH NICHT gebaut —
// diese Funktion persistiert die Praesenz (Kommen/Gehen) revisionssicher mit
// `source:'kiosk'` + `sessionId`; die Umwandlung in einen abrechnungsrelevanten
// WorkEntry (inkl. Pausen nach ArbZG, Compliance-Spiegel) ist der verbleibende,
// auf dem Emulator zu verifizierende Schritt (Kopplung #2).
// ArbZG-Pflichtpause (Brutto-Minuten) — 1:1 zu ClockService.requiredBreakMinutes
// (30 min ab >6 h, 45 min ab >9 h). Compliance-Spiegel (CLAUDE.md Kopplung #2).
function kioskRequiredBreakMinutes(grossMinutes) {
  if (grossMinutes > 540) return 45;
  if (grossMinutes > 360) return 30;
  return 0;
}

async function findOpenClockEntry(orgId, employeeId) {
  const snap = await organizationCollection(orgId, "clockEntries")
    .where("userId", "==", employeeId)
    .where("status", "==", "ongoing")
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0];
}

exports.kioskClockPunch = callable(
  "kioskClockPunch",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request); // Geraete-Konto
    const sid = stringOrNull(request.data?.sid);
    const direction = stringOrNull(request.data?.direction);
    const session = await requireKioskSession(caller, sid);
    const orgId = session.orgId;
    const employeeId = session.employeeId;
    const clockEntries = organizationCollection(orgId, "clockEntries");

    // Nur-Abfrage: ist der Mitarbeiter eingestempelt? (für die Button-Anzeige)
    if (direction === "status") {
      const open = await findOpenClockEntry(orgId, employeeId);
      return {clockedIn: Boolean(open)};
    }

    if (direction === "in") {
      const existing = await findOpenClockEntry(orgId, employeeId);
      if (existing) {
        return {clockedIn: true, clockEntryId: existing.id};
      }
      const docRef = clockEntries.doc();
      await docRef.set({
        orgId,
        userId: employeeId,
        siteId: stringOrNull(request.data?.siteId),
        siteName: stringOrNull(request.data?.siteName),
        kommen: FieldValue.serverTimestamp(),
        gehen: null,
        pauseMinuten: 0,
        nettoMinutes: 0,
        status: "ongoing",
        source: "kiosk",
        deviceId: session.deviceId || null,
        sessionId: sid,
        createdByUid: caller.uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {clockedIn: true, clockEntryId: docRef.id};
    }

    if (direction === "out") {
      const doc = await findOpenClockEntry(orgId, employeeId);
      if (!doc) {
        return {clockedIn: false};
      }
      const data = doc.data() || {};
      const kommenMs = data.kommen?.toMillis?.() ?? Date.now();
      const nowMs = Date.now();
      const grossMin = Math.max(0, Math.round((nowMs - kommenMs) / 60000));
      const clientPause = Number(request.data?.pauseMinuten) || 0;
      const pause = Math.max(clientPause, kioskRequiredBreakMinutes(grossMin));
      const netto = Math.max(0, grossMin - pause);
      const gehenTs = Timestamp.fromMillis(nowMs);

      await doc.ref.set({
        gehen: gehenTs,
        pauseMinuten: pause,
        nettoMinutes: netto,
        status: "completed",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      // Abrechnungsrelevanten WorkEntry(submitted) erzeugen — best-effort, wie
      // der Client-Stempel (der Admin gibt „submitted" frei). Compliance wird
      // NICHT hart geprüft (Freigabe-Workflow fängt es), analog zum Client, der
      // die WorkEntry-Erzeugung ebenfalls nicht blockierend macht.
      // HINWEIS: emulator-pending — vor Produktiv-Deploy verifizieren.
      await organizationCollection(orgId, "workEntries").add({
        orgId,
        userId: employeeId,
        date: data.kommen ?? gehenTs,
        startTime: data.kommen ?? gehenTs,
        endTime: gehenTs,
        breakMinutes: pause,
        siteId: data.siteId ?? null,
        siteName: data.siteName ?? null,
        category: "stempel",
        status: "submitted",
        sourceClockEntryId: doc.id,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {clockedIn: false, clockEntryId: doc.id};
    }

    throw new HttpsError(
      "invalid-argument",
      "direction muss 'in', 'out' oder 'status' sein.",
    );
  },
);

async function loadCallerProfile(request) {
  if (!request.auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "Du musst angemeldet sein, um diese Aktion auszufuehren.",
    );
  }

  const snapshot = await db.collection("users").doc(request.auth.uid).get();
  if (!snapshot.exists) {
    throw new HttpsError(
      "permission-denied",
      "Fuer das aktuelle Konto liegt kein Benutzerprofil vor.",
    );
  }

  const data = snapshot.data() || {};
  if (!isTruthy(valueFromEither(data, "isActive", "is_active"))) {
    throw new HttpsError(
      "permission-denied",
      "Das Benutzerkonto ist deaktiviert.",
    );
  }

  const role = normalizeRole(data.role);

  return {
    uid: snapshot.id,
    orgId: stringFromEither(data, "orgId", "org_id"),
    role,
    isAdmin: role === "admin",
    permissions: resolvePermissions(data),
  };
}

function assertScheduler(caller) {
  if (!caller.isAdmin && !caller.permissions.canEditSchedule) {
    throw new HttpsError(
      "permission-denied",
      "Fuer dieses Profil ist die Schichtplanung deaktiviert.",
    );
  }
}

function assertTimeEntryEditor(caller) {
  if (!caller.isAdmin && !caller.permissions.canEditTimeEntries) {
    throw new HttpsError(
      "permission-denied",
      "Fuer dieses Profil ist die Bearbeitung von Zeiteintraegen deaktiviert.",
    );
  }
}

function assertSameOrg(caller, orgId) {
  if (caller.orgId !== orgId) {
    throw new HttpsError(
      "permission-denied",
      "Die angeforderte Organisation passt nicht zum angemeldeten Benutzer.",
    );
  }
}

function resolvePermissions(data) {
  const role = normalizeRole(data.role);
  const defaults = permissionDefaultsForRole(role);
  const permissions = isPlainObject(data.permissions) ? data.permissions : {};
  return {
    canViewSchedule: booleanOrDefault(
      permissions.canViewSchedule,
      defaults.canViewSchedule,
    ),
    canEditSchedule: booleanOrDefault(
      permissions.canEditSchedule,
      defaults.canEditSchedule,
    ),
    canViewTimeTracking: booleanOrDefault(
      permissions.canViewTimeTracking,
      defaults.canViewTimeTracking,
    ),
    canEditTimeEntries: booleanOrDefault(
      permissions.canEditTimeEntries,
      defaults.canEditTimeEntries,
    ),
    canViewReports: booleanOrDefault(
      permissions.canViewReports,
      defaults.canViewReports,
    ),
  };
}

function permissionDefaultsForRole(role) {
  switch (normalizeRole(role)) {
    case "admin":
      return {
        canViewSchedule: true,
        canEditSchedule: true,
        canViewTimeTracking: true,
        canEditTimeEntries: true,
        canViewReports: true,
      };
    case "teamlead":
      return {
        canViewSchedule: true,
        canEditSchedule: true,
        canViewTimeTracking: true,
        canEditTimeEntries: true,
        canViewReports: true,
      };
    default:
      return {
        canViewSchedule: true,
        canEditSchedule: false,
        canViewTimeTracking: true,
        canEditTimeEntries: true,
        canViewReports: true,
      };
  }
}

function booleanOrDefault(value, fallback) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return value.trim().toLowerCase() === "true";
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  return fallback;
}

function valueFromEither(data, primaryKey, legacyKey) {
  if (!isPlainObject(data)) {
    return undefined;
  }
  if (Object.prototype.hasOwnProperty.call(data, primaryKey)) {
    return data[primaryKey];
  }
  if (Object.prototype.hasOwnProperty.call(data, legacyKey)) {
    return data[legacyKey];
  }
  return undefined;
}

function stringFromEither(data, primaryKey, legacyKey) {
  return stringOrEmpty(valueFromEither(data, primaryKey, legacyKey));
}

function isTruthy(value) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return value.trim().toLowerCase() === "true";
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  return false;
}

function normalizeRole(value) {
  const role = stringOrEmpty(value).trim().toLowerCase();
  if (role === "teamleiter") {
    return "teamlead";
  }
  return role;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

async function validateShiftBatch({orgId, shifts}) {
  const context = await loadShiftValidationContext(orgId, shifts);
  return shifts
    .map((shift) => ({
      shiftId: shift.id || null,
      draftKey: shift.draftKey,
      employeeName: shift.employeeName,
      title: shift.title,
      violations: validateSingleShift({
        shift,
        existingShifts: context.existingShifts,
        draftShifts: shifts,
        absences: context.absences,
        contracts: context.contracts,
        siteAssignments: context.siteAssignments,
        ruleSets: context.ruleSets,
        travelTimeRules: context.travelTimeRules,
        members: context.members,
      }),
    }))
    .filter((issue) => issue.violations.length > 0);
}

async function writeShiftBatch({callerUid, shifts}) {
  const collection = organizationCollection(shifts[0].orgId, "shifts");
  const refs = shifts.map((shift, index) =>
    collection.doc(shift.id || buildShiftDocumentId(shift, index)),
  );
  const snapshots = refs.length > 0 ? await db.getAll(...refs) : [];
  const existingById = new Map(
    snapshots.map((snapshot) => [snapshot.id, snapshot]),
  );

  const batch = db.batch();
  const savedIds = [];
  for (let index = 0; index < shifts.length; index += 1) {
    const shift = shifts[index];
    const docRef = refs[index];
    const existing = existingById.get(docRef.id);
    savedIds.push(docRef.id);
    batch.set(
      docRef,
      {
        ...toFirestoreShift(shift, callerUid, existing),
        ...(existing?.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    );
  }

  await batch.commit();
  return savedIds;
}

// Genehmigte Abwesenheiten der betroffenen Nutzer im relevanten Zeitfenster.
// Nutzt den vorhandenen (userId, status, startDate)-Composite-Index und filtert
// userId+status serverseitig, statt die gesamte Org-Abwesenheitsliste zu laden
// und im Speicher zu filtern (absence-query-missing-status-index-filter).
// Firestore erlaubt max. 30 Werte pro "in"-Filter -> userIds chunken.
async function loadApprovedAbsencesInRange(orgId, userIds, maxEnd) {
  if (userIds.length === 0) {
    return [];
  }
  const collection = organizationCollection(orgId, "absenceRequests");
  const maxEndTs = Timestamp.fromDate(maxEnd);
  const chunks = [];
  for (let i = 0; i < userIds.length; i += 30) {
    chunks.push(userIds.slice(i, i + 30));
  }
  const snaps = await Promise.all(
    chunks.map((chunk) =>
      collection
        .where("userId", "in", chunk)
        .where("status", "==", "approved")
        .where("startDate", "<=", maxEndTs)
        .get(),
    ),
  );
  const seen = new Set();
  const absences = [];
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) {
        continue;
      }
      seen.add(doc.id);
      absences.push(fromFirestoreAbsence(doc));
    }
  }
  return absences;
}

async function loadShiftValidationContext(orgId, shifts) {
  const userIds = [...new Set(shifts.map((shift) => shift.userId).filter(Boolean))];
  const minStart = new Date(
    Math.min(...shifts.map((shift) => shift.startTime.getTime())) - 24 * 60 * 60 * 1000,
  );
  const maxEnd = new Date(
    Math.max(...shifts.map((shift) => shift.endTime.getTime())) + 24 * 60 * 60 * 1000,
  );

  const [
    shiftsSnap,
    absences,
    contractsSnap,
    assignmentsSnap,
    rulesSnap,
    travelRulesSnap,
    membersSnap,
  ] = await Promise.all([
    organizationCollection(orgId, "shifts")
      .where("startTime", ">=", Timestamp.fromDate(minStart))
      .where("startTime", "<", Timestamp.fromDate(maxEnd))
      .orderBy("startTime")
      .get(),
    loadApprovedAbsencesInRange(orgId, userIds, maxEnd),
    organizationCollection(orgId, "employmentContracts").get(),
    organizationCollection(orgId, "employeeSiteAssignments").get(),
    organizationCollection(orgId, "ruleSets").get(),
    organizationCollection(orgId, "travelTimeRules").get(),
    db.collection("users").where("orgId", "==", orgId).get(),
  ]);

  return {
    existingShifts: shiftsSnap.docs
      .map(fromFirestoreShift)
      .filter((shift) => userIds.includes(shift.userId)),
    absences,
    contracts: contractsSnap.docs.map(fromFirestoreContract),
    siteAssignments: assignmentsSnap.docs.map(fromFirestoreSiteAssignment),
    ruleSets: rulesSnap.docs.map(fromFirestoreRuleSet),
    travelTimeRules: travelRulesSnap.docs.map(fromFirestoreTravelTimeRule),
    members: membersSnap.docs
      .map(fromFirestoreMember)
      .filter((member) => userIds.includes(member.uid)),
  };
}

async function validateWorkEntry({callerUid, entry}) {
  // Fenster = ganzer Monat mit 1-Tag-Polster an beiden Raendern. Das deckt die
  // monatliche Minijob-Aggregation und die Ruhezeit-Luecken zu Eintraegen am
  // Vor-/Folgetag (auch ueber Monatsgrenzen) ab. Tages-/Monatsfilter in
  // validateSingleWorkEntry schraenken die Kandidaten je Regel wieder ein.
  const monthStart = new Date(
    entry.startTime.getFullYear(),
    entry.startTime.getMonth(),
    1,
  );
  const monthEndExclusive = new Date(
    entry.startTime.getFullYear(),
    entry.startTime.getMonth() + 1,
    1,
  );
  const windowStart = new Date(
    monthStart.getFullYear(),
    monthStart.getMonth(),
    monthStart.getDate() - 1,
  );
  const windowEndExclusive = new Date(
    monthEndExclusive.getFullYear(),
    monthEndExclusive.getMonth(),
    monthEndExclusive.getDate() + 1,
  );

  const collection = organizationCollection(entry.orgId, "workEntries");
  const existingRef = entry.id ? collection.doc(entry.id) : null;
  const [
    entriesSnap,
    contractsSnap,
    assignmentsSnap,
    rulesSnap,
    travelRulesSnap,
    memberSnapshot,
    existingSnapshot,
  ] = await Promise.all([
    collection
      .where("userId", "==", entry.userId)
      .where("startTime", ">=", Timestamp.fromDate(windowStart))
      .where("startTime", "<", Timestamp.fromDate(windowEndExclusive))
      .orderBy("startTime")
      .get(),
    organizationCollection(entry.orgId, "employmentContracts").get(),
    organizationCollection(entry.orgId, "employeeSiteAssignments").get(),
    organizationCollection(entry.orgId, "ruleSets").get(),
    organizationCollection(entry.orgId, "travelTimeRules").get(),
    db.collection("users").doc(entry.userId).get(),
    existingRef ? existingRef.get() : Promise.resolve(null),
  ]);

  const existingEntries = entriesSnap.docs.map(fromFirestoreWorkEntry);
  const contracts = contractsSnap.docs.map(fromFirestoreContract);
  const siteAssignments = assignmentsSnap.docs.map(fromFirestoreSiteAssignment);
  const ruleSets = rulesSnap.docs.map(fromFirestoreRuleSet);
  const travelTimeRules = travelRulesSnap.docs.map(fromFirestoreTravelTimeRule);
  const member = memberSnapshot.exists ? fromFirestoreMember(memberSnapshot) : null;
  const violations = validateSingleWorkEntry({
    entry,
    existingEntries,
    contracts,
    siteAssignments,
    ruleSets,
    travelTimeRules,
    member,
  });

  if (
    existingSnapshot?.exists &&
    correctionReasonRequired(existingSnapshot.data() || {}, entry) &&
    !entry.correctionReason
  ) {
    violations.push({
      code: "correction_reason_required",
      severity: "blocking",
      message: "Aenderungen an bestehenden Zeiteintraegen erfordern eine Begruendung.",
      relatedEntityIds: [entry.id].filter(Boolean),
    });
  }

  return {
    savedId: entry.id || buildWorkEntryDocumentId(entry),
    correctedByUid: entry.correctionReason ? callerUid : null,
    violations,
  };
}

function validateSingleShift({
  shift,
  existingShifts,
  draftShifts,
  absences,
  contracts,
  siteAssignments,
  ruleSets,
  travelTimeRules,
  members,
}) {
  const violations = [];
  const contract = activeContract(contracts, shift.userId, shift.startTime);
  const member = members.find((item) => item.uid === shift.userId) || null;
  const workRuleSettings = effectiveWorkRuleSettings(member);
  const assignment = assignmentForShift(siteAssignments, shift);
  const ruleSet = resolveRuleSet(ruleSets, shift.siteId, contract);
  const durationMinutes = workedMinutesFromShift(shift);
  const sameUserExisting = existingShifts.filter(
    (candidate) => candidate.userId === shift.userId && candidate.id !== shift.id,
  );
  const sameUserDraft = draftShifts.filter(
    (candidate) =>
      candidate.userId === shift.userId && candidate.draftKey !== shift.draftKey,
  );

  if (!shift.isUnassigned && !shift.siteId) {
    violations.push(blockingViolation(
      "site_required",
      "Fuer geplante Schichten ist ein Standort Pflicht.",
    ));
  }

  if (!shift.isUnassigned && !assignment) {
    violations.push({
      code: "site_assignment_missing",
      severity: "blocking",
      message: `${shift.employeeName} ist dem gewaehlten Standort nicht zugeordnet.`,
      relatedEntityIds: [shift.userId, shift.siteId].filter(Boolean),
    });
  }

  if (!shift.isUnassigned && shift.requiredQualificationIds.length > 0 && assignment) {
    const missing = shift.requiredQualificationIds.filter(
      (id) => !assignment.qualificationIds.includes(id),
    );
    if (missing.length > 0) {
      violations.push({
        code: "missing_qualification",
        severity: "blocking",
        message: `${shift.employeeName} erfuellt nicht alle erforderlichen Qualifikationen.`,
        relatedEntityIds: missing,
      });
    }
  }

  const conflictingExisting = sameUserExisting.filter((candidate) =>
    overlapsShift(candidate, shift),
  );
  if (conflictingExisting.length > 0) {
    violations.push({
      code: "overlap_existing",
      severity: "blocking",
      message: `Ueberschneidung mit bestehender Schicht am ${formatDateTime(conflictingExisting[0].startTime)}.`,
      relatedEntityIds: conflictingExisting.map((entry) => entry.id).filter(Boolean),
    });
  }

  const conflictingDraft = sameUserDraft.filter((candidate) =>
    overlapsShift(candidate, shift),
  );
  if (conflictingDraft.length > 0) {
    violations.push({
      code: "overlap_draft",
      severity: "blocking",
      message: "Ueberschneidung mit weiterer neuer Schicht im Paket.",
      relatedEntityIds: conflictingDraft.map((entry) => entry.id || entry.draftKey),
    });
  }

  const approvedAbsences = absences.filter(
    (absence) =>
      absence.userId === shift.userId &&
      absence.status === "approved" &&
      overlapsAbsence(absence, shift.startTime, shift.endTime),
  );
  if (approvedAbsences.length > 0) {
    violations.push({
      code: "absence_conflict",
      severity: "blocking",
      message: `Genehmigte Abwesenheit (${absenceTypeLabel(approvedAbsences[0].type)}) ueberschneidet diese Schicht.`,
      relatedEntityIds: approvedAbsences.map((entry) => entry.id).filter(Boolean),
    });
  }

  const requiredBreakMinutes = getRequiredBreakMinutes(
    durationMinutes,
    ruleSet,
    workRuleSettings,
  );
  if (requiredBreakMinutes > Math.round(shift.breakMinutes)) {
    violations.push({
      code: "break_required",
      severity: "blocking",
      message: `Fuer ${formatHours(durationMinutes)} Arbeitszeit sind mindestens ${requiredBreakMinutes} Minuten Pause erforderlich.`,
      relatedEntityIds: [],
    });
  }

  const shiftsSameDay = [...sameUserExisting, ...sameUserDraft].filter((candidate) =>
    isSameDay(candidate.startTime, shift.startTime),
  );
  const plannedDayMinutes = shiftsSameDay.reduce(
    (sum, candidate) => sum + workedMinutesFromShift(candidate),
    durationMinutes,
  );
  const maxDailyMinutes = maxDailyMinutesFor(contract, ruleSet);
  if (workRuleSettings.enforceMaxDailyMinutes &&
    plannedDayMinutes > maxDailyMinutes) {
    violations.push({
      code: "daily_limit",
      severity: "blocking",
      message: `Mit dieser Schicht wuerde ${shift.employeeName} ${formatHours(plannedDayMinutes)} an einem Tag erreichen. Erlaubt sind ${formatHours(maxDailyMinutes)}.`,
      relatedEntityIds: [],
    });
  } else if (workRuleSettings.warnDailyAverageExceeded &&
    plannedDayMinutes > 8 * 60) {
    violations.push(warningViolation(
      "daily_average_warning",
      "Die Tagesarbeitszeit liegt ueber 8 Stunden und sollte im Ausgleichszeitraum beobachtet werden.",
    ));
  }

  violations.push(
    ...restViolations({
      shift,
      candidateShifts: [...sameUserExisting, ...sameUserDraft],
      ruleSet,
      travelTimeRules,
      siteAssignments,
      contract,
      workRuleSettings,
    }),
  );

  if (workRuleSettings.enforceMinijobLimit &&
    contract?.type === "mini_job" &&
    Number(contract.hourlyRate || 0) > 0) {
    const monthlyMinutes = [...sameUserExisting, ...sameUserDraft]
      .filter(
        (candidate) =>
          candidate.startTime.getFullYear() === shift.startTime.getFullYear() &&
          candidate.startTime.getMonth() === shift.startTime.getMonth(),
      )
      .reduce((sum, candidate) => sum + workedMinutesFromShift(candidate), durationMinutes);
    const projectedCents = Math.round((monthlyMinutes / 60) * contract.hourlyRate * 100);
    const monthlyLimit = contract.monthlyIncomeLimitCents || ruleSet.minijobMonthlyLimitCents;
    if (projectedCents > monthlyLimit) {
      violations.push({
        code: "minijob_limit",
        severity: "blocking",
        message: `Die geplanten Stunden wuerden die Minijob-Grenze von ${(monthlyLimit / 100).toFixed(0)} EUR ueberschreiten.`,
        relatedEntityIds: [],
      });
    }
  }

  if (contract?.isMinor === true) {
    if (overlapsRestrictedMinorNightWindow(shift)) {
      violations.push(blockingViolation(
        "minor_night_work",
        "Jugendliche duerfen in diesem Zeitfenster nicht eingeplant werden.",
      ));
    }
    if (plannedDayMinutes > 8 * 60) {
      violations.push(blockingViolation(
        "minor_daily_limit",
        "Jugendliche duerfen maximal 8 Stunden pro Tag arbeiten.",
      ));
    }
  }

  if (contract?.isPregnant === true) {
    if (overlapsPregnancyNightWindow(shift)) {
      violations.push(blockingViolation(
        "pregnancy_night_work",
        "Nachtschichten sind fuer diesen Vertrag nicht zulaessig.",
      ));
    }
    if (plannedDayMinutes > 510) {
      violations.push(blockingViolation(
        "pregnancy_daily_limit",
        "Fuer diesen Vertrag gilt eine Tagesgrenze von 8,5 Stunden.",
      ));
    }
  }

  const previousShift = [...sameUserExisting, ...sameUserDraft]
    .filter((candidate) => candidate.endTime < shift.startTime)
    .sort((left, right) => right.endTime - left.endTime)[0];
  if (previousShift &&
    ruleSet.warnForwardRotation &&
    workRuleSettings.warnForwardRotation) {
    const previousBucket = shiftBucket(previousShift.startTime);
    const currentBucket = shiftBucket(shift.startTime);
    if (currentBucket < previousBucket) {
      violations.push(warningViolation(
        "forward_rotation_warning",
        "Die Abfolge der Schichtarten ist rueckwaerts rotiert. Vorwaertsrotation ist ergonomischer.",
      ));
    }
  }

  if (workRuleSettings.warnOvertime &&
    contract &&
    Number(contract.dailyHours || 0) > 0) {
    const targetMinutes = Math.round(contract.dailyHours * 60);
    if (plannedDayMinutes > targetMinutes) {
      violations.push(warningViolation(
        "overtime_warning",
        `Die Schicht fuehrt voraussichtlich zu Ueberstunden gegenueber ${Number(contract.dailyHours).toFixed(1)} Sollstunden.`,
      ));
    }
  }

  if (workRuleSettings.warnSundayWork && shift.startTime.getDay() === 0) {
    violations.push(warningViolation(
      "sunday_work_warning",
      "Sonntagsarbeit erfordert Ersatzruhetage und gesonderte Pruefung.",
    ));
  }

  if (!member && !shift.isUnassigned) {
    violations.push(warningViolation(
      "member_missing",
      "Das Mitarbeiterprofil konnte fuer die Regelpruefung nicht vollstaendig geladen werden.",
    ));
  }

  return dedupeViolations(violations);
}

// Vollständiger Spiegel von validateWorkEntry in compliance_service.dart.
// Frueher pruefte der Server nur site_required/site_assignment_missing/
// break_required/daily_limit — Ruhezeit, Minijob-, Jugend- und Mutterschutz
// sowie Ueberschneidungen wurden NICHT durchgesetzt (probleme/compliance.md #1).
function validateSingleWorkEntry({
  entry,
  existingEntries,
  contracts,
  siteAssignments,
  ruleSets,
  travelTimeRules,
  member,
}) {
  const violations = [];
  const contract = activeContract(contracts, entry.userId, entry.startTime);
  const workRuleSettings = effectiveWorkRuleSettings(member);
  const ruleSet = resolveRuleSet(ruleSets, entry.siteId, contract);
  const assignment = siteAssignments.find(
    (item) => item.userId === entry.userId && item.siteId === entry.siteId,
  );
  const sameUserEntries = existingEntries.filter(
    (candidate) => candidate.id !== entry.id,
  );

  if (!(entry.endTime > entry.startTime)) {
    violations.push(blockingViolation(
      "invalid_range",
      "Das Ende muss nach dem Start liegen.",
    ));
  }

  if (!entry.siteId) {
    violations.push(blockingViolation(
      "site_required",
      "Zeiteintraege muessen einem Standort zugeordnet sein.",
    ));
  }

  if (!assignment && entry.siteId) {
    violations.push(blockingViolation(
      "site_assignment_missing",
      "Der Mitarbeiter ist dem gewaehlten Standort nicht zugeordnet.",
    ));
  }

  const overlappingEntries = sameUserEntries.filter(
    (candidate) =>
      candidate.startTime < entry.endTime && candidate.endTime > entry.startTime,
  );
  if (overlappingEntries.length > 0) {
    violations.push({
      code: "overlap_existing",
      severity: "blocking",
      message: `Dieser Eintrag ueberschneidet sich mit einem bestehenden Zeiteintrag am ${formatDateTime(overlappingEntries[0].startTime)}.`,
      relatedEntityIds: overlappingEntries.map((item) => item.id).filter(Boolean),
    });
  }

  const workedMinutes = workedMinutesFromEntry(entry);
  const requiredBreakMinutes = getRequiredBreakMinutes(
    workedMinutes,
    ruleSet,
    workRuleSettings,
  );
  if (requiredBreakMinutes > Math.round(entry.breakMinutes)) {
    violations.push({
      code: "break_required",
      severity: "blocking",
      message: `Fuer ${formatHours(workedMinutes)} Arbeitszeit sind mindestens ${requiredBreakMinutes} Minuten Pause erforderlich.`,
      relatedEntityIds: [],
    });
  }

  const sameDayMinutes = sameUserEntries
    .filter((candidate) => isSameDay(candidate.startTime, entry.startTime))
    .reduce((sum, candidate) => sum + workedMinutesFromEntry(candidate), workedMinutes);
  const maxDailyMinutes = maxDailyMinutesFor(contract, ruleSet);
  if (workRuleSettings.enforceMaxDailyMinutes &&
    sameDayMinutes > maxDailyMinutes) {
    violations.push({
      code: "daily_limit",
      severity: "blocking",
      message: `Mit diesem Eintrag wird die Tagesgrenze von ${formatHours(maxDailyMinutes)} ueberschritten.`,
      relatedEntityIds: [],
    });
  } else if (workRuleSettings.warnDailyAverageExceeded &&
    sameDayMinutes > 8 * 60) {
    violations.push(warningViolation(
      "daily_average_warning",
      "Die Tagesarbeitszeit liegt ueber 8 Stunden und sollte im Ausgleichszeitraum beobachtet werden.",
    ));
  }

  if (workRuleSettings.enforceMinRestTime) {
    const previous = sameUserEntries
      .filter((candidate) => candidate.endTime < entry.startTime)
      .sort((left, right) => right.endTime - left.endTime)[0];
    if (previous &&
      shouldEnforceRestGap(previous.startTime, previous.endTime, entry.startTime)) {
      violations.push(
        ...singleRestGapViolations({
          earlier: previous,
          later: entry,
          ruleSet,
          travelTimeRules,
          siteAssignments,
          contract,
        }),
      );
    }
    const next = sameUserEntries
      .filter((candidate) => candidate.startTime > entry.endTime)
      .sort((left, right) => left.startTime - right.startTime)[0];
    if (next &&
      shouldEnforceRestGap(entry.startTime, entry.endTime, next.startTime)) {
      violations.push(
        ...singleRestGapViolations({
          earlier: entry,
          later: next,
          ruleSet,
          travelTimeRules,
          siteAssignments,
          contract,
        }),
      );
    }
  }

  if (workRuleSettings.enforceMinijobLimit &&
    contract?.type === "mini_job" &&
    Number(contract.hourlyRate || 0) > 0) {
    const monthlyMinutes = sameUserEntries
      .filter(
        (candidate) =>
          candidate.startTime.getFullYear() === entry.startTime.getFullYear() &&
          candidate.startTime.getMonth() === entry.startTime.getMonth(),
      )
      .reduce((sum, candidate) => sum + workedMinutesFromEntry(candidate), workedMinutes);
    const projectedCents = Math.round((monthlyMinutes / 60) * contract.hourlyRate * 100);
    const monthlyLimit = contract.monthlyIncomeLimitCents || ruleSet.minijobMonthlyLimitCents;
    if (projectedCents > monthlyLimit) {
      violations.push({
        code: "minijob_limit",
        severity: "blocking",
        message: `Die erfassten Stunden wuerden die Minijob-Grenze von ${(monthlyLimit / 100).toFixed(0)} EUR ueberschreiten.`,
        relatedEntityIds: [],
      });
    }
  }

  if (contract?.isMinor === true) {
    if (overlapsRestrictedMinorNightWindow(entry)) {
      violations.push(blockingViolation(
        "minor_night_work",
        "Jugendliche duerfen in diesem Zeitfenster nicht arbeiten.",
      ));
    }
    if (sameDayMinutes > 8 * 60) {
      violations.push(blockingViolation(
        "minor_daily_limit",
        "Jugendliche duerfen maximal 8 Stunden pro Tag arbeiten.",
      ));
    }
  }

  if (contract?.isPregnant === true) {
    if (overlapsPregnancyNightWindow(entry)) {
      violations.push(blockingViolation(
        "pregnancy_night_work",
        "Nachtschichten sind fuer diesen Vertrag nicht zulaessig.",
      ));
    }
    if (sameDayMinutes > 510) {
      violations.push(blockingViolation(
        "pregnancy_daily_limit",
        "Fuer diesen Vertrag gilt eine Tagesgrenze von 8,5 Stunden.",
      ));
    }
  }

  if (workRuleSettings.warnOvertime &&
    contract &&
    Number(contract.dailyHours || 0) > 0) {
    const targetMinutes = Math.round(contract.dailyHours * 60);
    if (sameDayMinutes > targetMinutes) {
      violations.push(warningViolation(
        "overtime_warning",
        `Der Eintrag fuehrt voraussichtlich zu Ueberstunden gegenueber ${Number(contract.dailyHours).toFixed(1)} Sollstunden.`,
      ));
    }
  }

  return dedupeViolations(violations);
}

function restViolations({
  shift,
  candidateShifts,
  ruleSet,
  travelTimeRules,
  siteAssignments,
  contract,
  workRuleSettings,
}) {
  if (!workRuleSettings?.enforceMinRestTime) {
    return [];
  }
  const violations = [];
  const sortedCandidates = [...candidateShifts].sort(
    (left, right) => left.startTime - right.startTime,
  );
  const previous = [...sortedCandidates]
    .filter((candidate) => candidate.endTime < shift.startTime)
    .sort((left, right) => right.endTime - left.endTime)[0];
  const next = [...sortedCandidates]
    .filter((candidate) => candidate.startTime > shift.endTime)
    .sort((left, right) => left.startTime - right.startTime)[0];

  if (previous) {
    violations.push(
      ...singleRestGapViolations({
        earlier: previous,
        later: shift,
        ruleSet,
        travelTimeRules,
        siteAssignments,
        contract,
      }),
    );
  }
  if (next) {
    violations.push(
      ...singleRestGapViolations({
        earlier: shift,
        later: next,
        ruleSet,
        travelTimeRules,
        siteAssignments,
        contract,
      }),
    );
  }
  return violations;
}

function singleRestGapViolations({
  earlier,
  later,
  ruleSet,
  travelTimeRules,
  siteAssignments,
  contract,
}) {
  const violations = [];
  const gapMinutes = Math.round((later.startTime - earlier.endTime) / 60000);
  const earlierSiteId = effectiveSiteId(earlier, siteAssignments);
  const laterSiteId = effectiveSiteId(later, siteAssignments);
  const travelRule = findTravelRule(travelTimeRules, earlierSiteId, laterSiteId);
  const minRestMinutes = contract?.isMinor === true ? 12 * 60 : ruleSet.minRestMinutes;

  if (earlierSiteId && laterSiteId && earlierSiteId !== laterSiteId && !travelRule) {
    violations.push(warningViolation(
      "travel_time_missing",
      "Zwischen diesen Standorten fehlt eine gepflegte Fahrtzeitregel.",
    ));
  }

  const effectiveGap = gapMinutes -
    (travelRule?.countsAsWorkTime === true ? travelRule.travelMinutes : 0);
  if (effectiveGap < minRestMinutes) {
    violations.push({
      code: "rest_time",
      severity: "blocking",
      message: `Zwischen ${formatDateTime(earlier.endTime)} und ${formatDateTime(later.startTime)} liegen nur ${formatHours(effectiveGap)} Ruhezeit.`,
      relatedEntityIds: [earlier.id, later.id].filter(Boolean),
    });
  }

  return violations;
}

// Spiegelt _shouldEnforceRestGap in compliance_service.dart: Tagesruhe gilt
// zwischen Arbeitstagen. Zwei getrennte Eintraege am selben Kalendertag
// (z.B. Pause zum Mittag, danach wieder eingestempelt) werden NICHT als neue
// Ruhezeit gewertet — sonst blockierte ein normaler geteilter Dienst faelschlich.
function shouldEnforceRestGap(earlierStart, earlierEnd, laterStart) {
  if (!isSameDay(earlierEnd, laterStart)) {
    return true;
  }
  return !isSameDay(earlierStart, earlierEnd);
}

function activeContract(contracts, userId, at) {
  return contracts
    .filter((contract) => contract.userId === userId && isContractActiveOn(contract, at))
    .sort((left, right) => right.validFrom - left.validFrom)[0] || null;
}

function isContractActiveOn(contract, at) {
  const start = new Date(
    contract.validFrom.getFullYear(),
    contract.validFrom.getMonth(),
    contract.validFrom.getDate(),
  );
  if (at < start) {
    return false;
  }
  if (!contract.validUntil) {
    return true;
  }
  const inclusiveEnd = new Date(
    contract.validUntil.getFullYear(),
    contract.validUntil.getMonth(),
    contract.validUntil.getDate(),
    23,
    59,
    59,
  );
  return at <= inclusiveEnd;
}

function assignmentForShift(siteAssignments, shift) {
  if (shift.siteId) {
    return siteAssignments.find(
      (item) => item.userId === shift.userId && item.siteId === shift.siteId,
    ) || null;
  }
  if (shift.siteName) {
    const normalized = shift.siteName.trim().toLowerCase();
    return siteAssignments.find(
      (item) =>
        item.userId === shift.userId &&
        item.siteName.trim().toLowerCase() === normalized,
    ) || null;
  }
  return null;
}

function effectiveSiteId(shift, siteAssignments) {
  if (shift.siteId) {
    return shift.siteId;
  }
  return assignmentForShift(siteAssignments, shift)?.siteId || null;
}

function resolveRuleSet(ruleSets, siteId, contract) {
  return (
    ruleSets.find(
      (item) => item.siteId === siteId && item.employmentType === contract?.type,
    ) ||
    ruleSets.find((item) => item.siteId === siteId && item.employmentType == null) ||
    ruleSets.find(
      (item) => item.siteId == null && item.employmentType === contract?.type,
    ) ||
    ruleSets.find((item) => item.siteId == null) ||
    defaultRuleSet(contract?.orgId || "")
  );
}

function findTravelRule(travelTimeRules, fromSiteId, toSiteId) {
  if (!fromSiteId || !toSiteId) {
    return null;
  }
  return travelTimeRules.find(
    (item) =>
      (item.fromSiteId === fromSiteId && item.toSiteId === toSiteId) ||
      (item.fromSiteId === toSiteId && item.toSiteId === fromSiteId),
  ) || null;
}

function getRequiredBreakMinutes(
  workedMinutes,
  ruleSet,
  workRuleSettings = defaultWorkRuleSettings(),
) {
  let requiredBreak = 0;
  const rules = [...ruleSet.breakRules].sort(
    (left, right) => left.afterMinutes - right.afterMinutes,
  );
  for (const rule of rules) {
    if (!isBreakRuleEnabled(rule, workRuleSettings)) {
      continue;
    }
    if (workedMinutes > rule.afterMinutes) {
      requiredBreak = rule.requiredBreakMinutes;
    }
  }
  return requiredBreak;
}

function maxDailyMinutesFor(contract, ruleSet) {
  if (Number.isFinite(contract?.maxDailyMinutes) && contract.maxDailyMinutes > 0) {
    return contract.maxDailyMinutes;
  }
  return ruleSet.maxPlannedMinutesPerDay;
}

function overlapsShift(left, right) {
  if (left.isUnassigned || right.isUnassigned) {
    return false;
  }
  if (left.userId !== right.userId) {
    return false;
  }
  return left.startTime < right.endTime && left.endTime > right.startTime;
}

function overlapsAbsence(absence, rangeStart, rangeEnd) {
  const start = new Date(
    absence.startDate.getFullYear(),
    absence.startDate.getMonth(),
    absence.startDate.getDate(),
  );
  const endExclusive = new Date(
    absence.endDate.getFullYear(),
    absence.endDate.getMonth(),
    absence.endDate.getDate() + 1,
  );
  return start < rangeEnd && endExclusive > rangeStart;
}

function overlapsRestrictedMinorNightWindow(shift) {
  return overlapsNightWindow(shift.startTime, shift.endTime);
}

function overlapsPregnancyNightWindow(shift) {
  return overlapsNightWindow(shift.startTime, shift.endTime);
}

function defaultWorkRuleSettings() {
  return {
    enforceMinRestTime: true,
    enforceBreakAfterSixHours: true,
    enforceBreakAfterNineHours: true,
    enforceMaxDailyMinutes: true,
    enforceMinijobLimit: true,
    warnDailyAverageExceeded: true,
    warnForwardRotation: true,
    warnOvertime: true,
    warnSundayWork: true,
  };
}

function workRuleSettingsFromData(data) {
  const settings = valueFromEither(data, "workRuleSettings", "work_rule_settings");
  const defaults = defaultWorkRuleSettings();
  return {
    enforceMinRestTime: asBoolean(
      valueFromEither(settings, "enforceMinRestTime", "enforce_min_rest_time"),
      defaults.enforceMinRestTime,
    ),
    enforceBreakAfterSixHours: asBoolean(
      valueFromEither(
        settings,
        "enforceBreakAfterSixHours",
        "enforce_break_after_six_hours",
      ),
      defaults.enforceBreakAfterSixHours,
    ),
    enforceBreakAfterNineHours: asBoolean(
      valueFromEither(
        settings,
        "enforceBreakAfterNineHours",
        "enforce_break_after_nine_hours",
      ),
      defaults.enforceBreakAfterNineHours,
    ),
    enforceMaxDailyMinutes: asBoolean(
      valueFromEither(
        settings,
        "enforceMaxDailyMinutes",
        "enforce_max_daily_minutes",
      ),
      defaults.enforceMaxDailyMinutes,
    ),
    enforceMinijobLimit: asBoolean(
      valueFromEither(settings, "enforceMinijobLimit", "enforce_minijob_limit"),
      defaults.enforceMinijobLimit,
    ),
    warnDailyAverageExceeded: asBoolean(
      valueFromEither(
        settings,
        "warnDailyAverageExceeded",
        "warn_daily_average_exceeded",
      ),
      defaults.warnDailyAverageExceeded,
    ),
    warnForwardRotation: asBoolean(
      valueFromEither(settings, "warnForwardRotation", "warn_forward_rotation"),
      defaults.warnForwardRotation,
    ),
    warnOvertime: asBoolean(
      valueFromEither(settings, "warnOvertime", "warn_overtime"),
      defaults.warnOvertime,
    ),
    warnSundayWork: asBoolean(
      valueFromEither(settings, "warnSundayWork", "warn_sunday_work"),
      defaults.warnSundayWork,
    ),
  };
}

function effectiveWorkRuleSettings(member) {
  return member?.workRuleSettings || defaultWorkRuleSettings();
}

function isBreakRuleEnabled(rule, workRuleSettings) {
  if (rule.afterMinutes === 360) {
    return workRuleSettings.enforceBreakAfterSixHours;
  }
  if (rule.afterMinutes === 540) {
    return workRuleSettings.enforceBreakAfterNineHours;
  }
  return true;
}

function shiftBucket(startTime) {
  const hour = startTime.getHours();
  if (hour < 12) {
    return 0;
  }
  if (hour < 20) {
    return 1;
  }
  return 2;
}

function workedMinutesFromShift(shift) {
  return Math.round((shift.endTime - shift.startTime) / 60000 - Number(shift.breakMinutes || 0));
}

function workedMinutesFromEntry(entry) {
  return Math.max(
    0,
    Math.round((entry.endTime - entry.startTime) / 60000 - Number(entry.breakMinutes || 0)),
  );
}

function correctionReasonRequired(existingRaw, nextEntry) {
  const existing = fromFirestoreWorkEntry({
    id: nextEntry.id,
    data: () => existingRaw,
  });
  return existing.startTime.getTime() !== nextEntry.startTime.getTime() ||
    existing.endTime.getTime() !== nextEntry.endTime.getTime() ||
    Math.round(existing.breakMinutes || 0) !== Math.round(nextEntry.breakMinutes || 0) ||
    stringOrNull(existing.siteId) !== stringOrNull(nextEntry.siteId);
}

function dedupeViolations(violations) {
  const seen = new Set();
  return violations.filter((item) => {
    const key = `${item.code}|${item.severity}|${item.message}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function isSameDay(left, right) {
  return left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate();
}

function formatHours(minutes) {
  return `${(minutes / 60).toFixed(1)} h`;
}

function formatDateTime(value) {
  const day = String(value.getDate()).padStart(2, "0");
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const year = String(value.getFullYear()).padStart(4, "0");
  const hour = String(value.getHours()).padStart(2, "0");
  const minute = String(value.getMinutes()).padStart(2, "0");
  return `${day}.${month}.${year} ${hour}:${minute}`;
}

function parseShift(raw, index, fallbackOrgId) {
  const map = ensureObject(raw, "shift");
  const startTime = parseDate(requiredString(map.start_time, `shifts[${index}].start_time`));
  const endTime = parseDate(requiredString(map.end_time, `shifts[${index}].end_time`));
  if (endTime <= startTime) {
    throw new HttpsError(
      "invalid-argument",
      `Die Schicht ${index + 1} hat kein gueltiges Zeitfenster.`,
    );
  }

  const siteId = stringOrNull(map.site_id);
  const siteName = stringOrNull(map.site_name);
  return {
    draftKey: `draft-${index}`,
    id: stringOrNull(map.id),
    orgId: stringOrEmpty(map.org_id) || fallbackOrgId,
    userId: stringOrEmpty(map.user_id),
    employeeName: stringOrEmpty(map.employee_name),
    title: stringOrEmpty(map.title),
    startTime,
    endTime,
    breakMinutes: asNumber(map.break_minutes),
    teamId: stringOrNull(map.team_id),
    team: stringOrNull(map.team),
    siteId,
    siteName,
    location: stringOrNull(map.location),
    requiredQualificationIds: asStringArray(map.required_qualification_ids),
    notes: stringOrNull(map.notes),
    color: stringOrNull(map.color),
    swapRequestedByUid: stringOrNull(map.swap_requested_by_uid),
    swapStatus: stringOrNull(map.swap_status),
    seriesId: stringOrNull(map.series_id),
    recurrencePattern: stringOrEmpty(map.recurrence_pattern) || "none",
    status: stringOrEmpty(map.status) || "planned",
    createdByUid: stringOrNull(map.created_by_uid),
    isUnassigned: stringOrEmpty(map.user_id).trim().length === 0,
  };
}

// Spiegelt WorkEntryStatus.fromValue (lib/models/work_entry.dart): unbekannter
// oder leerer Wert fällt still auf "approved" (abwärtskompatibel).
function normalizeWorkEntryStatus(raw) {
  const value = stringOrEmpty(raw);
  return ["draft", "submitted", "approved", "rejected"].includes(value)
    ? value
    : "approved";
}

function parseWorkEntry(raw) {
  const map = ensureObject(raw, "entry");
  const startTime = parseDate(requiredString(map.start_time, "entry.start_time"));
  const endTime = parseDate(requiredString(map.end_time, "entry.end_time"));
  if (endTime <= startTime) {
    throw new HttpsError(
      "invalid-argument",
      "Der Zeiteintrag hat kein gueltiges Zeitfenster.",
    );
  }

  return {
    id: stringOrNull(map.id),
    orgId: requiredString(map.org_id, "entry.org_id"),
    userId: requiredString(map.user_id, "entry.user_id"),
    date: parseDate(requiredString(map.date, "entry.date")),
    startTime,
    endTime,
    breakMinutes: asNumber(map.break_minutes),
    siteId: stringOrNull(map.site_id),
    siteName: stringOrNull(map.site_name),
    sourceShiftId: stringOrNull(map.source_shift_id),
    correctionReason: stringOrNull(map.correction_reason),
    correctedByUid: stringOrNull(map.corrected_by_uid),
    correctedAt: parseNullableDate(map.corrected_at),
    note: stringOrNull(map.note),
    category: stringOrNull(map.category),
    status: normalizeWorkEntryStatus(map.status),
    approvedByUid: stringOrNull(map.approved_by_uid),
    approvedAt: parseNullableDate(map.approved_at),
    sourceClockEntryId: stringOrNull(map.source_clock_entry_id),
  };
}

function toFirestoreShift(shift, callerUid, existingSnapshot) {
  const existingData = existingSnapshot?.data?.() || null;
  return {
    orgId: shift.orgId,
    userId: shift.userId,
    employeeName: shift.employeeName,
    title: shift.title,
    startTime: Timestamp.fromDate(shift.startTime),
    endTime: Timestamp.fromDate(shift.endTime),
    breakMinutes: shift.breakMinutes,
    teamId: shift.teamId,
    team: shift.team,
    siteId: shift.siteId,
    siteName: shift.siteName,
    location: shift.location,
    requiredQualificationIds: shift.requiredQualificationIds,
    notes: shift.notes,
    color: shift.color,
    swapRequestedByUid: shift.swapRequestedByUid,
    swapStatus: shift.swapStatus,
    seriesId: shift.seriesId,
    recurrencePattern: shift.recurrencePattern,
    status: shift.status,
    createdByUid: shift.createdByUid || existingData?.createdByUid || callerUid,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function toFirestoreWorkEntry(entry, callerUid) {
  return {
    orgId: entry.orgId,
    userId: entry.userId,
    date: Timestamp.fromDate(normalizeDate(entry.date)),
    startTime: Timestamp.fromDate(entry.startTime),
    endTime: Timestamp.fromDate(entry.endTime),
    breakMinutes: entry.breakMinutes,
    siteId: entry.siteId,
    siteName: entry.siteName,
    sourceShiftId: entry.sourceShiftId,
    correctionReason: entry.correctionReason || null,
    correctedByUid: entry.correctionReason ? callerUid : entry.correctedByUid,
    correctedAt: entry.correctionReason
      ? FieldValue.serverTimestamp()
      : (entry.correctedAt ? Timestamp.fromDate(entry.correctedAt) : null),
    note: entry.note,
    category: entry.category,
    status: normalizeWorkEntryStatus(entry.status),
    approvedByUid: entry.approvedByUid || null,
    approvedAt: entry.approvedAt ? Timestamp.fromDate(entry.approvedAt) : null,
    sourceClockEntryId: entry.sourceClockEntryId || null,
    workedHours: workedMinutesFromEntry(entry) / 60,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function fromFirestoreShift(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    userId: stringOrEmpty(data.userId),
    employeeName: stringOrEmpty(data.employeeName),
    title: stringOrEmpty(data.title),
    startTime: toDate(data.startTime),
    endTime: toDate(data.endTime),
    breakMinutes: asNumber(data.breakMinutes),
    teamId: stringOrNull(data.teamId),
    team: stringOrNull(data.team),
    siteId: stringOrNull(data.siteId),
    siteName: stringOrNull(data.siteName),
    location: stringOrNull(data.location),
    requiredQualificationIds: asStringArray(data.requiredQualificationIds),
    notes: stringOrNull(data.notes),
    color: stringOrNull(data.color),
    swapRequestedByUid: stringOrNull(data.swapRequestedByUid),
    swapStatus: stringOrNull(data.swapStatus),
    seriesId: stringOrNull(data.seriesId),
    recurrencePattern: stringOrEmpty(data.recurrencePattern) || "none",
    status: stringOrEmpty(data.status) || "planned",
    createdByUid: stringOrNull(data.createdByUid),
    isUnassigned: stringOrEmpty(data.userId).trim().length === 0,
  };
}

function fromFirestoreAbsence(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    userId: stringOrEmpty(data.userId),
    employeeName: stringOrEmpty(data.employeeName),
    startDate: toDate(data.startDate),
    endDate: toDate(data.endDate),
    type: stringOrEmpty(data.type) || "vacation",
    status: stringOrEmpty(data.status) || "pending",
  };
}

function fromFirestoreContract(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    userId: stringOrEmpty(data.userId),
    label: stringOrNull(data.label),
    type: stringOrEmpty(data.type) || "full_time",
    validFrom: toDate(data.validFrom),
    validUntil: toNullableDate(data.validUntil),
    weeklyHours: asNumber(data.weeklyHours, 40),
    dailyHours: asNumber(data.dailyHours, 8),
    hourlyRate: asNumber(data.hourlyRate),
    currency: stringOrEmpty(data.currency) || "EUR",
    vacationDays: asInteger(data.vacationDays, 30),
    maxDailyMinutes: nullableInteger(data.maxDailyMinutes),
    monthlyIncomeLimitCents: nullableInteger(data.monthlyIncomeLimitCents),
    isMinor: Boolean(data.isMinor),
    isPregnant: Boolean(data.isPregnant),
  };
}

function fromFirestoreSiteAssignment(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    userId: stringOrEmpty(data.userId),
    siteId: stringOrEmpty(data.siteId),
    siteName: stringOrEmpty(data.siteName),
    role: stringOrNull(data.role),
    qualificationIds: asStringArray(data.qualificationIds),
    isPrimary: Boolean(data.isPrimary),
  };
}

function fromFirestoreRuleSet(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    name: stringOrEmpty(data.name),
    siteId: stringOrNull(data.siteId),
    employmentType: stringOrNull(data.employmentType),
    minRestMinutes: asInteger(data.minRestMinutes, 660),
    breakRules: asArray(data.breakRules).map((item) => ({
      afterMinutes: asInteger(item?.afterMinutes),
      requiredBreakMinutes: asInteger(item?.requiredBreakMinutes),
    })),
    maxPlannedMinutesPerDay: asInteger(data.maxPlannedMinutesPerDay, 600),
    minijobMonthlyLimitCents: asInteger(data.minijobMonthlyLimitCents, 60300),
    nightWindowStartMinutes: asInteger(data.nightWindowStartMinutes, 23 * 60),
    nightWindowEndMinutes: asInteger(data.nightWindowEndMinutes, 6 * 60),
    warnForwardRotation: data.warnForwardRotation !== false,
  };
}

function fromFirestoreTravelTimeRule(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    fromSiteId: stringOrEmpty(data.fromSiteId),
    toSiteId: stringOrEmpty(data.toSiteId),
    travelMinutes: asInteger(data.travelMinutes),
    countsAsWorkTime: data.countsAsWorkTime !== false,
  };
}

function fromFirestoreMember(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    uid: doc.id || stringOrNull(data.uid),
    orgId: stringFromEither(data, "orgId", "org_id"),
    role: normalizeRole(data.role),
    isActive: isTruthy(valueFromEither(data, "isActive", "is_active")),
    workRuleSettings: workRuleSettingsFromData(data),
  };
}

function fromFirestoreWorkEntry(doc) {
  const data = typeof doc.data === "function" ? doc.data() : doc;
  return {
    id: doc.id || stringOrNull(data.id),
    orgId: stringOrEmpty(data.orgId),
    userId: stringOrEmpty(data.userId),
    date: toDate(data.date),
    startTime: toDate(data.startTime),
    endTime: toDate(data.endTime),
    breakMinutes: asNumber(data.breakMinutes),
    siteId: stringOrNull(data.siteId),
    siteName: stringOrNull(data.siteName),
    sourceShiftId: stringOrNull(data.sourceShiftId),
    correctionReason: stringOrNull(data.correctionReason),
    correctedByUid: stringOrNull(data.correctedByUid),
    correctedAt: toNullableDate(data.correctedAt),
    note: stringOrNull(data.note),
    category: stringOrNull(data.category),
    status: normalizeWorkEntryStatus(data.status),
    approvedByUid: stringOrNull(data.approvedByUid),
    approvedAt: toNullableDate(data.approvedAt),
    sourceClockEntryId: stringOrNull(data.sourceClockEntryId),
  };
}

function organizationCollection(orgId, name) {
  return db.collection("organizations").doc(orgId).collection(name);
}

function buildShiftDocumentId(shift, index) {
  return `shift_${stableHash([
    shift.orgId,
    shift.userId,
    shift.employeeName,
    shift.title,
    shift.startTime.toISOString(),
    shift.endTime.toISOString(),
    String(shift.breakMinutes),
    shift.teamId || "",
    shift.siteId || "",
    shift.seriesId || "",
    shift.status || "",
    String(index),
  ])}`;
}

function buildWorkEntryDocumentId(entry) {
  return `entry_${stableHash([
    entry.orgId,
    entry.userId,
    entry.date.toISOString(),
    entry.startTime.toISOString(),
    entry.endTime.toISOString(),
    String(entry.breakMinutes),
    entry.siteId || "",
    entry.category || "",
  ])}`;
}

async function writeWorkEntryBatch({callerUid, entries}) {
  const collection = organizationCollection(entries[0].orgId, "workEntries");
  const refs = entries.map((entry) =>
    collection.doc(entry.id || buildWorkEntryDocumentId(entry)),
  );
  const snapshots = refs.length > 0 ? await db.getAll(...refs) : [];
  const existingById = new Map(
    snapshots.map((snapshot) => [snapshot.id, snapshot]),
  );

  const batch = db.batch();
  const savedIds = [];
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    const docRef = refs[index];
    const existing = existingById.get(docRef.id);
    savedIds.push(docRef.id);
    batch.set(
      docRef,
      {
        ...toFirestoreWorkEntry(entry, callerUid),
        ...(existing?.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    );
  }

  await batch.commit();
  return savedIds;
}

function stableHash(parts) {
  return crypto
    .createHash("sha1")
    .update(parts.join("|"))
    .digest("hex")
    .slice(0, 24);
}

function defaultRuleSet(orgId) {
  return {
    orgId,
    name: "DE Einzelhandel Standard",
    siteId: null,
    employmentType: null,
    minRestMinutes: 660,
    breakRules: [
      {afterMinutes: 360, requiredBreakMinutes: 30},
      {afterMinutes: 540, requiredBreakMinutes: 45},
    ],
    maxPlannedMinutesPerDay: 600,
    minijobMonthlyLimitCents: 60300,
    nightWindowStartMinutes: 23 * 60,
    nightWindowEndMinutes: 6 * 60,
    warnForwardRotation: true,
  };
}

function normalizeDate(value) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate(), 12);
}

function overlapsNightWindow(startTime, endTime) {
  return startTime.getHours() < 6 ||
    endTime.getHours() >= 20 ||
    !isSameDay(startTime, endTime);
}

function absenceTypeLabel(type) {
  switch (type) {
    case "sickness":
      return "Krank";
    case "unavailable":
      return "Nicht verfuegbar";
    default:
      return "Urlaub";
  }
}

function blockingViolation(code, message) {
  return {code, severity: "blocking", message, relatedEntityIds: []};
}

function warningViolation(code, message) {
  return {code, severity: "warning", message, relatedEntityIds: []};
}

function isBlockingViolation(violation) {
  return violation.severity === "blocking";
}

function ensureObject(value, fieldName) {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} muss ein Objekt sein.`,
    );
  }
  return value;
}

function requiredString(value, fieldName) {
  const normalized = stringOrEmpty(value).trim();
  if (!normalized) {
    throw new HttpsError(
      "invalid-argument",
      `${fieldName} ist erforderlich.`,
    );
  }
  return normalized;
}

function stringOrEmpty(value) {
  if (value == null) {
    return "";
  }
  return String(value);
}

function stringOrNull(value) {
  const normalized = stringOrEmpty(value).trim();
  return normalized ? normalized : null;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function asStringArray(value) {
  return asArray(value)
    .map((item) => stringOrEmpty(item).trim())
    .filter(Boolean);
}

function asNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function asInteger(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function nullableInteger(value) {
  if (value == null) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

function parseDate(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError(
      "invalid-argument",
      `Ungueltiges Datumsformat: ${value}`,
    );
  }
  return parsed;
}

function parseNullableDate(value) {
  if (value == null || `${value}`.trim().length === 0) {
    return null;
  }
  return parseDate(value);
}

function toDate(value) {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value?.toDate === "function") {
    return value.toDate();
  }
  if (typeof value === "string" && value.trim()) {
    return parseDate(value);
  }
  return new Date();
}

function toNullableDate(value) {
  if (value == null) {
    return null;
  }
  return toDate(value);
}

// ===========================================================================
// OktoPOS-Kassenanbindung — read-only Transaktions-Pull -> Bestandsabbuchung
// ---------------------------------------------------------------------------
// Sicherheit/Architektur:
//  - X-API-KEY ist ein Secret (Secret Manager OKTOPOS_API_KEYS), NIE im
//    Client. Der Aufruf gegen OktoPOS laeuft ausschliesslich serverseitig
//    (Server-zu-Server) -> kein CORS, kein Schluessel im Bundle.
//  - Bestandsbewegungen werden via Admin SDK geschrieben (umgeht die
//    Client-Rules). Die Rules erlauben Clients KEINE source=='oktopos'
//    -> keine gefaelschte Kassen-Provenienz vom Client.
//  - Idempotent: deterministische Doc-ID je (Kasse, Beleg, Position) ->
//    erneuter Lauf bucht NICHT doppelt (Transaktion + Existenz-Check).
//  - Nur LESEN aus OktoPOS; kein Schreibpfad in die Kasse.
//  - TLS-Pflicht: baseUrl muss https sein (Key nie im Klartext).
//
// Betrieb braucht den Blaze-Plan (ausgehende Netzwerk-Calls + Secret Manager
// + Scheduler) sowie das Config-Dokument organizations/{orgId}/config/
// oktoposSync mit baseUrl + sites[siteId].cashRegisterId. Siehe
// plan/oktopos-kassenanbindung.md.
// ===========================================================================

const OKTOPOS_SYNC_CONFIG_ID = "oktoposSync";
const OKTOPOS_FETCH_TIMEOUT_MS = 25000;
const OKTOPOS_MAX_PAGES = 200; // Cap gegen Endlos-Pagination
const OKTOPOS_DEFAULT_PAGE_SIZE = 50;
const OKTOPOS_DEFAULT_LOOKBACK_DAYS = 3;
// API10 (Fremddaten bounden): eingebettete Belegzeilen kappen, damit ein Beleg
// nie das Firestore-1-MiB-Doc-Limit reisst (Kiosk-Bons sind klein; mehr ist eine
// Anomalie). Ueberzaehlige Zeilen werden verworfen und im Beleg markiert.
const OKTOPOS_MAX_RECEIPT_LINES = 200;

// Manueller Kassenabgleich (Admin loest ihn pro Standort aus).
exports.syncOktoposTransactions = callable(
  "syncOktoposTransactions",
  // Hoeheres Timeout als der Default (60s): ein Pull ueber mehrere Seiten mit
  // je einer Bestands-Transaktion kann laenger dauern. Der Client wartet
  // entsprechend laenger (siehe FirestoreService.syncOktoposTransactions).
  {region: REGION, secrets: [OKTOPOS_API_KEYS], timeoutSeconds: 300,
    memory: "256MiB"},
  async (request, {requestId, fn}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    assertAdmin(caller);
    const orgId = requiredString(request.data?.orgId, "orgId");
    assertSameOrg(caller, orgId);
    const siteId = requiredString(request.data?.siteId, "siteId");

    const config = await loadOktoposConfig(orgId);
    if (!config || !stringOrNull(config.baseUrl)) {
      throw new HttpsError(
        "failed-precondition",
        "OktoPOS ist noch nicht eingerichtet (baseUrl fehlt im " +
          "Config-Dokument config/oktoposSync).",
      );
    }

    return runOktoposSync({
      orgId,
      siteId,
      config,
      apiKeysRaw: OKTOPOS_API_KEYS.value(),
      fromOverride: stringOrNull(request.data?.from),
      untilOverride: stringOrNull(request.data?.until),
      dryRun: request.data?.dryRun === true,
      fn,
      requestId,
    });
  },
);

// Naechtlicher autonomer Pull (opt-in: config.enabled === true je Org).
exports.oktoposNightlySync = onSchedule(
  {
    region: REGION,
    schedule: "every day 03:30",
    timeZone: "Europe/Berlin",
    secrets: [OKTOPOS_API_KEYS],
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const orgsSnap = await db.collection("organizations").limit(50).get();
    for (const orgDoc of orgsSnap.docs) {
      const orgId = orgDoc.id;
      let config;
      try {
        config = await loadOktoposConfig(orgId);
      } catch (error) {
        logger.error("oktopos_config_error", {
          event: "oktopos_config_error",
          fn: "oktoposNightlySync",
          orgId,
          error: truncateError(error),
        });
        continue;
      }
      if (!config || config.enabled !== true || !stringOrNull(config.baseUrl)) {
        continue;
      }
      const sites = isPlainObject(config.sites) ? config.sites : {};
      for (const siteId of Object.keys(sites)) {
        // Eine Request-ID je Standort-Lauf, damit alle Logzeilen (HTTP-Calls,
        // Abschluss/Fehler) dieses Laufs korrelierbar sind. Die Erfolgs-Summary
        // loggt runOktoposSync selbst (oktopos_sync_done).
        const requestId = crypto.randomUUID();
        try {
          await runOktoposSync({
            orgId,
            siteId,
            config,
            apiKeysRaw: OKTOPOS_API_KEYS.value(),
            fn: "oktoposNightlySync",
            requestId,
          });
        } catch (error) {
          logger.error("oktopos_sync_error", {
            event: "oktopos_sync_error",
            fn: "oktoposNightlySync",
            requestId,
            orgId,
            siteId,
            error: truncateError(error),
          });
        }
      }
    }
  },
);

async function loadOktoposConfig(orgId) {
  const snap = await organizationCollection(orgId, "config")
    .doc(OKTOPOS_SYNC_CONFIG_ID)
    .get();
  return snap.exists ? (snap.data() || null) : null;
}

function assertAdmin(caller) {
  if (!caller.isAdmin) {
    throw new HttpsError(
      "permission-denied",
      "Nur Administratoren duerfen den Kassenabgleich ausloesen.",
    );
  }
}

// Key-Aufloesung: JSON {"<siteId>":"<key>"} ODER einzelner Key-String.
function resolveOktoposApiKey(apiKeysRaw, siteId) {
  const raw = stringOrEmpty(apiKeysRaw).trim();
  if (!raw) {
    throw new HttpsError(
      "failed-precondition",
      "Kein OktoPOS-API-Key hinterlegt (Secret OKTOPOS_API_KEYS).",
    );
  }
  if (raw.startsWith("{")) {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      throw new HttpsError(
        "failed-precondition",
        "OKTOPOS_API_KEYS ist kein gueltiges JSON.",
      );
    }
    const key = parsed?.[siteId] || parsed?.["*"] || parsed?.default;
    if (!stringOrNull(key)) {
      throw new HttpsError(
        "failed-precondition",
        `Kein OktoPOS-API-Key fuer Standort ${siteId} in OKTOPOS_API_KEYS.`,
      );
    }
    return String(key).trim();
  }
  return raw;
}

async function runOktoposSync({
  orgId, siteId, config, apiKeysRaw,
  fromOverride = null, untilOverride = null, dryRun = false,
  fn = "runOktoposSync", requestId = null,
}) {
  const baseUrl = stringOrEmpty(config.baseUrl).trim().replace(/\/+$/, "");
  // TLS-Pflicht: der API-Key darf nie im Klartext ueber http gehen.
  if (!baseUrl.toLowerCase().startsWith("https://")) {
    throw new HttpsError(
      "failed-precondition", "OktoPOS baseUrl muss https sein.",
    );
  }
  const apiKey = resolveOktoposApiKey(apiKeysRaw, siteId);
  const siteConfig = isPlainObject(config.sites?.[siteId])
    ? config.sites[siteId]
    : {};
  const rawCr = Number(siteConfig.cashRegisterId);
  const cashRegisterId = Number.isFinite(rawCr) && rawCr > 0
    ? Math.trunc(rawCr)
    : null;
  // Schutz gegen Doppelbuchung: teilen sich mehrere Laeden einen API-Key und
  // ist keine Kassen-Nr. gesetzt, wuerde JEDER Lauf ALLE Verkaufsbuchungen
  // ziehen und gegen die Produkte SEINES Standorts matchen -> ein Verkauf wird
  // in beiden Laeden abgebucht. Bei mehreren konfigurierten Laeden ist die
  // Kassen-Nr. daher Pflicht (manuell: Fehler; naechtlich: per try/catch geloggt).
  const siteCount = isPlainObject(config.sites)
    ? Object.keys(config.sites).length
    : 0;
  if (cashRegisterId == null && siteCount > 1) {
    throw new HttpsError(
      "failed-precondition",
      "Bei mehreren Laeden muss je Laden eine Kassen-Nr. gesetzt sein, " +
        "sonst werden Verkaeufe doppelt gebucht.",
    );
  }
  const pageSize = asInteger(config.defaultSize, OKTOPOS_DEFAULT_PAGE_SIZE) ||
    OKTOPOS_DEFAULT_PAGE_SIZE;

  // Zeitfenster (Cursor = letzter synchronisierter Geschaeftstag).
  const until = parseOktoposDate(untilOverride) || new Date();
  let from = parseOktoposDate(fromOverride);
  if (!from) {
    const cursor = parseOktoposDate(stringOrNull(siteConfig.lastBusinessDay));
    from = cursor || daysAgo(until, OKTOPOS_DEFAULT_LOOKBACK_DAYS);
  }
  const fromIso = toOktoposDateTime(from);
  const untilIso = toOktoposDateTime(until);

  const lookups = await loadProductLookups(orgId, siteId);

  const result = {
    siteId,
    fromUsed: fromIso,
    untilUsed: untilIso,
    cashRegisterId,
    pages: 0,
    processedTransactions: 0,
    appliedMovements: 0,
    reversedMovements: 0,
    receiptsCollected: 0,
    receiptsPersisted: 0,
    skippedTraining: 0,
    skippedNonSales: 0,
    skippedNoReference: 0,
    unmatchedLineItems: 0,
    unmatchedSamples: [],
    dryRun,
  };

  let maxBusinessDay = stringOrNull(siteConfig.lastBusinessDay);
  let page = 1;
  let lastPage = 1;
  do {
    const wrappers = await fetchOktoposTransactionsPage({
      baseUrl, apiKey, fromIso, untilIso, page, size: pageSize, cashRegisterId,
      fn, requestId,
    });
    result.pages += 1;
    let pageLastPage = page;
    const pending = [];
    const pendingReceipts = [];
    for (const wrapper of wrappers) {
      pageLastPage = Math.max(pageLastPage, asInteger(wrapper.lastPage, page));
      for (const tx of asArray(wrapper.transactions)) {
        result.processedTransactions += 1;
        const training = tx?.training === true;
        const type = stringOrEmpty(tx?.type).trim().toLowerCase();
        // sales bucht ab (-), refund bucht zurueck (+); cash/sonstiges bewegt
        // KEINEN Bestand. cash- und training-Belege werden trotzdem als
        // Verkaufsfaktum (posReceipts, P0) gesichert: Kassendifferenz/
        // Tagesabschluss brauchen cash, Aggregate schliessen training/cash
        // ueber die Flags `training`/`isRevenue` aus.
        const sign = type === "sales" ? -1 : (type === "refund" ? 1 : 0);
        const ref = stringOrNull(tx?.referenceNumber);
        if (!ref) {
          // Ohne Belegnummer gibt es keinen stabilen Idempotenz-Schluessel ->
          // weder buchen NOCH als Beleg-Faktum schreiben (Doc-ID waere nicht
          // deterministisch). Bei echten fiskalischen Belegen Pflichtfeld.
          result.skippedNoReference += 1;
          continue;
        }
        const businessDay = stringOrNull(tx?.businessDay);
        if (businessDay && (!maxBusinessDay || businessDay > maxBusinessDay)) {
          maxBusinessDay = businessDay;
        }
        const txDate = parseOktoposTxDate(tx);
        // Telemetrie unveraendert (training hat Vorrang vor cash).
        if (training) result.skippedTraining += 1;
        else if (sign === 0) result.skippedNonSales += 1;

        // (A) Verkaufsfaktum (P0): JEDEN Beleg mit Belegnummer denormalisiert
        // sichern (Zeilen mit Name/Kategorie/Preis ZUM VERKAUFSZEITPUNKT, damit
        // ein spaeter geloeschtes Produkt die Historie nicht verwaist).
        const isRevenue = !training && sign !== 0;
        const receiptLines = [];
        let truncatedLines = false;
        for (const item of asArray(tx?.items)) {
          if (receiptLines.length >= OKTOPOS_MAX_RECEIPT_LINES) {
            truncatedLines = true;
            break;
          }
          const matched = matchProduct(lookups, item?.product);
          receiptLines.push({
            productId: matched ? matched.id : null,
            name: stringOrNull(item?.product?.name),
            externalReference: stringOrNull(item?.product?.externalReference),
            scannedBarcode: stringOrNull(item?.product?.scannedBarcode),
            category: stringOrNull(item?.product?.group?.token) ||
              stringOrNull(item?.product?.category),
            quantity: asInteger(item?.quantity, 0),
            unitPriceCents: oktoposMoneyToCents(
              item?.price ?? item?.unitPrice ?? item?.singlePrice,
            ),
            discountCents: oktoposMoneyToCents(
              item?.discount ?? item?.discountAmount,
            ),
          });
        }
        if (!dryRun) {
          pendingReceipts.push({
            receiptId: buildOktoposReceiptId(cashRegisterId, siteId, ref),
            referenceNumber: ref,
            type: type || null,
            training,
            isRevenue,
            businessDay: businessDay || null,
            txDate,
            grossCents: oktoposMoneyToCents(
              tx?.grossAmount ?? tx?.gross ?? tx?.total ?? tx?.amount,
            ),
            taxes: parseOktoposReceiptTaxes(tx),
            payments: parseOktoposPayments(tx),
            lines: receiptLines,
            lineCount: receiptLines.length,
            truncatedLines,
            // PII-Minimierung: nur IDs sichern, Namen erst im UI aus dem Team-/
            // Kontaktbestand aufloesen (sofern OktoPOS sie liefert — gegen die
            // Swagger verifizieren, hier tolerant/optional).
            cashierId: stringOrNull(tx?.cashier?.id ?? tx?.cashierId),
            customerId: stringOrNull(tx?.customer?.id ?? tx?.customerId),
          });
        }
        result.receiptsCollected += 1;

        // (B) Bestandsbewegungen NUR fuer echte Umsatzbelege (sales/refund, kein
        // training, kein cash).
        if (!isRevenue) {
          continue;
        }
        for (const item of asArray(tx?.items)) {
          const quantity = Math.abs(asInteger(item?.quantity, 0));
          if (quantity <= 0) {
            continue;
          }
          const product = matchProduct(lookups, item?.product);
          if (!product) {
            result.unmatchedLineItems += 1;
            if (result.unmatchedSamples.length < 20) {
              result.unmatchedSamples.push({
                name: stringOrNull(item?.product?.name),
                barcode: stringOrNull(item?.product?.scannedBarcode),
                externalReference: stringOrNull(item?.product?.externalReference),
              });
            }
            continue;
          }
          const delta = sign * quantity;
          if (dryRun) {
            if (sign < 0) result.appliedMovements += 1;
            else result.reversedMovements += 1;
            continue;
          }
          pending.push({
            movementId: buildOktoposMovementId(
              cashRegisterId, ref, asInteger(item?.id, 0),
            ),
            productId: product.id,
            productName: product.name,
            delta,
            inFridge: product.inFridge === true,
            referenceNumber: ref,
            txDate,
          });
        }
      }
    }
    // Verkaufsfakten zuerst sichern (idempotentes set(merge)) — unabhaengig von
    // der Bestandsbuchung, damit ein Bewegungs-Fehler nicht die Belege verliert.
    if (!dryRun && pendingReceipts.length > 0) {
      result.receiptsPersisted += await applyOktoposReceiptsBatch(
        orgId, siteId, cashRegisterId, pendingReceipts,
      );
    }
    // Seitenweise GEBÜNDELT buchen statt einer Transaktion je Position:
    // 1 getAll (Idempotenz) + <=500-Writes-Batches mit FieldValue.increment.
    if (!dryRun && pending.length > 0) {
      const appliedIds = await applyOktoposMovementsBatch(orgId, siteId, pending);
      for (const p of pending) {
        if (appliedIds.has(p.movementId)) {
          if (p.delta < 0) result.appliedMovements += 1;
          else result.reversedMovements += 1;
        }
      }
    }
    lastPage = pageLastPage;
    page += 1;
  } while (page <= lastPage && page <= OKTOPOS_MAX_PAGES);

  // Cursor fortschreiben (nicht im dryRun).
  if (!dryRun && maxBusinessDay) {
    await organizationCollection(orgId, "config")
      .doc(OKTOPOS_SYNC_CONFIG_ID)
      .set({
        sites: {
          [siteId]: {
            lastBusinessDay: maxBusinessDay,
            lastSyncAt: FieldValue.serverTimestamp(),
          },
        },
      }, {merge: true});
  }

  // Abschluss-Summary — gilt fuer den MANUELLEN Lauf (vorher log-los) UND den
  // naechtlichen. Nur Aggregate, keine unmatchedSamples (koennen Produktnamen
  // enthalten).
  logger.info("oktopos_sync_done", {
    event: "oktopos_sync_done",
    fn,
    requestId,
    orgId,
    siteId,
    dryRun,
    pages: result.pages,
    processedTransactions: result.processedTransactions,
    applied: result.appliedMovements,
    reversed: result.reversedMovements,
    receiptsPersisted: result.receiptsPersisted,
    unmatched: result.unmatchedLineItems,
  });
  return result;
}

async function loadProductLookups(orgId, siteId) {
  const snap = await organizationCollection(orgId, "products")
    .where("siteId", "==", siteId)
    .get();
  const byBarcode = new Map();
  const byExternal = new Map();
  const bySku = new Map();
  const byId = new Map();
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const entry = {
      id: doc.id,
      name: stringOrNull(data.name),
      inFridge: isTruthy(data.inFridge),
    };
    byId.set(doc.id, entry);
    const barcode = stringOrNull(data.barcode);
    const external = stringOrNull(data.externalPosId);
    const sku = stringOrNull(data.sku);
    if (barcode) byBarcode.set(barcode, entry);
    if (external) byExternal.set(external, entry);
    if (sku) bySku.set(sku, entry);
  }
  return {byBarcode, byExternal, bySku, byId};
}

// Join-Reihenfolge: gescannter Barcode -> externalPosId -> SKU -> Produkt-ID.
// Die ID-Variante greift, wenn der Artikel via Push (externalReferenceNumber =
// product.id) in die Kasse geschrieben wurde.
function matchProduct(lookups, posProduct) {
  if (!posProduct) return null;
  const barcode = stringOrNull(posProduct.scannedBarcode);
  if (barcode && lookups.byBarcode.has(barcode)) {
    return lookups.byBarcode.get(barcode);
  }
  const external = stringOrNull(posProduct.externalReference);
  if (external && lookups.byExternal.has(external)) {
    return lookups.byExternal.get(external);
  }
  if (external && lookups.bySku.has(external)) {
    return lookups.bySku.get(external);
  }
  if (external && lookups.byId.has(external)) {
    return lookups.byId.get(external);
  }
  return null;
}

// Performanter Ersatz fuer die frueheren Einzel-Transaktionen: bucht eine ganze
// Seite gebuendelt. (1) Ein `getAll` filtert bereits gebuchte Bewegungen heraus
// (Idempotenz). (2) Pro Chunk (<=500 Writes) ein WriteBatch: je neue Bewegung
// `create` (scheitert bei Race -> atomarer Batch-Rollback statt Doppelbuchung),
// je betroffenem Produkt EIN `update` mit `FieldValue.increment` der Summe.
// Gibt die Menge der tatsaechlich neu gebuchten movementIds zurueck.
//
// Trade-off: `balanceAfter` wird fuer Kassen-Bewegungen nicht gesetzt (null),
// da der Bestand per increment fortgeschrieben wird (kein verlaesslicher
// Snapshot-Stand ohne Lesen; manuelle Buchungen tragen weiterhin balanceAfter).
async function applyOktoposMovementsBatch(orgId, siteId, pending) {
  if (pending.length === 0) {
    return new Set();
  }
  const movementsCol = organizationCollection(orgId, "stockMovements");
  const productsCol = organizationCollection(orgId, "products");

  // Innerhalb einer Seite nach movementId deduplizieren (defensiv).
  const byId = new Map();
  for (const p of pending) {
    if (!byId.has(p.movementId)) {
      byId.set(p.movementId, p);
    }
  }
  const items = [...byId.values()];

  // (1) Idempotenz: existierende Bewegungen herausfiltern (getAll, gechunkt).
  const existing = new Set();
  for (let i = 0; i < items.length; i += 300) {
    const refs = items.slice(i, i + 300).map((p) => movementsCol.doc(p.movementId));
    const snaps = await db.getAll(...refs);
    for (const snap of snaps) {
      if (snap.exists) {
        existing.add(snap.id);
      }
    }
  }
  const fresh = items.filter((p) => !existing.has(p.movementId));
  if (fresh.length === 0) {
    return new Set();
  }

  // (2) In Chunks batchen (je Bewegung 1 create + je Produkt 1 update <= 500).
  const applied = new Set();
  const CHUNK = 200;
  for (let i = 0; i < fresh.length; i += CHUNK) {
    const slice = fresh.slice(i, i + CHUNK);
    const deltaByProduct = new Map();
    const fridgeDeltaByProduct = new Map();
    for (const p of slice) {
      deltaByProduct.set(
        p.productId, (deltaByProduct.get(p.productId) || 0) + p.delta,
      );
      // Kuehlschrank-Artikel: derselbe Verkauf leert auch den Kuehlschrank-Ist.
      if (p.inFridge) {
        fridgeDeltaByProduct.set(
          p.productId, (fridgeDeltaByProduct.get(p.productId) || 0) + p.delta,
        );
      }
    }
    const batch = db.batch();
    for (const p of slice) {
      const reason = p.delta < 0
        ? `Kasse: Verkauf Beleg ${p.referenceNumber}`
        : `Kasse: Erstattung Beleg ${p.referenceNumber}`;
      batch.create(movementsCol.doc(p.movementId), {
        orgId,
        siteId,
        productId: p.productId,
        productName: p.productName || null,
        type: p.delta < 0 ? "issue" : "receipt",
        quantityDelta: p.delta,
        balanceAfter: null,
        reason,
        relatedOrderId: null,
        source: "oktopos",
        externalRef: p.referenceNumber,
        createdByUid: null,
        createdAt: p.txDate
          ? Timestamp.fromDate(p.txDate)
          : FieldValue.serverTimestamp(),
      });
    }
    for (const [productId, totalDelta] of deltaByProduct) {
      // set(merge:true) statt update(): wurde ein Produkt zwischen
      // loadProductLookups und dem Commit gelöscht, würde update() mit
      // NOT_FOUND fehlschlagen und den GESAMTEN atomaren Batch (inkl. der
      // Bewegungs-creates) verwerfen -> ganzer Sync-Lauf bricht ab. merge-set
      // schreibt robust fort (legt im Extremfall ein Doc an, statt zu crashen).
      const update = {
        currentStock: FieldValue.increment(totalDelta),
        updatedAt: FieldValue.serverTimestamp(),
      };
      // Kuehlschrank-Ist mitfuehren (nur inFridge-Artikel). Kann roh negativ
      // werden -> Flooring leseseitig via Product.fridgeStockClamped (Plan §7).
      if (fridgeDeltaByProduct.has(productId)) {
        update.fridgeStock = FieldValue.increment(
          fridgeDeltaByProduct.get(productId),
        );
      }
      batch.set(productsCol.doc(productId), update, {merge: true});
    }
    await batch.commit();
    for (const p of slice) {
      applied.add(p.movementId);
    }
  }
  return applied;
}

// Verkaufsfakten-Layer (P0): schreibt je Beleg EIN posReceipts-Doc mit
// eingebetteten `lines[]` (1 Write/Beleg statt 1+N). Im Gegensatz zu den
// Bewegungen (batch.create, nie ueberschreiben) per `set(merge:true)`:
// idempotent + ein Re-Pull aktualisiert ein evtl. korrigiertes Beleg-Faktum.
// Doc-Schreiben ausschliesslich serverseitig (Admin SDK) — die Client-Rules
// erlauben kein write auf posReceipts. Gibt die Anzahl geschriebener Belege.
async function applyOktoposReceiptsBatch(orgId, siteId, cashRegisterId, items) {
  if (!Array.isArray(items) || items.length === 0) {
    return 0;
  }
  const col = organizationCollection(orgId, "posReceipts");
  // Innerhalb des Laufs nach receiptId deduplizieren (letzter gewinnt).
  const byId = new Map();
  for (const r of items) {
    byId.set(r.receiptId, r);
  }
  const unique = [...byId.values()];
  let persisted = 0;
  const CHUNK = 400; // je Beleg 1 Write -> sicher unter dem 500er-Batch-Limit.
  for (let i = 0; i < unique.length; i += CHUNK) {
    const slice = unique.slice(i, i + CHUNK);
    const batch = db.batch();
    for (const r of slice) {
      batch.set(col.doc(r.receiptId), {
        orgId,
        siteId,
        cashRegisterId: cashRegisterId == null ? null : cashRegisterId,
        referenceNumber: r.referenceNumber,
        type: r.type,
        training: r.training === true,
        isRevenue: r.isRevenue === true,
        businessDay: r.businessDay,
        transactionDate: r.txDate ? Timestamp.fromDate(r.txDate) : null,
        grossCents: r.grossCents,
        taxes: r.taxes,
        payments: r.payments,
        lines: r.lines,
        lineCount: r.lineCount,
        truncatedLines: r.truncatedLines === true,
        cashierId: r.cashierId,
        customerId: r.customerId,
        source: "oktopos",
        syncedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await batch.commit();
    persisted += slice.length;
  }
  return persisted;
}

// Zentraler HTTP-Helfer fuer ALLE ausgehenden Kassen-Calls: AbortController +
// Timeout, einheitliches X-API-KEY-Header-Setzen und GENAU EINE strukturierte
// Log-Zeile je Call (siehe logOktoposHttp). Gibt die rohe Response zurueck;
// Status-/JSON-Auswertung bleibt beim Aufrufer. Loggt NIE Header/Key/Body/PII.
async function oktoposFetch({method, baseUrl, path, apiKey, body, fn, requestId}) {
  const headers = {"X-API-KEY": apiKey, "Accept": "application/json"};
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), OKTOPOS_FETCH_TIMEOUT_MS);
  const startedAt = Date.now();
  let response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    logOktoposHttp({
      fn, requestId, method, path,
      status: null, ok: false, durationMs: Date.now() - startedAt, error,
    });
    throw new HttpsError(
      "unavailable", `OktoPOS nicht erreichbar: ${truncateError(error)}`,
    );
  } finally {
    clearTimeout(timer);
  }
  logOktoposHttp({
    fn, requestId, method, path,
    status: response.status, ok: response.ok, durationMs: Date.now() - startedAt,
  });
  return response;
}

// Severity nach Status: 403 (Key abgelehnt) + Netzwerk-/Timeout-Fehler = error
// (operativ kritisch, alarmfaehig); erwartete Idempotenz-Codes 404/409 + ok =
// info; sonstige 4xx/5xx = warn. Loggt nur den (entschaerften) Pfad, nie
// Query-/Body-Werte und nie den API-Key.
function logOktoposHttp({fn, requestId, method, path, status, ok, durationMs,
  error}) {
  const entry = {
    event: "oktopos_http",
    fn: fn || null,
    requestId: requestId || null,
    method,
    path: redactOktoposPath(path),
    status: status == null ? null : status,
    ok: ok === true,
    durationMs,
  };
  if (error) {
    entry.error = truncateError(error);
  }
  if (status === 403 || (status == null && error)) {
    logger.error("oktopos_http", entry);
  } else if (status != null && status >= 400 &&
      status !== 404 && status !== 409) {
    logger.warn("oktopos_http", entry);
  } else {
    logger.info("oktopos_http", entry);
  }
}

// Dynamische Pfad-Segmente zu Platzhaltern normalisieren: haelt die Log-
// Kardinalitaet niedrig und verhindert, dass IDs/Datumswerte ins Log lecken.
// Statische Pfade (/articles, /customers, ...) bleiben unveraendert.
function redactOktoposPath(path) {
  return stringOrEmpty(path)
    .replace(/\/from\/[^/]+/, "/from/:from")
    .replace(/\/until\/[^/]+/, "/until/:until")
    .replace(/\/page\/[^/]+/, "/page/:page")
    .replace(/\/size\/[^/]+/, "/size/:size")
    .replace(/\/cash-register\/[^/]+/, "/cash-register/:cr")
    .replace(
      /\/findByExternalIdentifier\/[^/]+/,
      "/findByExternalIdentifier/:externalId",
    );
}

async function fetchOktoposTransactionsPage({
  baseUrl, apiKey, fromIso, untilIso, page, size, cashRegisterId, fn, requestId,
}) {
  // Path-Parameter (KEINE Query-Parameter); cash-register-Segment nur wenn
  // gesetzt (sonst ganzes Segment weglassen, gemaess Spec).
  let path = "/transactions" +
    `/from/${encodeURIComponent(fromIso)}` +
    `/until/${encodeURIComponent(untilIso)}` +
    `/page/${page}` +
    `/size/${size}`;
  if (cashRegisterId != null) {
    path += `/cash-register/${cashRegisterId}`;
  }

  const response = await oktoposFetch({
    method: "GET", baseUrl, path, apiKey, fn, requestId,
  });

  if (response.status === 403) {
    throw new HttpsError(
      "permission-denied",
      "OktoPOS lehnte den API-Key ab (403). Schluessel/Freischaltung pruefen.",
    );
  }
  if (!response.ok) {
    throw new HttpsError("unavailable", `OktoPOS-Fehler HTTP ${response.status}.`);
  }

  let payload;
  try {
    payload = await response.json();
  } catch (error) {
    throw new HttpsError("internal", "OktoPOS-Antwort war kein gueltiges JSON.");
  }
  // Antwort ist ein TransactionResponse-Objekt ODER ein Array davon
  // (z.B. ein Wrapper je Kasse). Beide Formen normalisieren.
  return Array.isArray(payload) ? payload : [payload];
}

function parseOktoposDate(value) {
  if (value == null) return null;
  const s = String(value).trim();
  if (!s) return null;
  // 'YYYY-MM-DD' (Geschaeftstag) und ISO-DateTime akzeptieren.
  const d = new Date(s.length === 10 ? `${s}T00:00:00` : s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function parseOktoposTxDate(tx) {
  return parseOktoposDate(tx?.transactionDate?.timestamp) ||
    parseOktoposDate(tx?.businessDay);
}

function toOktoposDateTime(date) {
  // OktoPOS-Beispielformat: 2021-12-01T12:00:00 (ohne Millis/Zone).
  return date.toISOString().slice(0, 19);
}

function daysAgo(base, days) {
  return new Date(base.getTime() - days * 24 * 60 * 60 * 1000);
}

function buildOktoposMovementId(cashRegisterId, referenceNumber, lineId) {
  const raw = stringOrEmpty(referenceNumber);
  // safeRef ist verlustbehaftet (Sonderzeichen -> "_"), daher wie bei
  // buildOktoposReceiptId einen kollisionsfreien Hash der ROH-Belegnummer
  // anhaengen: gleiche Rohnummer = gleiche ID (idempotent), verschiedene
  // Rohnummern = verschiedene IDs (kein Doppel-/Fehlbuchen beim Re-Pull).
  const safeRef = raw.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120);
  const cr = cashRegisterId == null ? "all" : String(cashRegisterId);
  return `oktopos-${cr}-${safeRef}-${stableHash([raw]).slice(0, 12)}-${lineId}`;
}

// Doc-ID eines posReceipts (P0). `referenceNumber` ist nur JE KASSE eindeutig
// -> mit Kassen-Nr. (oder, falls keine gesetzt, Standort) qualifizieren, sonst
// Cross-Store-Kollision. Deterministisch = Idempotenz beim Re-Pull (set(merge)).
// Der lesbare `safeRef` ersetzt Sonderzeichen verlustbehaftet (zwei
// verschiedene Belegnummern könnten gleich normalisieren) -> ein
// kollisionsfreier Hash der ROH-Belegnummer wird angehängt; gleiche Rohnummer
// = gleiche ID (idempotent), verschiedene Rohnummern = verschiedene IDs.
function buildOktoposReceiptId(cashRegisterId, siteId, referenceNumber) {
  const raw = stringOrEmpty(referenceNumber);
  const safeRef = raw.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120);
  const scope = cashRegisterId == null
    ? stringOrEmpty(siteId).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 80) || "all"
    : String(cashRegisterId);
  return `${scope}-${safeRef}-${stableHash([raw]).slice(0, 12)}`;
}

// OktoPOS-Geldbetraege kommen je nach Endpoint als Zahl, String ("1,23"/"1.23")
// oder Money-Objekt ({decimal|amount|value|cents}). Tolerant nach ganzen Cents
// (Math.round, NICHT truncaten — sonst systematischer 1-Cent-Verlust). null,
// wenn nicht ermittelbar. FELDNAMEN/Form gegen die OktoPOS-Swagger verifizieren,
// bevor fachlich (Marge/USt) darauf gebaut wird (P0-Hinweis, Fremddaten).
function oktoposMoneyToCents(value) {
  if (value == null) return null;
  if (typeof value === "number") {
    return Number.isFinite(value) ? Math.round(value * 100) : null;
  }
  if (typeof value === "string") {
    const n = Number(value.replace(/\s/g, "").replace(",", "."));
    return Number.isFinite(n) ? Math.round(n * 100) : null;
  }
  if (typeof value === "object") {
    const inner = value.decimal ?? value.amount ?? value.value ?? value.gross;
    if (inner != null && typeof inner !== "object") {
      return oktoposMoneyToCents(inner);
    }
    if (value.cents != null) {
      const c = Number(value.cents);
      return Number.isFinite(c) ? Math.round(c) : null;
    }
  }
  return null;
}

// Belegweite USt-Aufschluesselung (OktoPOS liefert den Satz NUR je Beleg, nicht
// je Position — LineItem hat kein Steuerfeld). Einheit = ganze Prozent
// (`ratePercent`, konsistent zu Product.taxRatePercent), Geld in Cents. Tolerant;
// Feldnamen gegen die Swagger verifizieren.
function parseOktoposReceiptTaxes(tx) {
  const raw = asArray(tx?.taxes ?? tx?.receiptTaxes);
  const out = [];
  for (const t of raw) {
    if (!isPlainObject(t)) continue;
    const rate = Number(t.ratePercent ?? t.rate ?? t.taxRate ?? t.percentage);
    out.push({
      ratePercent: Number.isFinite(rate) ? Math.round(rate) : null,
      netCents: oktoposMoneyToCents(t.net ?? t.netAmount ?? t.netValue),
      taxCents: oktoposMoneyToCents(t.tax ?? t.taxAmount ?? t.vat),
      grossCents: oktoposMoneyToCents(t.gross ?? t.grossAmount ?? t.grossValue),
    });
  }
  return out;
}

// Zahlart-Aufschluesselung des Belegs (bar/Karte/...). Tolerant; method als
// normalisierter Kleinbuchstaben-Token. Feldnamen gegen die OktoPOS-Swagger
// verifizieren (P0, Fremddaten) — heute best-effort/optional.
function parseOktoposPayments(tx) {
  const raw = asArray(tx?.payments ?? tx?.paymentDetails ?? tx?.tenders);
  const out = [];
  for (const p of raw) {
    if (!isPlainObject(p)) continue;
    const method = stringOrNull(p.method ?? p.type ?? p.paymentType ?? p.tenderType);
    out.push({
      method: method ? method.toLowerCase() : null,
      amountCents: oktoposMoneyToCents(p.amount ?? p.amountCents ?? p.value ?? p.sum),
      subType: stringOrNull(p.subType ?? p.subtype ?? p.cardType),
    });
  }
  return out;
}

function truncateError(error) {
  return stringOrEmpty(error?.message || error).slice(0, 200);
}

// ===========================================================================
// OktoPOS-Kassenanbindung — Artikel/Preise SCHREIBEN (WorkTime -> Kasse, M5)
// ---------------------------------------------------------------------------
// Schreibt Artikel-Stammdaten/Preise/Barcodes in die OktoPOS-Kasse (ArticleApi).
// Gleiche Sicherheits-Eckpunkte wie der Pull (Secret-Key, https, X-API-KEY,
// admin-only, server-zu-server). Idempotenz über externalReferenceNumber =
// WorkTime-Produkt-ID: existiert der Artikel schon (HTTP 409 bei POST /articles),
// wird auf POST /articles/change-prices ausgewichen. Barcodes werden best-effort
// separat gepflegt (POST /articles/add-barcodes). Kein Schreiben in Firestore.
// ===========================================================================

// Lädt die Referenz-Tokens (Einheiten + Vertriebskanäle) aus der Kasse, damit
// die Einstellungs-UI gültige Werte anbieten kann.
exports.getOktoposLookups = callable(
  "getOktoposLookups",
  {region: REGION, secrets: [OKTOPOS_API_KEYS], timeoutSeconds: 60},
  async (request, {requestId, fn}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    assertAdmin(caller);
    const orgId = requiredString(request.data?.orgId, "orgId");
    assertSameOrg(caller, orgId);
    const siteId = requiredString(request.data?.siteId, "siteId");

    const config = await loadOktoposConfig(orgId);
    const baseUrl = resolveOktoposBaseUrl(config);
    const apiKey = resolveOktoposApiKey(OKTOPOS_API_KEYS.value(), siteId);

    const [units, channels] = await Promise.all([
      fetchOktoposJson(baseUrl, apiKey, "/articles/units", fn, requestId),
      fetchOktoposJson(
        baseUrl, apiKey, "/articles/distribution-channels", fn, requestId,
      ),
    ]);
    return {
      units: normalizeTokenList(units),
      distributionChannels: normalizeTokenList(channels),
    };
  },
);

// Schreibt (ausgewählte oder alle aktiven) Artikel eines Standorts in die Kasse.
exports.pushOktoposArticles = callable(
  "pushOktoposArticles",
  {region: REGION, secrets: [OKTOPOS_API_KEYS], timeoutSeconds: 300,
    memory: "256MiB"},
  async (request, {requestId, fn}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    assertAdmin(caller);
    const orgId = requiredString(request.data?.orgId, "orgId");
    assertSameOrg(caller, orgId);
    const siteId = requiredString(request.data?.siteId, "siteId");
    const productIds = asStringArray(request.data?.productIds);
    const dryRun = request.data?.dryRun === true;

    const config = await loadOktoposConfig(orgId);
    const baseUrl = resolveOktoposBaseUrl(config);
    const apiKey = resolveOktoposApiKey(OKTOPOS_API_KEYS.value(), siteId);

    const push = isPlainObject(config.push) ? config.push : {};
    const opts = {
      distributionChannel: stringOrNull(push.distributionChannel),
      defaultUnitToken: stringOrNull(push.defaultUnitToken),
      defaultTaxRate: asInteger(push.defaultTaxRate, 19),
      cashierCanChangePrice: push.cashierCanChangePrice === true,
      unitTokenMap: isPlainObject(push.unitTokenMap) ? push.unitTokenMap : {},
    };
    if (!opts.distributionChannel) {
      throw new HttpsError(
        "failed-precondition",
        "Kein Vertriebskanal (distributionChannel) in den Kassen-" +
          "Einstellungen hinterlegt.",
      );
    }
    if (!opts.defaultUnitToken) {
      throw new HttpsError(
        "failed-precondition",
        "Keine Standard-Einheit (defaultUnitToken) in den Kassen-" +
          "Einstellungen hinterlegt.",
      );
    }

    const products = await loadPushProducts(orgId, siteId, productIds);
    const result = {
      siteId,
      total: products.length,
      created: 0,
      updated: 0,
      failed: 0,
      skipped: 0,
      dryRun,
      results: [],
    };

    for (const product of products) {
      let outcome;
      try {
        outcome = await pushSingleArticle({
          baseUrl, apiKey, product, opts, dryRun, fn, requestId,
        });
      } catch (error) {
        // 403 (Key abgelehnt) bricht den ganzen Push ab; sonst pro Artikel
        // protokollieren und weitermachen.
        if (error instanceof HttpsError && error.code === "permission-denied") {
          throw error;
        }
        outcome = {status: "failed", message: truncateError(error)};
      }
      if (outcome.status === "created") result.created += 1;
      else if (outcome.status === "updated") result.updated += 1;
      else if (outcome.status === "failed") result.failed += 1;
      else result.skipped += 1;
      if (result.results.length < 200) {
        result.results.push({
          productId: product.id,
          name: product.name,
          status: outcome.status,
          message: outcome.message || null,
        });
      }
    }
    // Nur Aggregate loggen, nie result.results (enthaelt Produktnamen).
    logger.info("oktopos_push_done", {
      event: "oktopos_push_done",
      fn,
      requestId,
      kind: "articles",
      siteId,
      total: result.total,
      created: result.created,
      updated: result.updated,
      failed: result.failed,
      skipped: result.skipped,
      dryRun,
    });
    return result;
  },
);

function resolveOktoposBaseUrl(config) {
  const baseUrl = stringOrEmpty(config?.baseUrl).trim().replace(/\/+$/, "");
  if (!baseUrl) {
    throw new HttpsError(
      "failed-precondition",
      "OktoPOS ist nicht eingerichtet (baseUrl fehlt im Config-Dokument " +
        "config/oktoposSync).",
    );
  }
  // TLS-Pflicht: der API-Key darf nie im Klartext ueber http gehen.
  if (!baseUrl.toLowerCase().startsWith("https://")) {
    throw new HttpsError("failed-precondition", "OktoPOS baseUrl muss https sein.");
  }
  return baseUrl;
}

function normalizeTokenList(list) {
  return asArray(list)
    .map((item) => ({
      id: Number.isFinite(Number(item?.id)) ? Math.trunc(Number(item.id)) : null,
      token: stringOrNull(item?.token),
    }))
    .filter((item) => item.token);
}

async function loadPushProducts(orgId, siteId, productIds) {
  const snap = await organizationCollection(orgId, "products")
    .where("siteId", "==", siteId)
    .get();
  const wanted = productIds.length > 0 ? new Set(productIds) : null;
  const products = [];
  for (const doc of snap.docs) {
    if (wanted && !wanted.has(doc.id)) {
      continue;
    }
    const data = doc.data() || {};
    // Ohne explizite Auswahl nur aktive Artikel pushen.
    if (!wanted && data.isActive === false) {
      continue;
    }
    products.push({
      id: doc.id,
      name: stringOrNull(data.name),
      sku: stringOrNull(data.sku),
      barcode: stringOrNull(data.barcode),
      category: stringOrNull(data.category),
      unit: stringOrNull(data.unit),
      sellingPriceCents: data.sellingPriceCents,
      taxRatePercent: data.taxRatePercent,
    });
  }
  return products;
}

async function pushSingleArticle(
  {baseUrl, apiKey, product, opts, dryRun, fn, requestId},
) {
  const sellingCents = asInteger(product.sellingPriceCents, -1);
  if (sellingCents < 0) {
    return {status: "skipped", message: "kein Verkaufspreis"};
  }
  if (!stringOrNull(product.name)) {
    return {status: "skipped", message: "kein Name"};
  }
  const unitToken = stringOrNull(opts.unitTokenMap[product.unit]) ||
    opts.defaultUnitToken;
  if (!unitToken) {
    return {status: "failed", message: "keine Einheit"};
  }
  if (dryRun) {
    return {status: "skipped", message: "dry-run"};
  }

  const body = buildOktoposArticleBody(product, opts, unitToken, sellingCents);
  const createRes = await postOktoposJson(
    baseUrl, apiKey, "/articles", body, fn, requestId,
  );
  if (createRes.status === 403) {
    throw new HttpsError(
      "permission-denied",
      "OktoPOS lehnte den API-Key ab (403). Freischaltung/Schluessel pruefen.",
    );
  }
  if (createRes.ok) {
    await addBarcodesBestEffort(baseUrl, apiKey, product, fn, requestId);
    return {status: "created"};
  }
  if (createRes.status === 409) {
    // Artikel existiert bereits -> nur Preise aktualisieren.
    const changeRes = await postOktoposJson(
      baseUrl,
      apiKey,
      "/articles/change-prices",
      {externalReferenceNumber: product.id, price: body.price},
      fn,
      requestId,
    );
    if (changeRes.status === 403) {
      throw new HttpsError("permission-denied", "OktoPOS lehnte den API-Key ab (403).");
    }
    if (changeRes.ok) {
      await addBarcodesBestEffort(baseUrl, apiKey, product, fn, requestId);
      return {status: "updated"};
    }
    return {status: "failed", message: `Preisaenderung HTTP ${changeRes.status}`};
  }
  return {status: "failed", message: `Anlegen HTTP ${createRes.status}`};
}

function buildOktoposArticleBody(product, opts, unitToken, sellingCents) {
  const taxRate = Number.isFinite(Number(product.taxRatePercent))
    ? Math.trunc(Number(product.taxRatePercent))
    : opts.defaultTaxRate;
  const body = {
    externalReferenceNumber: product.id,
    description: product.name,
    unit: {token: unitToken},
    price: [
      {
        distributionChannel: {token: opts.distributionChannel},
        price: sellingCents / 100,
        taxRate: Number(taxRate).toFixed(2),
      },
    ],
    cashierCanChangePrice: opts.cashierCanChangePrice,
  };
  if (stringOrNull(product.sku)) {
    body.materialNumber = product.sku;
  }
  if (stringOrNull(product.category)) {
    body.group = {token: product.category};
  }
  return body;
}

async function addBarcodesBestEffort(baseUrl, apiKey, product, fn, requestId) {
  const barcode = stringOrNull(product.barcode);
  if (!barcode) {
    return;
  }
  try {
    await postOktoposJson(baseUrl, apiKey, "/articles/add-barcodes", {
      externalReferenceNumber: product.id,
      barcodes: [{value: barcode, crate: false}],
      forceReuse: true,
    }, fn, requestId);
  } catch (error) {
    // Barcode-Pflege ist best-effort; der Artikel selbst ist schon geschrieben.
    logger.warn("oktopos_add_barcodes_failed", {
      event: "oktopos_add_barcodes_failed",
      fn: fn || "pushOktoposArticles",
      requestId: requestId || null,
      productId: product.id,
      error: truncateError(error),
    });
  }
}

async function fetchOktoposJson(baseUrl, apiKey, path, fn, requestId) {
  const response = await oktoposFetch({
    method: "GET", baseUrl, path, apiKey, fn, requestId,
  });
  if (response.status === 403) {
    throw new HttpsError("permission-denied", "OktoPOS lehnte den API-Key ab (403).");
  }
  if (!response.ok) {
    throw new HttpsError("unavailable", `OktoPOS-Fehler HTTP ${response.status}.`);
  }
  try {
    return await response.json();
  } catch (error) {
    throw new HttpsError("internal", "OktoPOS-Antwort war kein gueltiges JSON.");
  }
}

async function postOktoposJson(baseUrl, apiKey, path, body, fn, requestId) {
  return oktoposFetch({
    method: "POST", baseUrl, path, apiKey, body, fn, requestId,
  });
}

async function getOktoposRaw(baseUrl, apiKey, path, fn, requestId) {
  return oktoposFetch({
    method: "GET", baseUrl, path, apiKey, fn, requestId,
  });
}

// ===========================================================================
// OktoPOS-Kassenanbindung — Kunden-Import (WorkTime Contacts -> Kasse, M6a)
// ---------------------------------------------------------------------------
// Schreibt Kunden-Kontakte (ContactType.customer) als OktoPOS-Customer in die
// Kasse (CustomerApi). Gleiche Sicherheits-Eckpunkte wie Pull/Push. Die
// CustomerApi hat KEINEN Update-Endpunkt, daher idempotent über
// externalIdentifier = WorkTime-Contact-ID: zuerst
// GET /customers/findByExternalIdentifier (404/409 = unbekannt) und nur dann
// POST /customers (anlegen). Bereits vorhandene Kunden werden übersprungen.
// (Bestell-Import/OrderApi bewusst NICHT umgesetzt — siehe plan-Datei: ein
// stationärer Kiosk hat keine Quelldaten für pickupToken/pickupTime/taxRateId.)
// ===========================================================================

exports.pushOktoposCustomers = callable(
  "pushOktoposCustomers",
  {region: REGION, secrets: [OKTOPOS_API_KEYS], timeoutSeconds: 300,
    memory: "256MiB"},
  async (request, {requestId, fn}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    assertAdmin(caller);
    const orgId = requiredString(request.data?.orgId, "orgId");
    assertSameOrg(caller, orgId);
    const siteId = requiredString(request.data?.siteId, "siteId");
    const contactIds = asStringArray(request.data?.contactIds);
    const dryRun = request.data?.dryRun === true;

    const config = await loadOktoposConfig(orgId);
    const baseUrl = resolveOktoposBaseUrl(config);
    const apiKey = resolveOktoposApiKey(OKTOPOS_API_KEYS.value(), siteId);
    const groupName = stringOrNull(config.customerGroupName) || "Stammkunde";

    const contacts = await loadPushContacts(orgId, contactIds);
    const result = {
      total: contacts.length,
      created: 0,
      skipped: 0,
      failed: 0,
      dryRun,
      results: [],
    };
    for (const contact of contacts) {
      let outcome;
      try {
        outcome = await pushSingleCustomer({
          baseUrl, apiKey, contact, groupName, dryRun, fn, requestId,
        });
      } catch (error) {
        if (error instanceof HttpsError && error.code === "permission-denied") {
          throw error;
        }
        outcome = {status: "failed", message: truncateError(error)};
      }
      if (outcome.status === "created") result.created += 1;
      else if (outcome.status === "failed") result.failed += 1;
      else result.skipped += 1;
      if (result.results.length < 200) {
        result.results.push({
          contactId: contact.id,
          name: contact.name,
          status: outcome.status,
          message: outcome.message || null,
        });
      }
    }
    // Nur Aggregate loggen, nie result.results (enthaelt Kundennamen/PII).
    logger.info("oktopos_push_done", {
      event: "oktopos_push_done",
      fn,
      requestId,
      kind: "customers",
      total: result.total,
      created: result.created,
      skipped: result.skipped,
      failed: result.failed,
      dryRun,
    });
    return result;
  },
);

async function loadPushContacts(orgId, contactIds) {
  const snap = await organizationCollection(orgId, "contacts")
    .where("type", "==", "customer")
    .get();
  const wanted = contactIds.length > 0 ? new Set(contactIds) : null;
  const contacts = [];
  for (const doc of snap.docs) {
    if (wanted && !wanted.has(doc.id)) {
      continue;
    }
    const data = doc.data() || {};
    if (!wanted && data.isActive === false) {
      continue;
    }
    contacts.push({
      id: doc.id,
      name: stringOrNull(data.name),
      email: stringOrNull(data.email),
      phone: stringOrNull(data.phone),
      mobile: stringOrNull(data.mobile),
      street: stringOrNull(data.street),
      postalCode: stringOrNull(data.postalCode),
      city: stringOrNull(data.city),
      taxId: stringOrNull(data.taxId),
      customerNumber: stringOrNull(data.customerNumber),
      notes: stringOrNull(data.notes),
    });
  }
  return contacts;
}

async function pushSingleCustomer(
  {baseUrl, apiKey, contact, groupName, dryRun, fn, requestId},
) {
  if (!stringOrNull(contact.name)) {
    return {status: "skipped", message: "kein Name"};
  }
  if (dryRun) {
    return {status: "skipped", message: "dry-run"};
  }
  // Idempotenz: existiert der Kunde bereits (per externalIdentifier)? Die
  // CustomerApi kennt kein Update -> vorhandene Kunden werden übersprungen.
  const lookup = await getOktoposRaw(
    baseUrl,
    apiKey,
    `/customers/findByExternalIdentifier/${encodeURIComponent(contact.id)}`,
    fn,
    requestId,
  );
  if (lookup.status === 403) {
    throw new HttpsError("permission-denied", "OktoPOS lehnte den API-Key ab (403).");
  }
  if (lookup.ok) {
    return {status: "skipped", message: "existiert bereits"};
  }
  // 404/409 = unbekannt -> anlegen; andere Codes sind echte Fehler.
  if (lookup.status !== 404 && lookup.status !== 409) {
    return {status: "failed", message: `Lookup HTTP ${lookup.status}`};
  }
  const body = buildOktoposCustomerBody(contact, groupName);
  const createRes = await postOktoposJson(
    baseUrl, apiKey, "/customers", body, fn, requestId,
  );
  if (createRes.status === 403) {
    throw new HttpsError("permission-denied", "OktoPOS lehnte den API-Key ab (403).");
  }
  if (createRes.ok) {
    return {status: "created"};
  }
  return {status: "failed", message: `Anlegen HTTP ${createRes.status}`};
}

function buildOktoposCustomerBody(contact, groupName) {
  const name = splitPersonName(contact.name);
  const person = {name};
  if (stringOrNull(contact.email)) {
    person.email = contact.email;
  }
  // vatRegNo max. 15 Zeichen — sonst weglassen.
  if (stringOrNull(contact.taxId) && contact.taxId.length <= 15) {
    person.vatRegNo = contact.taxId;
  }
  const phones = [];
  if (stringOrNull(contact.phone)) {
    phones.push({type: "home", value: contact.phone});
  }
  if (stringOrNull(contact.mobile)) {
    phones.push({type: "mobile", value: contact.mobile});
  }
  if (phones.length > 0) {
    person.phone = phones.slice(0, 2);
  }
  const address = {};
  if (stringOrNull(contact.street)) {
    address.streetAddress = contact.street;
  }
  if (stringOrNull(contact.postalCode)) {
    address.postalCode = contact.postalCode;
  }
  if (stringOrNull(contact.city)) {
    address.addressLocality = contact.city;
  }
  if (Object.keys(address).length > 0) {
    address.addressCountry = "DE";
    person.address = address;
  }
  const body = {
    externalIdentifier: contact.id,
    groups: [{name: groupName}],
    person,
  };
  const comments = [];
  if (stringOrNull(contact.customerNumber)) {
    comments.push({type: "INTERNAL", value: `Kundennr.: ${contact.customerNumber}`});
  }
  if (stringOrNull(contact.notes)) {
    comments.push({type: "INTERNAL", value: contact.notes});
  }
  if (comments.length > 0) {
    body.comments = comments;
  }
  return body;
}

// WorkTime führt einen einzelnen Namen; OktoPOS verlangt given- UND familyName.
// Letztes Wort = Nachname, Rest = Vorname; Einzelwort (z.B. Firmenname) in beide.
function splitPersonName(name) {
  const trimmed = stringOrEmpty(name).trim().replace(/\s+/g, " ");
  if (!trimmed) {
    return {givenName: "-", familyName: "-"};
  }
  const parts = trimmed.split(" ");
  if (parts.length === 1) {
    return {givenName: parts[0], familyName: parts[0]};
  }
  return {
    givenName: parts.slice(0, -1).join(" "),
    familyName: parts[parts.length - 1],
  };
}
