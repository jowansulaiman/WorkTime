"use strict";

const crypto = require("node:crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated, onDocumentWritten} =
  require("firebase-functions/v2/firestore");
const {defineSecret, defineString} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const push = require("./push_notifications");
const monatsLock = require("./monats_lock");
const oktoposStats = require("./oktopos_stats");
const {parseThirdPartyAmounts} = require("./third_party_cash");
const kioskShift = require("./kiosk_shift");
const passwordCrypto = require("./password_crypto");
const passwordAccess = require("./password_access");
const accountDeletion = require("./account_deletion");

admin.initializeApp();

const db = admin.firestore();
// firebase-admin v13: FieldValue/Timestamp NICHT mehr zuverlaessig ueber den
// Namespace `admin.firestore.FieldValue` (kann undefined sein) -> Subpath-Import.
const {FieldValue, FieldPath, Timestamp} = require("firebase-admin/firestore");
const REGION = "europe-west3";

// OktoPOS-Kassen-API-Schluessel (HTTP-Header X-API-KEY). Ein Secret — NIE im
// Client-Bundle, NIE in Firestore, NIE per dart-define. Wert ist entweder ein
// einzelner Key-String (alle Standorte teilen ihn) ODER ein JSON-Objekt
// {"<siteId>": "<key>"} fuer einen Key je Standort/Division. Setzen via:
//   firebase functions:secrets:set OKTOPOS_API_KEYS
const OKTOPOS_API_KEYS = defineSecret("OKTOPOS_API_KEYS");
// K4/GB (SSRF-Schutz): exakte Host-Allowlist fuer die OktoPOS-baseUrl
// (kommagetrennt, z.B. "kasse.example.de,kasse2.example.de"). Die baseUrl kommt
// aus dem admin-schreibbaren config/oktoposSync — OHNE Allowlist koennte eine
// manipulierte baseUrl den X-API-KEY an einen fremden HTTPS-Server exfiltrieren.
// Leer = OktoPOS-Aufrufe verweigern (fail-closed; beim Cutover setzen).
const OKTOPOS_ALLOWED_HOSTS = defineString("OKTOPOS_ALLOWED_HOSTS", {
  default: "",
});

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

// Best-effort Server-Audit (PA-8.3): schreibt einen auditLog-Eintrag via Admin
// SDK (umgeht die Rules). Wirft NIE — ein Audit-Fehler darf keine Callable
// brechen. `action` muss in ['created','updated','deleted','corrected'] liegen
// (der Dart-Reader kennt nur diese). Zusaetzliche Felder sessionId/deviceId/
// source dienen der Server-Nachvollziehbarkeit; unbekannte Felder ignoriert der
// Reader. Fuellt die Luecke, dass Kiosk-Stempel/PIN-Operationen bislang NICHT
// im Aenderungsprotokoll auftauchten (Client hat dort keinen loggenden Pfad).
async function writeAudit({
  orgId, action, entityType, entityId, summary,
  actorUid, actorName, sessionId, deviceId, requestId,
}) {
  if (!orgId || !action || !entityType) {
    return;
  }
  try {
    await db.collection("organizations").doc(orgId).collection("auditLog").add({
      orgId,
      action,
      entityType,
      entityId: entityId || null,
      summary: summary || "",
      actorUid: actorUid || null,
      actorName: actorName || null,
      sessionId: sessionId || null,
      deviceId: deviceId || null,
      source: "server",
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.warn("audit_write_failed", {
      requestId, entityType, error: String(error),
    });
  }
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

// Zeit-Freigabe (Z7): eingereichte Zeit -> genehmigt/abgelehnt durch einen
// Freigeber -> Push an den betroffenen Mitarbeiter. Nur dieser eine Übergang
// benachrichtigt (nicht jede Statusänderung). Idempotent via thread/dedupe.
exports.onWorkEntryWritten = documentWrittenTrigger(
  "onWorkEntryWritten",
  {region: REGION, document: "organizations/{orgId}/workEntries/{entryId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const entryId = event.params.entryId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const beforeStatus = before ? stringOrEmpty(before.status) : null;
    const afterStatus = stringOrEmpty(after.status);
    if (beforeStatus === "submitted" &&
        (afterStatus === "approved" || afterStatus === "rejected")) {
      const userId = stringFromEither(after, "userId", "user_id");
      if (!userId) {
        return;
      }
      const dateLabel = push.formatDe(readTriggerDate(after, "date", "date"));
      const notif = push.buildWorkEntryDecisionNotification({
        entryId, dateLabel, approved: afterStatus === "approved",
      });
      await fanOutPush({
        orgId, recipientUids: [userId], notif, requestId: ctx.requestId,
      });
    }
  },
);

// Neues (fuer den Mitarbeiter sichtbares) Dokument in der Personalakte (PA-3.5)
// -> Push an genau diesen Mitarbeiter. Interne Ablagen (visibleToEmployee=false)
// loesen KEINE Benachrichtigung aus. Idempotent ueber dedupeId=docId.
exports.onEmployeeDocumentCreated = documentCreatedTrigger(
  "onEmployeeDocumentCreated",
  {region: REGION, document: "organizations/{orgId}/employeeDocuments/{docId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const docId = event.params.docId;
    const data = event.data?.data();
    if (!data) {
      return;
    }
    const visible = data.visibleToEmployee !== false &&
      data.visible_to_employee !== false;
    if (!visible) {
      return;
    }
    const userId = stringFromEither(data, "userId", "user_id");
    if (!userId) {
      return;
    }
    const notif = push.buildDocumentNotification({
      docId,
      title: stringOrEmpty(data.title),
    });
    await fanOutPush({
      orgId, recipientUids: [userId], notif, requestId: ctx.requestId,
    });
  },
);

// Lohnabrechnung freigegeben (Status-Übergang -> "freigegeben") -> Push an den
// Mitarbeiter (PA-7.4). „bezahlt"/„storniert"/„entwurf" lösen keinen (zweiten)
// Push aus. Idempotent über entityId=recordId (Inbox-.create()).
exports.onPayrollRecordWritten = documentWrittenTrigger(
  "onPayrollRecordWritten",
  {region: REGION, document: "organizations/{orgId}/payrollRecords/{recordId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const recordId = event.params.recordId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) {
      return;
    }
    const beforeStatus = before ? stringOrEmpty(before.status) : null;
    const afterStatus = stringOrEmpty(after.status);
    if (afterStatus !== "freigegeben" || beforeStatus === "freigegeben") {
      return;
    }
    const userId = stringFromEither(after, "userId", "user_id");
    if (!userId) {
      return;
    }
    const year = Number(valueFromEither(after, "periodYear", "period_year"));
    const month = Number(valueFromEither(after, "periodMonth", "period_month"));
    const monthLabel = (year && month) ?
      `${String(month).padStart(2, "0")}/${year}` : null;
    const notif = push.buildPayrollReleasedNotification({recordId, monthLabel});
    await fanOutPush({
      orgId, recipientUids: [userId], notif, requestId: ctx.requestId,
    });
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

// Auto-Klärung (ZV-2.3b): schließt nachts alle noch offenen Buchungen, deren
// `kommen` länger als AUTO_KLAERUNG_MIN_MINUTES zurückliegt (vergessenes
// Ausstempeln), auf `status='klaerung'` — OHNE `gehen` zu setzen (die echten
// Zeiten setzt erst der Manager-Resolve, ZV-3.1). Idempotent: der `ongoing`-
// Filter greift beim nächsten Lauf nicht mehr. Benachrichtigt den betroffenen
// Mitarbeiter (der Manager sieht es live in der Klärungs-Inbox). Region/Zeitzone
// wie die anderen Nightly-Jobs.
const AUTO_KLAERUNG_MIN_MINUTES = 12 * 60;

exports.autoKlaerungNightly = onSchedule(
  {region: REGION, schedule: "every day 03:00", timeZone: "Europe/Berlin"},
  async () => {
    const requestId = crypto.randomUUID();
    const cutoffMs = Date.now() - AUTO_KLAERUNG_MIN_MINUTES * 60 * 1000;
    const orgsSnap = await db.collection("organizations").limit(50).get();
    let orgsProcessed = 0;
    let flagged = 0;
    for (const orgDoc of orgsSnap.docs) {
      const orgId = orgDoc.id;
      let openSnap;
      try {
        openSnap = await db.collection("organizations").doc(orgId)
          .collection("clockEntries")
          .where("status", "==", "ongoing")
          .get();
      } catch (error) {
        logger.error("auto_klaerung_query_error", {
          event: "auto_klaerung_query_error", fn: "autoKlaerungNightly",
          requestId, orgId, message: truncateError(error),
        });
        continue;
      }
      if (openSnap.empty) continue;
      orgsProcessed += 1;
      for (const doc of openSnap.docs) {
        const data = doc.data() || {};
        const kommenMs = data.kommen?.toMillis?.();
        // Nur Buchungen, die lange genug offen sind (frische offene Buchungen
        // der laufenden Schicht bleiben unberührt).
        if (typeof kommenMs !== "number" || kommenMs > cutoffMs) continue;
        try {
          await doc.ref.set({
            status: "klaerung",
            klaerung: true,
            anmerkung: "Automatisch zur Klärung gelegt " +
              "(Ausstempeln vergessen).",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        } catch (error) {
          logger.error("auto_klaerung_write_error", {
            event: "auto_klaerung_write_error", fn: "autoKlaerungNightly",
            requestId, orgId, clockEntryId: doc.id,
            message: truncateError(error),
          });
          continue;
        }
        flagged += 1;
        await writeAudit({
          orgId, action: "updated", entityType: "Stempelung",
          entityId: doc.id,
          summary: "Automatisch zur Klärung gelegt (Ausstempeln vergessen)",
          actorUid: stringOrNull(data.userId), requestId,
        });
        // Betroffenen Mitarbeiter benachrichtigen (Manager sieht es live).
        const userId = stringOrNull(data.userId);
        if (!userId) continue;
        const kommenDate = data.kommen?.toDate?.();
        const notif = push.buildAutoKlaerungNotification({
          clockEntryId: doc.id,
          dayLabel: kommenDate ?
            `${String(kommenDate.getDate()).padStart(2, "0")}.` +
              `${String(kommenDate.getMonth() + 1).padStart(2, "0")}.` :
            "",
        });
        await fanOutPush({
          orgId, recipientUids: [userId], notif, requestId,
        });
      }
    }
    logger.info("auto_klaerung_done", {
      event: "auto_klaerung_done", fn: "autoKlaerungNightly",
      requestId, orgsProcessed, flagged,
    });
  },
);

// Klärung gelöst -> Mitarbeiter benachrichtigen (ZV-7). Nur der Übergang
// klaerung -> completed (Manager-Korrektur) löst einen Push aus; alle anderen
// clockEntries-Writes (Ein-/Ausstempeln, deaktiviert) werden früh verworfen —
// KEIN Push pro normalem Stempel (die Live-Sicht deckt das ab).
exports.onClockEntryWritten = documentWrittenTrigger(
  "onClockEntryWritten",
  {region: REGION, document: "organizations/{orgId}/clockEntries/{clockEntryId}"},
  async (event, ctx) => {
    const orgId = event.params.orgId;
    const clockEntryId = event.params.clockEntryId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const data = after ?? before;
    if (!data) return;
    const userId = stringFromEither(data, "userId", "user_id");

    // ── kioskPresence-Projektion (PA-4.5b): "wer ist gerade im Dienst" für
    // das Laden-Tablet, OHNE dem Geraetekonto clockEntries zu oeffnen. Ein
    // Doc je Mitarbeiter; dank {userId}-open-Guard existiert hoechstens eine
    // offene Buchung → delete bei allem, was nicht ongoing ist, ist korrekt.
    // Deckt Callable- UND Direct-Write-Pfad (Review-Auflage). Best-effort.
    if (userId) {
      const presenceRef = db.collection("organizations").doc(orgId)
        .collection("kioskPresence").doc(userId);
      const ongoing = Boolean(after) && stringOrEmpty(after.status) === "ongoing";
      try {
        if (ongoing) {
          await presenceRef.set({
            userId,
            name: stringOrEmpty(after.userName ?? after.user_name),
            siteId: after.siteId ?? after.site_id ?? null,
            siteName: after.siteName ?? after.site_name ?? null,
            kommen: after.kommen ?? null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        } else {
          await presenceRef.delete();
        }
      } catch (error) {
        logger.warn("presence_write_failed", {
          requestId: ctx.requestId, clockEntryId, error: String(error),
        });
      }
    }

    const beforeStatus = before ? stringOrEmpty(before.status) : "";
    const afterStatus = after ? stringOrEmpty(after.status) : "";

    // ── Neue Klaerung → Manager (PA-4.7): vergessenes Ausstempeln darf nicht
    // still liegen bleiben (blockiert u. a. den Monatsabschluss).
    if (userId && afterStatus === "klaerung" && beforeStatus !== "klaerung") {
      const recipientUids = push.managerUids(await loadOrgUserRecords(orgId));
      if (recipientUids.length > 0) {
        const notif = push.buildKlaerungNotification({
          entryId: clockEntryId,
          name: stringOrEmpty(after.userName ?? after.user_name),
        });
        await fanOutPush({
          orgId, recipientUids, notif, requestId: ctx.requestId,
        });
      }
    }

    // ── Klaerung geloest → Mitarbeiter (ZV, bestehend).
    if (!userId || beforeStatus !== "klaerung" || afterStatus !== "completed") {
      return;
    }
    const kommenDate = readTriggerDate(after, "kommen", "kommen");
    const nettoMin = Number(after.nettoMinutes ?? after.netto_minutes) || 0;
    const notif = push.buildKlaerungResolvedNotification({
      clockEntryId,
      dayLabel: kommenDate ? push.formatDe(kommenDate) : "",
      hours: nettoMin > 0 ? nettoMin / 60 : undefined,
    });
    await fanOutPush({
      orgId, recipientUids: [userId], notif, requestId: ctx.requestId,
    });
  },
);

// Kiosk-Anmelde-Roster (PA-4.4b): Datensparsamkeits-Projektion je users-Doc —
// nur Name + aktiv, damit das geteilte Tablet NIE volle users-Docs (mit
// hourlyRate etc.) lesen muss. Geraetekonten (role kiosk) erscheinen nie.
exports.onUserWrittenKioskRoster = documentWrittenTrigger(
  "onUserWrittenKioskRoster",
  {region: REGION, document: "users/{uid}"},
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return; // users-Docs werden nie geloescht (Rules delete:false)
    const uid = event.params.uid;
    const orgId = stringFromEither(after, "orgId", "org_id");
    if (!orgId) return;
    const rosterRef = db.collection("organizations").doc(orgId)
      .collection("kioskRoster").doc(uid);
    if (normalizeRole(after.role) === "kiosk") {
      await rosterRef.delete().catch(() => {});
      return;
    }
    const settings = isPlainObject(after.settings) ? after.settings : {};
    const name = stringOrEmpty(settings.name) || stringOrEmpty(after.email);
    await rosterRef.set({
      name,
      isActive: isTruthy(valueFromEither(after, "isActive", "is_active")),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
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

  const shifts = enforceShiftOrg(
    rawShifts.map((item, index) => parseShift(item, index, orgId)),
    orgId,
  );
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
    orgId,
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

  const shifts = enforceShiftOrg(
    rawShifts.map((item, index) => parseShift(item, index, orgId)),
    orgId,
  ).map((shift) => ({...shift, status}));
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
    orgId,
    shifts,
  });
  return {savedIds, issues};
});

// Monats-Festschreibung (PA-5, Server-Schicht): verweigert Writes in einen
// bereits abgeschlossenen Monat (`zeitkontoSnapshots/{userId}-{jahr}-{mm}`
// mit `abgeschlossen == true`) mit `failed-precondition`. Pure Anteile in
// functions/monats_lock.js (node-getestet); Dart-Spiegel
// lib/core/monats_festschreibung.dart. Nur Reopen (admin) hebt die Sperre auf.
async function assertMonatNichtFestgeschrieben({orgId, userId, date}) {
  const ym = monatsLock.jahrMonatVon(date);
  if (!ym) {
    return;
  }
  const snap = await organizationCollection(orgId, "zeitkontoSnapshots")
    .doc(monatsLock.zeitkontoSnapshotId(userId, ym.jahr, ym.monat))
    .get();
  if (snap.exists && monatsLock.istFestgeschrieben(snap.data())) {
    throw new HttpsError(
      "failed-precondition",
      monatsLock.festgeschriebenMeldung(ym.monat, ym.jahr),
    );
  }
}

exports.upsertWorkEntry = callable("upsertWorkEntry", {region: REGION}, async (request) => {
  assertSupportedVersion(request);
  const caller = await loadCallerProfile(request);
  assertTimeEntryEditor(caller);
  const entry = parseWorkEntry(request.data?.entry);
  assertSameOrg(caller, entry.orgId);
  await assertMonatNichtFestgeschrieben({
    orgId: entry.orgId,
    userId: entry.userId,
    date: entry.date,
  });

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
  const existingData = snapshot.exists ? snapshot.data() : null;
  // Z6: Freigabe-Semantik serverseitig durchsetzen (Status/Genehmiger/Re-Approval).
  const decision = resolveWorkEntryApproval({
    caller,
    entry,
    existingStatus: existingData ? stringOrEmpty(existingData.status) : null,
    materialChanged: existingData
      ? correctionReasonRequired(existingData, entry)
      : false,
    targetIsAdmin: caller.uid === entry.userId
      ? false
      : await loadTargetIsAdmin(entry.userId),
  });
  if (!decision.ok) {
    throw new HttpsError(decision.code, decision.message);
  }
  const fireDoc = applyApprovalDecision(
    toFirestoreWorkEntry(entry, caller.uid),
    decision,
    entry,
  );
  await docRef.set(
    {
      ...fireDoc,
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
  }

  // PA-5: Festschreibungs-Guard je eindeutigem (userId, Jahr, Monat) — ein
  // Snapshot-Read pro betroffenem Mitarbeiter-Monat statt pro Eintrag.
  const geprueft = new Set();
  for (const entry of entries) {
    const ym = monatsLock.jahrMonatVon(entry.date);
    if (!ym) {
      continue;
    }
    const key = monatsLock.zeitkontoSnapshotId(entry.userId, ym.jahr, ym.monat);
    if (geprueft.has(key)) {
      continue;
    }
    geprueft.add(key);
    await assertMonatNichtFestgeschrieben({
      orgId: entry.orgId,
      userId: entry.userId,
      date: entry.date,
    });
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
    caller,
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
exports.resetKioskPin = callable("resetKioskPin", {region: REGION},
  async (request, ctx) => {
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
    await writeAudit({
      orgId: caller.orgId, action: "updated", entityType: "Kiosk-PIN",
      entityId: employeeId, summary: "Kiosk-PIN zurückgesetzt",
      actorUid: caller.uid, requestId: ctx.requestId,
    });
    return {ok: true};
  });

// === Kontolöschung (Plan plan/account-loeschung.md) ========================
// deleteUserAccount: löscht ein Konto KOMPLETT. Self-Löschung (caller == target)
// ODER Admin-Fremdlöschung. `users/{uid}` ist per Rules client-unlöschbar ->
// nur dieser Admin-SDK-Pfad (umgeht Rules) darf löschen. Reauth ist ein reines
// Client-Gate; admin.auth().deleteUser braucht KEIN recent-login.
exports.deleteUserAccount = callable("deleteUserAccount", {region: REGION},
  async (request, ctx) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    // Step-up: irreversible Löschung verlangt eine kürzlich bestätigte Identität
    // (Client erzwingt Reauth; hier server-seitig verankert).
    assertRecentAuth(request);
    const targetUid = stringOrNull(request.data?.userId) || caller.uid;
    const isSelf = targetUid === caller.uid;
    if (!isSelf && !caller.isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Nur Administratoren dürfen fremde Konten löschen.",
      );
    }

    const targetSnap = await db.collection("users").doc(targetUid).get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "Das Zielkonto wurde nicht gefunden.");
    }
    const targetData = targetSnap.data() || {};
    const targetOrg = stringFromEither(targetData, "orgId", "org_id");
    // Mandantengrenze (spiegelt firestore.rules sameOrg).
    assertSameOrg(caller, targetOrg);
    const targetRole = normalizeRole(targetData.role);
    const targetEmail = stringOrEmpty(
      valueFromEither(targetData, "email", "email"),
    );

    // Letzter-Admin-Schutz: die Organisation darf nicht ohne aktiven Admin
    // zurückbleiben (das users-Doc trägt die orgId; ohne Admin wäre sie verwaist).
    if (targetRole === "admin") {
      const adminsSnap = await db.collection("users")
        .where("orgId", "==", targetOrg)
        .where("role", "==", "admin")
        .get();
      const otherActiveAdmins = adminsSnap.docs.filter((doc) =>
        doc.id !== targetUid &&
        isTruthy(valueFromEither(doc.data(), "isActive", "is_active")));
      if (otherActiveAdmins.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "Das ist der letzte aktive Administrator der Organisation und kann " +
          "nicht gelöscht werden. Ernenne zuerst einen anderen Administrator.",
        );
      }
    }

    const sentinel = accountDeletion.anonSentinel(targetUid);
    const counts = await runAccountDeletion({
      orgId: targetOrg, uid: targetUid, sentinel, requestId: ctx.requestId,
    });

    // Firebase-Auth-Nutzer entfernen (Admin SDK, kein Reauth nötig).
    try {
      await admin.auth().deleteUser(targetUid);
    } catch (error) {
      if (error?.code !== "auth/user-not-found") {
        logger.error("account_delete_auth_failed", {
          requestId: ctx.requestId, code: error?.code,
        });
        throw new HttpsError(
          "internal",
          "Der Anmelde-Zugang konnte nicht gelöscht werden.",
        );
      }
    }

    // userInvites (E-Mail-basiert) entfernen -> sonst sperrt der Bootstrap den
    // nächsten Login mit demselben Auth-Konto (StateError „keine Einladung").
    if (targetEmail) {
      await db.collection("userInvites")
        .doc(accountDeletion.inviteDocId(targetEmail))
        .delete()
        .catch(() => {});
    }

    await writeAudit({
      orgId: targetOrg, action: "deleted", entityType: "Benutzerkonto",
      entityId: targetUid,
      summary: isSelf
        ? "Eigenes Konto endgültig gelöscht"
        : "Benutzerkonto endgültig gelöscht (Daten anonymisiert)",
      actorUid: caller.uid, requestId: ctx.requestId,
    });
    return {ok: true, hardDeleted: counts.hardDeleted,
      anonymized: counts.anonymized};
  });

// Löscht/aktualisiert alle Treffer einer Query in Blöcken (Firestore-Batch-Limit
// 500). Re-queriert nach jedem Commit: gelöschte Docs fallen aus dem Filter,
// anonymisierte (Link-Feld != uid danach) ebenso -> die Schleife terminiert.
async function forEachQueryChunk(query, apply) {
  const CHUNK = 300;
  let processed = 0;
  for (let guard = 0; guard < 100000; guard++) {
    const snap = await query.limit(CHUNK).get();
    if (snap.empty) {
      break;
    }
    const batch = db.batch();
    let ops = 0;
    for (const doc of snap.docs) {
      if (apply(batch, doc)) {
        ops++;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
    processed += ops;
    // Voller Chunk ohne Änderung => nächste Query liefert dieselben Docs
    // (Endlosschleife). Und ein Teil-Chunk bedeutet ohnehin „alles gesehen".
    if (snap.size < CHUNK || ops === 0) {
      break;
    }
  }
  return processed;
}

// Server-seitiges Step-up für irreversible Aktionen: verlangt eine kürzlich
// bestätigte Identität (Reauth ODER frischer Login). Der Client erzwingt die
// Reauth im UI-Gate; hier server-seitig verankert, damit ein bloß gültiges
// (evtl. entwendetes/unbeaufsichtigtes) Token allein nicht genügt. `auth_time`
// (Sekunden) steckt im ID-Token; Client-Reauth erneuert das Token.
function assertRecentAuth(request, maxAgeSeconds = 600) {
  const authTime = Number(request.auth?.token?.auth_time);
  if (!Number.isFinite(authTime) ||
      (Date.now() / 1000) - authTime > maxAgeSeconds) {
    throw new HttpsError(
      "failed-precondition",
      "Bitte bestätige aus Sicherheitsgründen deine Identität erneut und " +
      "wiederhole die Löschung.",
    );
  }
}

// Führt die eigentliche Daten-Löschung/-Anonymisierung gemäß der Klassifikation
// aus account_deletion.js aus (Admin SDK, umgeht Rules).
async function runAccountDeletion({orgId, uid, sentinel, requestId}) {
  const org = (name) => organizationCollection(orgId, name);
  const counts = {hardDeleted: 0, anonymized: 0};

  // A) Doc-ID == uid direkt löschen.
  for (const name of accountDeletion.DOC_ID_DELETE) {
    await org(name).doc(uid).delete().catch(() => {});
    counts.hardDeleted++;
  }

  // A) Feld-basiert hart löschen.
  for (const {collection, field} of accountDeletion.FIELD_DELETE) {
    counts.hardDeleted += await forEachQueryChunk(
      org(collection).where(field, "==", uid),
      (batch, doc) => {
        batch.delete(doc.ref);
        return true;
      },
    );
  }

  // B) Anonymisieren (Link-Felder -> Marker), Doc bleibt erhalten.
  for (const {collection, fields} of accountDeletion.ANONYMIZE) {
    for (const field of fields) {
      counts.anonymized += await forEachQueryChunk(
        org(collection).where(field, "==", uid),
        (batch, doc) => {
          const update = accountDeletion.computeAnonymizeUpdate(
            doc.data(), uid, sentinel, fields);
          if (Object.keys(update).length === 0) {
            return false;
          }
          batch.update(doc.ref, update);
          return true;
        },
      );
    }
  }

  // B') Anonymisieren in PRODUKT-Subcollections (collectionGroup, org-gefiltert).
  for (const {group, orgField, fields} of
    accountDeletion.SUBCOLLECTION_ANONYMIZE) {
    for (const field of fields) {
      counts.anonymized += await forEachQueryChunk(
        db.collectionGroup(group)
          .where(orgField, "==", orgId)
          .where(field, "==", uid),
        (batch, doc) => {
          const update = accountDeletion.computeAnonymizeUpdate(
            doc.data(), uid, sentinel, fields);
          if (Object.keys(update).length === 0) {
            return false;
          }
          batch.update(doc.ref, update);
          return true;
        },
      );
    }
  }

  // B) passwordEntries: uid aus Empfänger-Arrays entfernen, eigene Einträge
  // samt Secret/Log löschen. Best-effort (Passwortmanager-Modul optional).
  try {
    await cleanupPasswordEntries(orgId, uid);
  } catch (error) {
    logger.warn("account_delete_passwords_failed",
      {requestId, error: truncateError(error)});
  }

  // users/{uid} + Subcollection fcmTokens zuletzt (recursiveDelete kaskadiert).
  await db.recursiveDelete(db.collection("users").doc(uid));
  counts.hardDeleted++;

  return counts;
}

async function cleanupPasswordEntries(orgId, uid) {
  const entries = organizationCollection(orgId, "passwordEntries");
  // uid aus den Empfänger-Arrays entfernen.
  await forEachQueryChunk(
    entries.where("audienceUids", "array-contains", uid),
    (batch, doc) => {
      batch.update(doc.ref, {audienceUids: FieldValue.arrayRemove(uid)});
      return true;
    },
  );
  // Eigene Einträge + zugehörige Secrets/Zugriffslogs löschen.
  const ownSnap = await entries.where("ownerUid", "==", uid).get();
  for (const doc of ownSnap.docs) {
    const id = doc.id;
    await doc.ref.delete().catch(() => {});
    await organizationCollection(orgId, "passwordSecrets").doc(id)
      .delete().catch(() => {});
    await forEachQueryChunk(
      organizationCollection(orgId, "passwordAccessLog")
        .where("entryId", "==", id),
      (batch, logDoc) => {
        batch.delete(logDoc.ref);
        return true;
      },
    );
  }
}

// kioskBeginSession: das Kiosk-Geraet meldet einen Mitarbeiter per PIN an.
// request.auth == Geraete-Konto. Prueft PIN serverseitig (scrypt) + Rate-Limit/
// Lockout + gleiche Org, legt eine kurzlebige Session an und gibt deren `sid`
// zurueck. App Check erzwungen (nur die echte App darf anmelden).
exports.kioskBeginSession = callable(
  "kioskBeginSession",
  {region: REGION, enforceAppCheck: true},
  async (request, ctx) => {
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
    await writeAudit({
      orgId: empOrg, action: "created", entityType: "Kiosk-Anmeldung",
      entityId: employeeId,
      summary: "Am Laden-Tablet angemeldet",
      actorUid: employeeId, sessionId: sid,
      deviceId: deviceId || null, requestId: ctx.requestId,
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
// HINWEIS (emulator-pending): diese Funktion persistiert die Praesenz
// (Kommen/Gehen) revisionssicher mit `source:'kiosk'` + `sessionId` UND erzeugt
// beim Ausstempeln einen abrechnungsrelevanten WorkEntry(submitted) inkl.
// ArbZG-Pflichtpause (siehe unten, direction === "out"). Der Compliance-Spiegel
// (Kopplung #2) und der Feld-Shape sind vor Produktiv-Deploy noch einmal gegen
// den Firestore-Emulator zu verifizieren (Kommen → Gehen → WorkEntry → Freigabe).
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

// Kiosk-Schichtbindung (ZV-2.1): löst die zum Stempelzeitpunkt passendste
// geplante Schicht des SESSION-Mitarbeiters auf — server-seitig via Admin SDK,
// weil das niedrig-privilegierte Geräte-Konto `shifts` nicht lesen darf (ein
// Client-Read scheiterte still). Best-effort: ein Fehler darf das Stempeln NIE
// verhindern (→ null). Query gegen Index shifts(userId, startTime); die Nähe-
// Auswahl ist der pure Helfer kioskShift.pickClosestShiftId (node-testbar).
async function resolveTodaysShiftId(orgId, employeeId) {
  try {
    const nowMs = Date.now();
    const from = Timestamp.fromMillis(nowMs - kioskShift.SHIFT_MATCH_WINDOW_MS);
    const to = Timestamp.fromMillis(nowMs + kioskShift.SHIFT_MATCH_WINDOW_MS);
    const snap = await organizationCollection(orgId, "shifts")
      .where("userId", "==", employeeId)
      .where("startTime", ">=", from)
      .where("startTime", "<", to)
      .orderBy("startTime")
      .get();
    if (snap.empty) return null;
    const candidates = snap.docs.map((doc) => ({
      id: doc.id,
      startMs: doc.data()?.startTime?.toMillis?.() ?? null,
    }));
    return kioskShift.pickClosestShiftId(candidates, nowMs);
  } catch (error) {
    logger.warn("kiosk_shift_resolve_failed", {
      event: "kiosk_shift_resolve_failed",
      orgId,
      employeeId,
      message: error && error.message,
    });
    return null;
  }
}

exports.kioskClockPunch = callable(
  "kioskClockPunch",
  {region: REGION, enforceAppCheck: true},
  async (request, ctx) => {
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
      // Uebergangsphase (PA-4.1): Alt-Buchungen mit zufaelliger ID zaehlen
      // weiter als offen (query-basiert) — sonst waere doppelt-offen moeglich.
      const existing = await findOpenClockEntry(orgId, employeeId);
      if (existing) {
        return {clockedIn: true, clockEntryId: existing.id};
      }
      // Schichtbindung (ZV-2.1): der Server löst die geplante Schicht des
      // Session-Mitarbeiters AUTHORITATIV auf (Admin SDK) — das Geräte-Konto
      // darf `shifts` nicht lesen. Ein explizit übergebener shiftId behält
      // Vorrang (Übergabe aus einem berechtigten Pfad); sonst server-seitig.
      const shiftId = stringOrNull(request.data?.shiftId) ||
        await resolveTodaysShiftId(orgId, employeeId);
      // PA-4.1: deterministische `{userId}-open`-ID + create() (schlaegt bei
      // Existenz ATOMAR fehl) — das fruehere read-then-write-Race ist damit zu.
      // Spiegel: FirestoreService.clockInOpen (App) + firestore.rules.
      const docRef = clockEntries.doc(`${employeeId}-open`);
      try {
        await docRef.create({
          orgId,
          userId: employeeId,
          siteId: stringOrNull(request.data?.siteId),
          siteName: stringOrNull(request.data?.siteName),
          // Geplante Schicht des Session-Mitarbeiters (ZV-2.1) — server-seitig
          // aufgelöst; die WorkEntry-Erzeugung erbt sie beim Ausstempeln als
          // sourceShiftId (Schicht-Completion-Hook).
          shiftId,
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
      } catch (error) {
        // ALREADY_EXISTS (gRPC-Code 6): parallel eingestempelt (App/anderes
        // Geraet) — idempotent als "bereits eingestempelt" beantworten.
        if (error && error.code === 6) {
          return {clockedIn: true, clockEntryId: docRef.id};
        }
        throw error;
      }
      await writeAudit({
        orgId, action: "created", entityType: "Stempelung",
        entityId: docRef.id, summary: "Eingestempelt (Kiosk-Tablet)",
        actorUid: employeeId, sessionId: sid,
        deviceId: session.deviceId || null, requestId: ctx.requestId,
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

      // PA-4.1: Lief die Buchung unter der deterministischen `{userId}-open`-ID,
      // wird sie transaktional unter eine endgueltige Auto-ID kopiert und das
      // open-Doc geloescht — sonst bliebe die open-ID mit status 'completed'
      // belegt und der naechste create() (Einstempeln) schluege fuer immer fehl.
      // Alt-Buchungen (zufaellige ID, Uebergangsphase) schliessen in place.
      let finalId = doc.id;
      if (doc.id === `${employeeId}-open`) {
        const closedRef = clockEntries.doc();
        finalId = closedRef.id;
        await db.runTransaction(async (tx) => {
          const open = await tx.get(doc.ref);
          if (!open.exists) {
            throw new HttpsError(
              "failed-precondition",
              "Keine laufende Buchung gefunden.",
            );
          }
          tx.set(closedRef, {
            ...open.data(),
            gehen: gehenTs,
            pauseMinuten: pause,
            nettoMinutes: netto,
            status: "completed",
            updatedAt: FieldValue.serverTimestamp(),
          });
          tx.delete(doc.ref);
        });
      } else {
        await doc.ref.set({
          gehen: gehenTs,
          pauseMinuten: pause,
          nettoMinutes: netto,
          status: "completed",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      // Abrechnungsrelevanten WorkEntry(submitted) erzeugen — best-effort, wie
      // der Client-Stempel (der Admin gibt „submitted" frei). Compliance wird
      // NICHT hart geprüft (Freigabe-Workflow fängt es), analog zum Client, der
      // die WorkEntry-Erzeugung ebenfalls nicht blockierend macht.
      // HINWEIS: emulator-pending — vor Produktiv-Deploy verifizieren.
      await organizationCollection(orgId, "workEntries").add({
        orgId,
        userId: employeeId,
        // M9/GB: auf Berliner Mittagszeit normalisiert (Dart-Spiegel:
        // WorkEntry.date = lokale 12:00) — der rohe Stempel-Zeitpunkt konnte
        // Tages-/Monatsauswertungen falsch gruppieren.
        date: Timestamp.fromDate(
          berlinNoonDate((data.kommen ?? gehenTs).toDate()),
        ),
        startTime: data.kommen ?? gehenTs,
        endTime: gehenTs,
        breakMinutes: pause,
        siteId: data.siteId ?? null,
        siteName: data.siteName ?? null,
        sourceShiftId: data.shiftId ?? null,
        category: "stempel",
        status: "submitted",
        // Rueckverweis auf die ENDGUELTIGE Doc-ID (nach PA-4.1-copy+delete).
        sourceClockEntryId: finalId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      await writeAudit({
        orgId, action: "created", entityType: "Stempelung",
        entityId: finalId,
        summary: `Ausgestempelt (Kiosk-Tablet, ${netto} min netto)`,
        actorUid: employeeId, sessionId: sid,
        deviceId: data.deviceId || null, requestId: ctx.requestId,
      });
      return {clockedIn: false, clockEntryId: finalId};
    }

    throw new HttpsError(
      "invalid-argument",
      "direction muss 'in', 'out' oder 'status' sein.",
    );
  },
);

// kioskSaveCashCount (Kassen-Modul M6-E): gehärtete Kassenzählung am Kiosk.
// Schreibt eine BLINDE CashCount (kein Soll/keine Differenz) als Geräte-Konto,
// aber autorisiert über die SERVER-geprüfte Session (statt Direkt-Write) — die
// zählende Person kommt authoritativ aus der Session, nicht vom Client
// (kein Spoofing von countedByLabel). Betrag/Notiz sind die einzigen
// Client-Eingaben; expectedCents/differenceCents bleiben null (blind, §7.3).
exports.kioskSaveCashCount = callable(
  "kioskSaveCashCount",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request); // Geraete-Konto
    const sid = stringOrNull(request.data?.sid);
    const session = await requireKioskSession(caller, sid);
    const orgId = session.orgId;
    const employeeId = session.employeeId;

    const countedCents = Number(request.data?.countedCents);
    if (!Number.isFinite(countedCents) || countedCents < 0) {
      throw new HttpsError(
        "invalid-argument", "countedCents muss eine Zahl >= 0 sein.",
      );
    }
    const businessDay = stringOrNull(request.data?.businessDay);
    if (!businessDay || !/^\d{4}-\d{2}-\d{2}$/.test(businessDay)) {
      throw new HttpsError(
        "invalid-argument", "businessDay muss 'YYYY-MM-DD' sein.",
      );
    }
    const note = stringOrNull(request.data?.note);
    const rawCr = Number(request.data?.cashRegisterId);
    const cashRegisterId = Number.isFinite(rawCr) && rawCr > 0
      ? Math.trunc(rawCr) : null;
    const siteId = stringOrNull(request.data?.siteId) ||
      stringOrNull(session.siteId);
    // M10/GB: die (client-gelieferte) siteId gegen die Standorte der Org
    // validieren — sonst laesst sich eine Kassenzaehlung einer beliebigen/
    // unbekannten Site zuordnen (Fehlattribution im Kassenbericht).
    if (siteId) {
      const siteSnap =
        await organizationCollection(orgId, "sites").doc(siteId).get();
      if (!siteSnap.exists) {
        throw new HttpsError(
          "invalid-argument",
          "Unbekannter Standort fuer die Kassenzaehlung.",
        );
      }
    }

    // Dritte-Hand-/Fremdgeld-Beträge (§8.7): streng OPTIONAL (alte Clients
    // senden den Key nicht), server-validiert, am Kiosk BLIND (expectedCents
    // hart null). Getrennt von der eigenen Kasse gespeichert.
    let thirdParty;
    try {
      thirdParty = parseThirdPartyAmounts(request.data?.thirdParty,
        {blind: true});
    } catch (error) {
      if (error && error.invalidArgument) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    // Anzeigename der Person AUTHORITATIV aus dem Server-Profil (nicht Client).
    // Fallback wie AppUserProfile.displayName: E-Mail-Präfix, wenn kein Name.
    let countedByLabel = null;
    try {
      const empSnap = await db.collection("users").doc(employeeId).get();
      const empData = empSnap.exists ? (empSnap.data() || {}) : {};
      const name = stringOrNull(empData.settings?.name ?? empData.name);
      const email = stringOrNull(empData.email);
      countedByLabel = name || (email ? email.split("@")[0] : null);
    } catch (error) {
      countedByLabel = null;
    }

    const ref = organizationCollection(orgId, "cashCounts").doc();
    await ref.set({
      orgId,
      siteId,
      cashRegisterId,
      businessDay,
      countedAt: FieldValue.serverTimestamp(),
      countedCents: Math.round(countedCents),
      // Blind: die Leitung sieht Soll/Differenz erst im Tagesabschluss.
      expectedCents: null,
      differenceCents: null,
      denominations: null,
      note,
      source: "kiosk",
      countedByLabel,
      // Harte Personen-Zuordnung (ZV-4.1): echte Mitarbeiter-uid aus der
      // server-geprüften Session — NICHT das Geräte-Konto (createdByUid) und
      // nicht vom Client setzbar.
      countedByUserId: employeeId,
      kioskSessionId: sid,
      thirdParty,
      createdByUid: caller.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {cashCountId: ref.id};
  },
);

// === Kiosk-Schichttausch (Kollegen-Schritt) ================================
// Der Session-Mitarbeiter sieht am Laden-Tablet die an ihn gerichteten, offenen
// Tauschanfragen und nimmt sie an / lehnt sie ab. Beide Callables laufen ALS der
// Mitarbeiter (Admin SDK), autorisiert ueber die Session-`sid` — das niedrig-
// privilegierte Geraete-Konto darf fremde `shiftSwapRequests` per Rules weder
// lesen noch aendern. Umbuchung/Bestaetigung macht weiterhin der Chef in der App.

// Serialisiert eine Tauschanfrage ins snake_case-Format, das der Dart-Client
// (ShiftSwapRequest.fromMap) erwartet — Datumsfelder als ISO-8601-Strings
// (Callable-Payload-Konvention, nicht Firestore-Timestamps ueber die Leitung).
// `tsToIso` (Timestamp→ISO) ist der gemeinsame Helfer weiter unten (gehoisted).
function serializeSwapForKiosk(id, d) {
  return {
    id,
    org_id: d.orgId || "",
    requester_uid: d.requesterUid || "",
    requester_name: d.requesterName || "",
    requester_shift_id: d.requesterShiftId || "",
    target_uid: d.targetUid || "",
    target_name: d.targetName || "",
    target_shift_id: d.targetShiftId || null,
    kind: d.kind || "exchange",
    status: d.status || "pending",
    reviewed_by_uid: d.reviewedByUid || null,
    overridden_compliance: d.overriddenCompliance === true,
    note: d.note || null,
    requester_shift_start: tsToIso(d.requesterShiftStart),
    target_shift_start: tsToIso(d.targetShiftStart),
    requester_shift_label: d.requesterShiftLabel || null,
    target_shift_label: d.targetShiftLabel || null,
    created_at: tsToIso(d.createdAt),
    updated_at: tsToIso(d.updatedAt),
  };
}

exports.getKioskIncomingSwaps = callable(
  "getKioskIncomingSwaps",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request); // Geraete-Konto
    const sid = stringOrNull(request.data?.sid);
    const session = await requireKioskSession(caller, sid);
    const orgId = session.orgId;
    const employeeId = session.employeeId;
    // Nur der Einzelfeld-Filter targetUid (Auto-Index) — der pending-Filter
    // laeuft in JS, damit KEIN Composite-Index noetig ist (die Menge je
    // Mitarbeiter ist klein).
    const snap = await organizationCollection(orgId, "shiftSwapRequests")
      .where("targetUid", "==", employeeId)
      .get();
    const requests = snap.docs
      .filter((doc) => (doc.data() || {}).status === "pending")
      .map((doc) => serializeSwapForKiosk(doc.id, doc.data() || {}))
      .sort((a, b) => String(b.created_at || "")
        .localeCompare(String(a.created_at || "")));
    return {requests};
  },
);

exports.kioskRespondSwap = callable(
  "kioskRespondSwap",
  {region: REGION, enforceAppCheck: true},
  async (request, ctx) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request); // Geraete-Konto
    const sid = stringOrNull(request.data?.sid);
    const requestId = stringOrNull(request.data?.requestId);
    const accept = request.data?.accept === true;
    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId fehlt.");
    }
    const session = await requireKioskSession(caller, sid);
    const orgId = session.orgId;
    const employeeId = session.employeeId;
    const ref = organizationCollection(orgId, "shiftSwapRequests")
      .doc(requestId);
    const nextStatus = accept ?
      "accepted_by_colleague" :
      "declined_by_colleague";
    let requesterName = "";
    // Transaktion: Ziel + Status atomar pruefen und umsetzen (verhindert die
    // Race mit einer parallelen Chef-Bestaetigung/Ruecknahme).
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Tauschanfrage nicht gefunden.");
      }
      const data = snap.data() || {};
      if (data.targetUid !== employeeId) {
        throw new HttpsError(
          "permission-denied",
          "Nur der angefragte Kollege kann annehmen oder ablehnen.",
        );
      }
      if (data.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "Diese Anfrage ist nicht mehr offen.",
        );
      }
      requesterName = data.requesterName || "";
      tx.update(ref, {
        status: nextStatus,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    await writeAudit({
      orgId,
      action: "updated",
      entityType: "Schichttausch",
      entityId: requestId,
      summary: accept ?
        `Tauschanfrage von ${requesterName} angenommen (Laden-Tablet)` :
        `Tauschanfrage von ${requesterName} abgelehnt (Laden-Tablet)`,
      actorUid: employeeId,
      sessionId: sid,
      deviceId: session.deviceId || null,
      requestId: ctx.requestId,
    });
    return {ok: true, status: nextStatus};
  },
);

// === Passwortmanager (§9) ===================================================
// Serverseitige Envelope-Verschlüsselung (Cloud KMS wrappt den pro-Eintrag-DEK).
// Der Klartext verlässt den Prozess NUR über den autorisierten + auditierten
// revealPasswordSecret-Callable. Alle Callables setzen enforceAppCheck EXPLIZIT
// (App Check ≠ Autorisierung). Config über Env: PASSWORD_KMS_KEY (KMS-Key-
// Ressourcenname), PASSWORD_MANAGER_TEAMLEAD ('true' schaltet Filialleiter frei).
const PASSWORD_REVEAL_MAX = 5; // pro Minuten-Fenster je Nutzer
const PASSWORD_REVEAL_WINDOW_MS = 60 * 1000;
const PASSWORD_REAUTH_TTL_MS = 60 * 1000;

function passwordTeamleadEnabled() {
  return process.env.PASSWORD_MANAGER_TEAMLEAD === "true";
}

function passwordKeyWrapper() {
  const keyName = process.env.PASSWORD_KMS_KEY;
  if (!keyName) {
    throw new HttpsError(
      "failed-precondition",
      "Passwortmanager ist nicht konfiguriert (PASSWORD_KMS_KEY fehlt).",
    );
  }
  return new passwordCrypto.KmsKeyWrapper(keyName);
}

function tsToIso(value) {
  if (value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  return null;
}

async function loadCallerSiteIds(orgId, uid) {
  try {
    const snap = await organizationCollection(orgId, "employeeSiteAssignments")
      .where("userId", "==", uid).get();
    const ids = [];
    snap.forEach((doc) => {
      const s = doc.data()?.siteId;
      if (s) ids.push(String(s));
    });
    return ids;
  } catch (error) {
    return [];
  }
}

async function loadUserLabel(uid) {
  try {
    const snap = await db.collection("users").doc(uid).get();
    const data = snap.exists ? (snap.data() || {}) : {};
    const name = stringOrNull(data.settings?.name ?? data.name);
    const email = stringOrNull(data.email);
    return name || (email ? email.split("@")[0] : "");
  } catch (error) {
    return "";
  }
}

// Materialisiert audienceSiteIds -> uids (Query-Optimierung für die Liste; die
// Reveal-Autorität rechnet dennoch LIVE, §11). Firestore 'in' <= 10 Werte.
async function materializeAudienceUids(orgId, siteIds) {
  const uids = new Set();
  const chunks = [];
  for (let i = 0; i < siteIds.length; i += 10) {
    chunks.push(siteIds.slice(i, i + 10));
  }
  for (const chunk of chunks) {
    if (chunk.length === 0) continue;
    const snap = await organizationCollection(orgId, "employeeSiteAssignments")
      .where("siteId", "in", chunk).get();
    snap.forEach((doc) => {
      const u = doc.data()?.userId;
      if (u) uids.add(String(u));
    });
  }
  return [...uids];
}

// Metadaten-Projektion für den Client (NIE Secret/keyVersion/strengthMeta).
function projectEntry(id, d) {
  return {
    id,
    orgId: d.orgId ?? null,
    title: d.title ?? "",
    category: d.category ?? "other",
    siteId: d.siteId ?? null,
    siteName: d.siteName ?? null,
    ownerUid: d.ownerUid ?? "",
    ownerLabel: d.ownerLabel ?? "",
    scope: d.scope ?? "personal",
    audienceUids: d.audienceUids ?? [],
    audienceRoles: d.audienceRoles ?? [],
    audienceSiteIds: d.audienceSiteIds ?? [],
    url: d.url ?? null,
    hasSecret: d.hasSecret === true,
    createdByUid: d.createdByUid ?? "",
    updatedByUid: d.updatedByUid ?? "",
    createdAt: tsToIso(d.createdAt),
    updatedAt: tsToIso(d.updatedAt),
    lastRotatedAt: tsToIso(d.lastRotatedAt),
  };
}

// Fail-closed Audit-Anker für Reveal/Copy (KEIN best-effort Sink) — wirft, wenn
// der Schreibvorgang scheitert ("no reveal without record").
async function writePasswordAccessLog(orgId, data) {
  await organizationCollection(orgId, "passwordAccessLog").add({
    orgId,
    ...data,
    at: FieldValue.serverTimestamp(),
  });
}

// listPasswordEntries: server-gefilterte Metadaten-Liste (Ersatz für einen
// Client-Stream, B1). Liefert nur sichtbare Einträge, nie Sensitiva.
exports.listPasswordEntries = callable(
  "listPasswordEntries",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    const orgId = stringOrNull(request.data?.orgId) || caller.orgId;
    assertSameOrg(caller, orgId);
    const callerSiteIds = caller.isAdmin
      ? [] : await loadCallerSiteIds(orgId, caller.uid);
    const snap = await organizationCollection(orgId, "passwordEntries").get();
    const entries = [];
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (passwordAccess.canViewEntry(d, caller, callerSiteIds)) {
        entries.push(projectEntry(doc.id, d));
      }
    });
    return {entries};
  },
);

// upsertPasswordEntry: Metadaten + optional Klartext-Secret. Kein Direkt-Write
// (Rules verbieten ihn) — dies ist der einzige Schreibpfad.
exports.upsertPasswordEntry = callable(
  "upsertPasswordEntry",
  {region: REGION, enforceAppCheck: true},
  async (request, {requestId}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    let entry;
    try {
      entry = passwordAccess.parseEntryPayload(request.data?.entry);
    } catch (error) {
      if (error && error.invalidArgument) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }
    const orgId = entry.orgId || caller.orgId;
    assertSameOrg(caller, orgId);

    const entryId = stringOrNull(request.data?.entry_id);
    const col = organizationCollection(orgId, "passwordEntries");
    const callerSiteIds = caller.isAdmin
      ? [] : await loadCallerSiteIds(orgId, caller.uid);
    const opts = {teamleadEnabled: passwordTeamleadEnabled()};

    let existing = null;
    let ownerUid = caller.uid;
    let isNew = true;
    if (entryId) {
      const snap = await col.doc(entryId).get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Eintrag nicht gefunden.");
      }
      existing = snap.data() || {};
      if (existing.orgId && existing.orgId !== orgId) {
        throw new HttpsError("permission-denied", "Falsche Organisation.");
      }
      ownerUid = existing.ownerUid || caller.uid;
      isNew = false;
      // Autorisierung gegen den BESTEHENDEN Zustand.
      if (!passwordAccess.canManageEntry(existing, caller, callerSiteIds, opts)) {
        throw new HttpsError(
          "permission-denied", "Keine Berechtigung für diesen Eintrag.");
      }
    }
    // Autorisierung gegen den NEUEN Zustand (Owner fixiert auf sich/Bestand).
    if (!passwordAccess.canManageEntry(
      {...entry, ownerUid}, caller, callerSiteIds, opts)) {
      throw new HttpsError(
        "permission-denied", "Keine Berechtigung für diesen Eintrag.");
    }

    const docRef = entryId ? col.doc(entryId) : col.doc();
    const finalId = docRef.id;

    // audienceSiteIds -> audienceUids materialisieren (nur Query-Optimierung).
    let audienceUids = entry.audienceUids;
    if (entry.scope === "shared" && entry.audienceSiteIds.length > 0) {
      const materialized =
        await materializeAudienceUids(orgId, entry.audienceSiteIds);
      audienceUids = [...new Set([...audienceUids, ...materialized])];
    }

    // Secret verschlüsseln (nur wenn Klartext geliefert wurde).
    const secret = passwordAccess.parseSecretPayload(request.data || {});
    const hasNewSecret = secret.p.length > 0;
    let hasSecret = existing?.hasSecret === true;
    if (hasNewSecret) {
      const record = await passwordCrypto.encryptSecret(secret, {
        orgId, entryId: finalId, keyWrapper: passwordKeyWrapper(),
      });
      await organizationCollection(orgId, "passwordSecrets").doc(finalId).set({
        orgId,
        entryId: finalId,
        ...record,
        updatedAt: FieldValue.serverTimestamp(),
        updatedByUid: caller.uid,
      });
      hasSecret = true;
    }

    const ownerLabel = isNew
      ? await loadUserLabel(ownerUid)
      : (existing.ownerLabel || await loadUserLabel(ownerUid));

    const data = {
      orgId,
      title: entry.title,
      category: entry.category,
      siteId: entry.siteId,
      siteName: entry.siteName,
      ownerUid,
      ownerLabel,
      scope: entry.scope,
      audienceUids,
      audienceRoles: entry.audienceRoles,
      audienceSiteIds: entry.audienceSiteIds,
      url: entry.url,
      hasSecret,
      updatedAt: FieldValue.serverTimestamp(),
      updatedByUid: caller.uid,
    };
    if (isNew) {
      data.createdAt = FieldValue.serverTimestamp();
      data.createdByUid = caller.uid;
    } else {
      data.createdAt = existing.createdAt || FieldValue.serverTimestamp();
      data.createdByUid = existing.createdByUid || caller.uid;
    }
    if (hasNewSecret) {
      data.lastRotatedAt = FieldValue.serverTimestamp();
    } else if (existing?.lastRotatedAt) {
      data.lastRotatedAt = existing.lastRotatedAt;
    }

    await docRef.set(data, {merge: false});

    await writeAudit({
      orgId,
      action: isNew ? "created" : "updated",
      entityType: "password",
      entityId: finalId,
      summary: `Passwort „${entry.title}" ${isNew ? "angelegt" : "geändert"}`,
      actorUid: caller.uid,
      requestId,
    });
    return {entry_id: finalId};
  },
);

// deletePasswordEntry: löscht Metadaten + Secret atomar.
exports.deletePasswordEntry = callable(
  "deletePasswordEntry",
  {region: REGION, enforceAppCheck: true},
  async (request, {requestId}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    const orgId = stringOrNull(request.data?.org_id) || caller.orgId;
    assertSameOrg(caller, orgId);
    const entryId = stringOrNull(request.data?.entry_id);
    if (!entryId) {
      throw new HttpsError("invalid-argument", "entry_id fehlt.");
    }
    const col = organizationCollection(orgId, "passwordEntries");
    const snap = await col.doc(entryId).get();
    if (!snap.exists) return {ok: true};
    const existing = snap.data() || {};
    const callerSiteIds = caller.isAdmin
      ? [] : await loadCallerSiteIds(orgId, caller.uid);
    if (!passwordAccess.canManageEntry(existing, caller, callerSiteIds,
      {teamleadEnabled: passwordTeamleadEnabled()})) {
      throw new HttpsError(
        "permission-denied", "Keine Berechtigung für diesen Eintrag.");
    }
    const batch = db.batch();
    batch.delete(col.doc(entryId));
    batch.delete(organizationCollection(orgId, "passwordSecrets").doc(entryId));
    await batch.commit();
    await writeAudit({
      orgId,
      action: "deleted",
      entityType: "password",
      entityId: entryId,
      summary: `Passwort „${existing.title || entryId}" gelöscht`,
      actorUid: caller.uid,
      requestId,
    });
    return {ok: true};
  },
);

// beginPasswordReauth: server-signierten Einmal-Nonce ausstellen (TTL 60s),
// Pflicht-Vorstufe für revealPasswordSecret (harte Reauth, Default).
exports.beginPasswordReauth = callable(
  "beginPasswordReauth",
  {region: REGION, enforceAppCheck: true},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    const orgId = stringOrNull(request.data?.org_id) || caller.orgId;
    assertSameOrg(caller, orgId);
    const token = crypto.randomBytes(24).toString("base64url");
    const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
    await organizationCollection(orgId, "passwordReauth").doc(caller.uid).set({
      tokenHash,
      createdAt: FieldValue.serverTimestamp(),
      expiresAtMs: Date.now() + PASSWORD_REAUTH_TTL_MS,
    });
    return {reauth_token: token};
  },
);

async function verifyReauth(orgId, uid, token) {
  if (!token) return false;
  const ref = organizationCollection(orgId, "passwordReauth").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const d = snap.data() || {};
  const expected = String(d.tokenHash || "");
  const given = crypto.createHash("sha256").update(token).digest("hex");
  const ok = expected.length === given.length &&
    crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(given)) &&
    Number(d.expiresAtMs || 0) > Date.now();
  // Einmal-Verwendung: Nonce immer verbrauchen.
  await ref.delete().catch(() => {});
  return ok;
}

async function enforceRevealRateLimit(orgId, uid) {
  const ref = organizationCollection(orgId, "passwordRevealLimits").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const d = snap.exists ? (snap.data() || {}) : {};
    let count = Number(d.count || 0);
    let windowStart = Number(d.windowStartMs || 0);
    if (now - windowStart > PASSWORD_REVEAL_WINDOW_MS) {
      windowStart = now;
      count = 0;
    }
    if (count >= PASSWORD_REVEAL_MAX) {
      throw new HttpsError(
        "resource-exhausted", "Zu viele Zugriffe – bitte kurz warten.");
    }
    tx.set(ref, {count: count + 1, windowStartMs: windowStart});
  });
}

// revealPasswordSecret: EINZIGER Klartext-Ausgabepfad. Harte Reauth + Live-
// Sichtbarkeit + Rate-Limit + fail-closed Audit VOR der Entschlüsselung (B4).
exports.revealPasswordSecret = callable(
  "revealPasswordSecret",
  {region: REGION, enforceAppCheck: true},
  async (request, {requestId}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    const orgId = stringOrNull(request.data?.org_id) || caller.orgId;
    assertSameOrg(caller, orgId);
    const entryId = stringOrNull(request.data?.entry_id);
    if (!entryId) {
      throw new HttpsError("invalid-argument", "entry_id fehlt.");
    }
    // Harte Reauth (server-verifizierter Einmal-Nonce).
    const reauthOk = await verifyReauth(
      orgId, caller.uid, stringOrNull(request.data?.reauth_token));
    if (!reauthOk) {
      throw new HttpsError(
        "unauthenticated", "Sicherheitsbestätigung erforderlich.");
    }
    const snap =
      await organizationCollection(orgId, "passwordEntries").doc(entryId).get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Eintrag nicht gefunden.");
    }
    const d = snap.data() || {};
    const callerSiteIds = caller.isAdmin
      ? [] : await loadCallerSiteIds(orgId, caller.uid);
    if (!passwordAccess.canViewEntry(d, caller, callerSiteIds)) {
      throw new HttpsError(
        "permission-denied", "Keine Berechtigung für dieses Passwort.");
    }
    await enforceRevealRateLimit(orgId, caller.uid);

    // Fail-closed: Audit VOR der Entschlüsselung (propagiert bei Fehler).
    const reason = stringOrNull(request.data?.reason);
    const actorLabel = await loadUserLabel(caller.uid);
    await writePasswordAccessLog(orgId, {
      action: "reveal_requested",
      entryId,
      entryTitle: d.title || "",
      category: d.category || null,
      siteId: d.siteId || null,
      siteName: d.siteName || null,
      actorUid: caller.uid,
      actorLabel,
      reason,
      requestId,
    });

    const secretSnap =
      await organizationCollection(orgId, "passwordSecrets").doc(entryId).get();
    if (!secretSnap.exists) {
      throw new HttpsError("not-found", "Kein Passwort hinterlegt.");
    }
    let plain;
    try {
      plain = await passwordCrypto.decryptSecret(secretSnap.data() || {}, {
        orgId, entryId, keyWrapper: passwordKeyWrapper(),
      });
    } catch (error) {
      logger.error("password_decrypt_failed", {requestId, entryId});
      throw new HttpsError(
        "internal", "Passwort konnte nicht entschlüsselt werden.");
    }
    await writePasswordAccessLog(orgId, {
      action: "revealed",
      entryId,
      entryTitle: d.title || "",
      category: d.category || null,
      siteId: d.siteId || null,
      siteName: d.siteName || null,
      actorUid: caller.uid,
      actorLabel,
      reason,
      requestId,
    });
    return {
      username: plain.u || "",
      password: plain.p || "",
      notes: plain.n || "",
    };
  },
);

// logPasswordCopy: Kopieren protokollieren (best-effort clientseitig, Server-
// Log fälschungssicher). Ehrliche Grenze: Reveal ist der Audit-Anker.
exports.logPasswordCopy = callable(
  "logPasswordCopy",
  {region: REGION, enforceAppCheck: true},
  async (request, {requestId}) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    const orgId = stringOrNull(request.data?.org_id) || caller.orgId;
    assertSameOrg(caller, orgId);
    const entryId = stringOrNull(request.data?.entry_id);
    if (!entryId) {
      throw new HttpsError("invalid-argument", "entry_id fehlt.");
    }
    const snap =
      await organizationCollection(orgId, "passwordEntries").doc(entryId).get();
    if (!snap.exists) return {ok: true};
    const d = snap.data() || {};
    const callerSiteIds = caller.isAdmin
      ? [] : await loadCallerSiteIds(orgId, caller.uid);
    if (!passwordAccess.canViewEntry(d, caller, callerSiteIds)) {
      throw new HttpsError("permission-denied", "Keine Berechtigung.");
    }
    const field = stringOrNull(request.data?.field);
    await writePasswordAccessLog(orgId, {
      action: "copied",
      entryId,
      entryTitle: d.title || "",
      category: d.category || null,
      siteId: d.siteId || null,
      field: (field === "username" || field === "password") ? field : null,
      actorUid: caller.uid,
      actorLabel: await loadUserLabel(caller.uid),
      requestId,
    });
    return {ok: true};
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
    // Kiosk-Geraetekonto (Arbeitsmodus/Laden-Tablet, PA-0.1): ohne explizite
    // Overrides bekommt es KEINE Rechte — sonst faellt es in den employee-
    // default (canEditTimeEntries:true) und kaeme z. B. durch
    // assertTimeEntryEditor. Spiegelt den Rules-seitigen isKiosk()-Deny.
    case "kiosk":
      return {
        canViewSchedule: false,
        canEditSchedule: false,
        canViewTimeTracking: false,
        canEditTimeEntries: false,
        canViewReports: false,
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

// K3 (Sicherheits-Audit 2026-07): erzwingt die gegen den Caller geprüfte Org
// auf JEDER Schicht — parseShift wuerde sonst ein client-geliefertes org_id
// uebernehmen und der Admin-SDK-Write (umgeht Rules) landete in einer FREMDEN
// Org. Muster wie im Work-Entry-Pfad (assertSameOrg je Zeile).
function enforceShiftOrg(shifts, orgId) {
  return shifts.map((shift) => ({...shift, orgId}));
}

// K3: orgId kommt explizit vom Callable (gegen den Caller geprueft) — NIE aus
// shifts[0].orgId ableiten, sonst entscheidet ein manipulierter Payload ueber
// die Ziel-Org des Admin-SDK-Writes.
async function writeShiftBatch({callerUid, orgId, shifts}) {
  const collection = organizationCollection(orgId || shifts[0].orgId, "shifts");
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
      "Für geplante Schichten ist ein Standort Pflicht.",
    ));
  }

  if (!shift.isUnassigned && !assignment) {
    violations.push({
      code: "site_assignment_missing",
      severity: "blocking",
      message: `${shift.employeeName} ist dem gewählten Standort nicht zugeordnet.`,
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
  // Split-Shift-Guard (Kopplung #2, Audit-H7): Der Dart-Spiegel prueft
  // _shouldEnforceRestGap auch im SCHICHT-Pfad (compliance_service.dart:721) —
  // ohne den Guard hier blockte der Server legitime geteilte Dienste
  // (08-12 + 14-18), die die Client-Vorschau gruen zeigte. Fuer den
  // Work-Entry-Pfad (prueft vor dem Aufruf) ist der Guard idempotent.
  if (!shouldEnforceRestGap(earlier.startTime, earlier.endTime, later.startTime)) {
    return [];
  }
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

// Formel in beiden Spiegeln identisch (compliance_service.dart _shiftWorkedMinutes/
// _entryWorkedMinutes): Brutto-Minuten runden, Pause separat runden, dann
// subtrahieren und auf >= 0 klemmen — sonst driftet der Wert bei fraktionalen
// breakMinutes/Sekundenanteilen um 1 Minute (Kopplung #2).
function workedMinutesFromShift(shift) {
  const gross = Math.round((shift.endTime - shift.startTime) / 60000);
  return Math.max(0, gross - Math.round(Number(shift.breakMinutes || 0)));
}

function workedMinutesFromEntry(entry) {
  const gross = Math.round((entry.endTime - entry.startTime) / 60000);
  return Math.max(0, gross - Math.round(Number(entry.breakMinutes || 0)));
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

// ── Zeitwirtschaft-Freigabe-Workflow (plan/zeit-schichtbindung-freigabe.md, Z6)
// Serverseitige Durchsetzung auf dem Callable-Pfad, spiegelbildlich zu den Rules
// (Z5): Nicht-Admins reichen nur ein (nie selbst genehmigen); nur ein Freigeber
// (canManageShifts, nicht der eigene Eintrag, Zielperson kein Admin) genehmigt/
// lehnt ab mit server-gesetzter Genehmiger-Identitaet + Server-Zeitstempel;
// Korrektur eines genehmigten Eintrags erzwingt einen Grund (Re-Approval, Z4).

function isReviewer(caller) {
  return Boolean(
    caller.isAdmin || (caller.permissions && caller.permissions.canEditSchedule),
  );
}

// PURE (ohne IO, node-testbar). Liefert die durchzusetzende Freigabe-Semantik:
// {ok:true, status, approvedByUid, approvedAtServer, clearApprovedAt} oder
// {ok:false, code, message}. `targetIsAdmin`: true/false, oder null wenn das
// Zielprofil fehlt (dann kein Fremd-Approval — fail-closed).
function resolveWorkEntryApproval(
  {caller, entry, existingStatus, materialChanged, targetIsAdmin},
) {
  const isOwn = caller.uid === entry.userId;
  if (isOwn) {
    if (caller.isAdmin) {
      // Admins sind laut Freigabe-Konzept ausgenommen.
      return {
        ok: true,
        status: normalizeWorkEntryStatus(entry.status),
        approvedByUid: entry.approvedByUid || null,
        approvedAtServer: false,
        clearApprovedAt: false,
      };
    }
    // Nicht-Admin Eigen-Erfassung/-Korrektur: immer submitted, Freigabe leeren.
    if (
      existingStatus === "approved" &&
      materialChanged &&
      !(entry.correctionReason && String(entry.correctionReason).trim())
    ) {
      return {
        ok: false,
        code: "failed-precondition",
        message:
          "Fuer die Korrektur eines genehmigten Zeiteintrags ist ein Grund erforderlich.",
      };
    }
    return {
      ok: true,
      status: "submitted",
      approvedByUid: null,
      approvedAtServer: false,
      clearApprovedAt: true,
    };
  }
  // Fremd-Eintrag: nur Freigeber, Zielperson kein Admin.
  if (!isReviewer(caller)) {
    return {
      ok: false,
      code: "permission-denied",
      message: "Nur Freigeber duerfen Zeiteintraege anderer Mitarbeiter bearbeiten.",
    };
  }
  if (targetIsAdmin === null || targetIsAdmin === true) {
    return {
      ok: false,
      code: "permission-denied",
      message: "Fuer diese Zielperson ist keine Fremd-Freigabe zulaessig.",
    };
  }
  const status = normalizeWorkEntryStatus(entry.status);
  if (status === "approved" || status === "rejected") {
    return {
      ok: true,
      status,
      approvedByUid: caller.uid,
      approvedAtServer: true,
      clearApprovedAt: false,
    };
  }
  return {
    ok: true,
    status,
    approvedByUid: null,
    approvedAtServer: false,
    clearApprovedAt: true,
  };
}

async function loadTargetIsAdmin(userId) {
  const snap = await db.collection("users").doc(userId).get();
  if (!snap.exists) {
    return null;
  }
  return normalizeRole((snap.data() || {}).role) === "admin";
}

// Wendet die Freigabe-Entscheidung auf die Firestore-Schreibmap an: setzt
// status/approvedByUid, Server-Zeitstempel bzw. geleerte Freigabe, und leitet
// `date` aus `startTime` ab (schliesst das Direct-Write-Loch „date allein
// verschieben" auch auf dem Callable-Pfad).
function applyApprovalDecision(fireDoc, decision, entry) {
  fireDoc.status = decision.status;
  fireDoc.approvedByUid = decision.approvedByUid;
  if (decision.approvedAtServer) {
    fireDoc.approvedAt = FieldValue.serverTimestamp();
  } else if (decision.clearApprovedAt) {
    fireDoc.approvedAt = null;
  }
  fireDoc.date = Timestamp.fromDate(normalizeDate(entry.startTime));
  return fireDoc;
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
    // Plan-Metadatum "geplante Überstunden" in Minuten (siehe lib/models/shift.dart).
    overtimeMinutes: asInteger(map.overtime_minutes),
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
    overtimeMinutes: asInteger(shift.overtimeMinutes),
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
    overtimeMinutes: asInteger(data.overtimeMinutes),
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

async function writeWorkEntryBatch({caller, entries}) {
  const collection = organizationCollection(entries[0].orgId, "workEntries");
  const refs = entries.map((entry) =>
    collection.doc(entry.id || buildWorkEntryDocumentId(entry)),
  );
  const snapshots = refs.length > 0 ? await db.getAll(...refs) : [];
  const existingById = new Map(
    snapshots.map((snapshot) => [snapshot.id, snapshot]),
  );

  // Ziel-Admin-Status je fremder Zielperson einmalig laden (fail-closed).
  const foreignTargets = [
    ...new Set(
      entries
        .filter((entry) => entry.userId !== caller.uid)
        .map((entry) => entry.userId),
    ),
  ];
  const targetAdminById = new Map();
  for (const uid of foreignTargets) {
    targetAdminById.set(uid, await loadTargetIsAdmin(uid));
  }

  const batch = db.batch();
  const savedIds = [];
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    const docRef = refs[index];
    const existing = existingById.get(docRef.id);
    const existingData = existing && existing.exists ? existing.data() : null;
    // Z6: Freigabe-Semantik je Eintrag serverseitig durchsetzen.
    const decision = resolveWorkEntryApproval({
      caller,
      entry,
      existingStatus: existingData ? stringOrEmpty(existingData.status) : null,
      materialChanged: existingData
        ? correctionReasonRequired(existingData, entry)
        : false,
      targetIsAdmin: entry.userId === caller.uid
        ? false
        : targetAdminById.get(entry.userId),
    });
    if (!decision.ok) {
      throw new HttpsError(decision.code, decision.message);
    }
    const fireDoc = applyApprovalDecision(
      toFirestoreWorkEntry(entry, caller.uid),
      decision,
      entry,
    );
    savedIds.push(docRef.id);
    batch.set(
      docRef,
      {
        ...fireDoc,
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

// M9/GB: WorkEntry.date ist im Dart-Client auf LOKALE Mittagszeit normalisiert
// (12:00, Europe/Berlin). Der Kiosk-Server-Pfad schrieb den rohen
// Stempel-Zeitpunkt — Nachtschichten/Zeitzonen konnten dadurch im falschen
// Kalendertag/Monat landen. Cloud Functions laufen in UTC, daher wird der
// Berliner Kalendertag ueber Intl bestimmt und 12:00 Berlin DST-korrekt
// (10:00Z im Sommer, 11:00Z im Winter) ermittelt. Pur & node-testbar.
function berlinNoonDate(value) {
  const day = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric", month: "2-digit", day: "2-digit",
  }).format(value); // "YYYY-MM-DD"
  for (const utcHour of [10, 11]) {
    const candidate =
      new Date(`${day}T${String(utcHour).padStart(2, "0")}:00:00Z`);
    // parseInt statt Number: de-DE formatiert "12 Uhr" (Suffix).
    const berlinHour = parseInt(new Intl.DateTimeFormat("de-DE", {
      timeZone: "Europe/Berlin", hour: "2-digit", hour12: false,
    }).format(candidate), 10);
    if (berlinHour === 12) {
      return candidate;
    }
  }
  return new Date(`${day}T11:00:00Z`);
}

// Gesetzliches Nachtfenster fuer Jugend- (JArbSchG § 14: 20:00–06:00) und
// Mutterschutz (MuSchG § 5: ab 20:00). Bewusst hartkodiert und UNABHAENGIG vom
// konfigurierbaren ruleSet.nightWindowStart/EndMinutes (allgemeine
// Nachtarbeits-Definition nach ArbZG): gesetzliche Minima sind per
// Org-Konfiguration nicht lockerbar. Spiegel: _overlapsNightWindow in
// lib/services/compliance_service.dart.
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
//  - Idempotent: deterministische Doc-ID je (Standort, Beleg, Position) ->
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
    // H7/GB: ueber ALLE Organisationen paginieren — das fruehere harte
    // limit(50) haette ab Org 51 still keinen naechtlichen Sync mehr gefahren.
    const orgIds = [];
    let orgCursor = null;
    for (;;) {
      let query = db.collection("organizations")
        .orderBy(FieldPath.documentId())
        .limit(200);
      if (orgCursor != null) {
        query = query.startAfter(orgCursor);
      }
      const orgsSnap = await query.get();
      if (orgsSnap.empty) {
        break;
      }
      for (const orgDoc of orgsSnap.docs) {
        orgIds.push(orgDoc.id);
      }
      orgCursor = orgsSnap.docs[orgsSnap.docs.length - 1].id;
      if (orgsSnap.docs.length < 200) {
        break;
      }
    }
    for (const orgId of orgIds) {
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

// Backfill/Reparatur der posDailyStats (M5, §3.3). Re-aggregiert die
// posDailyStats fuer einen Zeitraum aus den bestehenden posReceipts —
// KEIN OktoPOS-Call (nur Firestore), daher ohne Secret. Admin-only, same-org.
// `from`/`until` als 'YYYY-MM-DD' oder ISO; Default: letzte ~370 Tage,
// hart auf 400 Tage gedeckelt (Read-Kosten-Schutz). `siteId` optional — ohne
// ihn alle in config/oktoposSync konfigurierten Standorte.
exports.rebuildPosDailyStats = callable(
  "rebuildPosDailyStats",
  // 512MiB: der Backfill kann bis zu 400 Tage posReceipts je Standort in einen
  // In-Memory-Array lesen (OOM-Schutz bei umsatzstarken Laeden).
  {region: REGION, timeoutSeconds: 300, memory: "512MiB"},
  async (request) => {
    assertSupportedVersion(request);
    const caller = await loadCallerProfile(request);
    assertAdmin(caller);
    const orgId = requiredString(request.data?.orgId, "orgId");
    assertSameOrg(caller, orgId);

    const until = parseOktoposDate(stringOrNull(request.data?.until)) ||
      new Date();
    let from = parseOktoposDate(stringOrNull(request.data?.from)) ||
      daysAgo(until, 370);
    // Range hart deckeln (Schutz gegen versehentliche Riesen-Reads).
    const maxFrom = daysAgo(until, 400);
    if (from < maxFrom) from = maxFrom;
    if (from > until) {
      throw new HttpsError("invalid-argument", "from liegt nach until.");
    }

    const explicitSite = stringOrNull(request.data?.siteId);
    let siteIds;
    if (explicitSite) {
      siteIds = [explicitSite];
    } else {
      const config = await loadOktoposConfig(orgId);
      const sites = isPlainObject(config?.sites) ? config.sites : {};
      siteIds = Object.keys(sites);
      if (siteIds.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "Keine Standorte in config/oktoposSync — bitte siteId angeben.",
        );
      }
    }

    const includeVat = await loadPurchasePricesIncludeVat(orgId);
    let daysWritten = 0;
    for (const siteId of siteIds) {
      const lookups = await loadProductLookups(orgId, siteId);
      daysWritten += await rebuildPosDailyStatsForRange(
        orgId, siteId, from, until, [...lookups.byId.values()], includeVat,
      );
    }
    return {
      orgId,
      siteIds,
      from: toOktoposDateTime(from),
      until: toOktoposDateTime(until),
      daysWritten,
    };
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
// H2 (Sicherheits-Audit 2026-07): KEIN `*`/`default`-Fallback mehr — der
// lieferte jeder beliebigen (auch fremden/unbekannten) siteId einen echten
// Key. In der JSON-Form muss jeder Standort explizit eingetragen sein.
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
    const key = parsed?.[siteId];
    if (!stringOrNull(key)) {
      throw new HttpsError(
        "failed-precondition",
        `Kein OktoPOS-API-Key fuer Standort ${siteId} in OKTOPOS_API_KEYS ` +
          "(jeder Standort braucht einen expliziten Eintrag).",
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
  // K4: zentrale baseUrl-Pruefung (https + Host-Allowlist gegen SSRF/
  // Key-Exfiltration); H2: siteId muss in der Org-Config existieren, BEVOR
  // ein Key aufgeloest wird.
  const baseUrl = resolveOktoposBaseUrl(config);
  assertOktoposSiteConfigured(config, siteId);
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
    statsDaysWritten: 0,
    truncated: false,
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
    let sawLastPageField = false;
    let pageTransactionCount = 0;
    const pending = [];
    const pendingReceipts = [];
    for (const wrapper of wrappers) {
      // H4: `lastPage` nur werten, wenn die API es wirklich liefert — der
      // fruehere Fallback auf `page` beendete die Schleife sonst still nach
      // der ersten Seite.
      const rawLastPage = asInteger(wrapper.lastPage, 0);
      if (rawLastPage > 0) {
        sawLastPageField = true;
        pageLastPage = Math.max(pageLastPage, rawLastPage);
      }
      pageTransactionCount += asArray(wrapper.transactions).length;
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
            receiptId: buildOktoposReceiptId(siteId, ref),
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
        let lineIndex = -1;
        for (const item of asArray(tx?.items)) {
          lineIndex += 1;
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
              siteId, ref, oktoposLineDiscriminator(item, lineIndex),
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
    // H4: liefert die API kein lastPage, weiterblaettern solange volle Seiten
    // kommen — sonst blieben alle Folgeseiten dauerhaft ungelesen.
    if (!sawLastPageField && pageTransactionCount >= pageSize) {
      pageLastPage = Math.max(pageLastPage, page + 1);
      logger.warn("oktopos_pagination_field_missing", {
        event: "oktopos_pagination_field_missing",
        fn, requestId, orgId, siteId, page,
      });
    }
    lastPage = pageLastPage;
    page += 1;
  } while (page <= lastPage && page <= OKTOPOS_MAX_PAGES);

  // H5: Endete die Schleife am Seiten-Cap, obwohl weitere Seiten gemeldet
  // waren, duerfen die ungelesenen Transaktionen NICHT durch einen
  // fortgeschriebenen Cursor dauerhaft verloren gehen -> Cursor stehen lassen
  // (der naechste Lauf zieht idempotent nach) + deutlich loggen.
  if (page <= lastPage) {
    result.truncated = true;
    logger.error("oktopos_pages_cap_reached", {
      event: "oktopos_pages_cap_reached",
      fn, requestId, orgId, siteId,
      maxPages: OKTOPOS_MAX_PAGES,
      reportedLastPage: lastPage,
    });
  }

  // Cursor fortschreiben (nicht im dryRun, nicht bei Cap-Abbruch).
  if (!dryRun && maxBusinessDay && !result.truncated) {
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

  // posDailyStats fortschreiben (M5, §3.3): GENAU EINMAL nach der Paging-Schleife
  // (nicht je Seite), nur `!dryRun`. Re-aggregiert das Sync-Fenster [from..until]
  // aus den JUST geschriebenen posReceipts (Ganztags-Neuaggregation ueber die
  // transactionDate-Range) — best-effort: ein Stats-Fehler darf den Sync nicht
  // scheitern lassen (die Belege/Bewegungen sind bereits sicher persistiert).
  if (!dryRun && result.receiptsPersisted > 0) {
    try {
      const includeVat = await loadPurchasePricesIncludeVat(orgId);
      result.statsDaysWritten = await rebuildPosDailyStatsForRange(
        orgId, siteId, from, until, [...lookups.byId.values()], includeVat,
      );
    } catch (error) {
      logger.error("oktopos_stats_error", {
        event: "oktopos_stats_error",
        fn, requestId, orgId, siteId,
        message: truncateError(error),
      });
    }
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
    statsDaysWritten: result.statsDaysWritten,
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
    // EK/USt fuer die posDailyStats-Wareneinsatz-Bewertung (M5, §3.3) mitfuehren.
    // 0 ist ein gueltiger EK -> nur null/undefined als "nicht gesetzt" behandeln.
    const ekRaw = data.purchasePriceCents;
    const rateRaw = data.taxRatePercent;
    const entry = {
      id: doc.id,
      name: stringOrNull(data.name),
      inFridge: isTruthy(data.inFridge),
      purchasePriceCents: ekRaw == null || !Number.isFinite(Number(ekRaw))
        ? null : Math.round(Number(ekRaw)),
      taxRatePercent: rateRaw == null || !Number.isFinite(Number(rateRaw))
        ? null : Math.round(Number(rateRaw)),
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

// ---------------------------------------------------------------------------
// Kassen-Modul M5 — posDailyStats-Fortschreibung (Tagesaggregate je Standort)
// ---------------------------------------------------------------------------
// Verdichtet die posReceipts zu EINEM Doc je (Standort, Geschaeftstag), damit
// Monats-/Jahres-Sichten nicht zehntausende Beleg-Reads kosten (§3.3). Die
// Rechenlogik liegt im puren Modul oktopos_stats.js (Spiegel von
// dailyStatsFromReceipts, §11.11). Nur serverseitig geschrieben (Admin SDK);
// die Client-Rules erlauben kein write auf posDailyStats.

// Org-Schalter §3.4: ob die EK-Preise MwSt enthalten (brutto -> auf netto
// normalisieren). Default false = netto. Fail-safe: bei Fehler netto annehmen.
async function loadPurchasePricesIncludeVat(orgId) {
  try {
    const snap = await organizationCollection(orgId, "config")
      .doc("orgSettings").get();
    return snap.exists && (snap.data() || {}).purchasePricesIncludeVat === true;
  } catch (error) {
    return false;
  }
}

// Liest die posReceipts eines Standorts im transactionDate-Fenster und mappt sie
// in die von computeDailyStats erwartete Form (§3.3: Range-Query statt
// businessDay-Gleichheit, damit null-businessDay-Belege nicht herausfallen).
async function readPosReceiptsForStats(orgId, siteId, fromDate, toDate) {
  const snap = await organizationCollection(orgId, "posReceipts")
    .where("siteId", "==", siteId)
    .where("transactionDate", ">=", Timestamp.fromDate(fromDate))
    .where("transactionDate", "<=", Timestamp.fromDate(toDate))
    .get();
  const out = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const td = d.transactionDate;
    out.push({
      siteId: stringOrNull(d.siteId),
      businessDay: stringOrNull(d.businessDay),
      transactionDate: td && typeof td.toDate === "function" ? td.toDate() : null,
      type: stringOrNull(d.type),
      training: d.training === true,
      isRevenue: d.isRevenue === true,
      grossCents: d.grossCents == null ? null : Number(d.grossCents),
      taxes: asArray(d.taxes),
      payments: asArray(d.payments),
      lines: asArray(d.lines),
    });
  }
  return out;
}

// Schreibt die Tagesaggregate (set, kein increment -> Re-Aggregation idempotent
// fuer beleg-abgeleitete Felder). Doc-ID deterministisch `{businessDay}-{siteId}`.
async function writePosDailyStats(orgId, stats) {
  if (!Array.isArray(stats) || stats.length === 0) return 0;
  const col = organizationCollection(orgId, "posDailyStats");
  let written = 0;
  const CHUNK = 400; // je Tag 1 Write -> sicher unter dem 500er-Batch-Limit.
  for (let i = 0; i < stats.length; i += CHUNK) {
    const slice = stats.slice(i, i + CHUNK);
    const batch = db.batch();
    for (const s of slice) {
      batch.set(col.doc(`${s.businessDay}-${s.siteId}`), {
        orgId,
        siteId: s.siteId,
        businessDay: s.businessDay,
        salesCount: s.salesCount,
        refundCount: s.refundCount,
        positiveRefundCount: s.positiveRefundCount,
        revenueGrossCents: s.revenueGrossCents,
        revenueNetCents: s.revenueNetCents,
        netUncoveredGrossCents: s.netUncoveredGrossCents,
        taxes: s.taxes,
        paymentsByMethod: s.paymentsByMethod,
        cashMovementCents: s.cashMovementCents,
        cogsCents: s.cogsCents,
        cogsCoveredGrossCents: s.cogsCoveredGrossCents,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    written += slice.length;
  }
  return written;
}

// Re-aggregiert posDailyStats fuer [fromDate..untilDate] eines Standorts und
// schreibt die betroffenen Tage. Liest ein um +/-1 Tag erweitertes Fenster
// (Geschaeftstag-vs-Kalendertag-Rand), schreibt aber nur Tage IM Kernfenster
// (Randtage koennten unvollstaendig aggregiert sein). `products` = Lookup-
// Eintraege mit purchasePriceCents/taxRatePercent. Gibt die Anzahl geschriebener
// Tage zurueck.
async function rebuildPosDailyStatsForRange(
  orgId, siteId, fromDate, untilDate, products, includeVat,
) {
  const fetchFrom = daysAgo(fromDate, 1);
  const fetchTo = new Date(untilDate.getTime() + 24 * 60 * 60 * 1000);
  const receipts = await readPosReceiptsForStats(
    orgId, siteId, fetchFrom, fetchTo,
  );
  const ekNettoById = oktoposStats.ekNettoByProduct(products, {
    purchasePricesIncludeVat: includeVat === true,
  });
  const all = oktoposStats.computeDailyStats(receipts, ekNettoById);
  const fromDay = oktoposStats.dayOf(fromDate);
  const toDay = oktoposStats.dayOf(untilDate);
  // Nur Kernfenster-Tage schreiben (die Rand-Puffer-Tage dienen nur der
  // vollstaendigen Aggregation der Kern-Tage).
  const inWindow = all.filter(
    (s) => s.businessDay >= fromDay && s.businessDay <= toDay,
  );
  return writePosDailyStats(orgId, inWindow);
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

// H6 (Sicherheits-Audit 2026-07): Idempotenz-Scope ist die STABILE siteId —
// frueher steckte die (nachtraeglich aenderbare) cashRegisterId in den IDs;
// ein Konfig-Wechsel gab denselben Belegen neue Doc-IDs und der 3-Tage-
// Lookback buchte Bestand doppelt. referenceNumber ist je Kasse eindeutig;
// pro Standort ist genau eine Kassen-Nr. konfiguriert -> siteId-Scope reicht.
function oktoposSiteScope(siteId) {
  return stringOrEmpty(siteId).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 80) ||
    "all";
}

// H3: Zeilen-Diskriminator fuer Bewegungs-IDs. Fehlt `item.id` (oder ist 0),
// kollabierten frueher ALLE Zeilen eines Belegs auf dieselbe movementId und
// der Dedup verwarf alle bis auf die erste -> Bestand zu hoch. Fallback ist
// der Positions-Index innerhalb des Belegs.
function oktoposLineDiscriminator(item, index) {
  const id = Number(item?.id);
  if (Number.isFinite(id) && Math.trunc(id) !== 0) {
    return String(Math.trunc(id));
  }
  return `i${index}`;
}

function buildOktoposMovementId(siteId, referenceNumber, lineDiscriminator) {
  const raw = stringOrEmpty(referenceNumber);
  // safeRef ist verlustbehaftet (Sonderzeichen -> "_"), daher wie bei
  // buildOktoposReceiptId einen kollisionsfreien Hash der ROH-Belegnummer
  // anhaengen: gleiche Rohnummer = gleiche ID (idempotent), verschiedene
  // Rohnummern = verschiedene IDs (kein Doppel-/Fehlbuchen beim Re-Pull).
  const safeRef = raw.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120);
  const scope = oktoposSiteScope(siteId);
  return `oktopos-${scope}-${safeRef}-${stableHash([raw]).slice(0, 12)}-` +
    `${lineDiscriminator}`;
}

// Doc-ID eines posReceipts (P0). Mit dem STABILEN Standort qualifiziert (H6,
// s.o.), sonst Cross-Store-Kollision. Deterministisch = Idempotenz beim
// Re-Pull (set(merge)). Der lesbare `safeRef` ersetzt Sonderzeichen
// verlustbehaftet (zwei verschiedene Belegnummern könnten gleich
// normalisieren) -> ein kollisionsfreier Hash der ROH-Belegnummer wird
// angehängt; gleiche Rohnummer = gleiche ID, verschiedene = verschiedene IDs.
function buildOktoposReceiptId(siteId, referenceNumber) {
  const raw = stringOrEmpty(referenceNumber);
  const safeRef = raw.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120);
  return `${oktoposSiteScope(siteId)}-${safeRef}-` +
    `${stableHash([raw]).slice(0, 12)}`;
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
    // H2: siteId gegen die Org-Config validieren, BEVOR ein Key aufgeloest wird.
    assertOktoposSiteConfigured(config, siteId);
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
    // H2: siteId gegen die Org-Config validieren, BEVOR ein Key aufgeloest wird.
    assertOktoposSiteConfigured(config, siteId);
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
  // K4 (Sicherheits-Audit 2026-07): Host gegen die Allowlist pruefen — die
  // baseUrl ist admin-schreibbare Config; ohne Pruefung ginge der X-API-KEY an
  // jeden beliebigen HTTPS-Host (Secret-Exfiltration/SSRF).
  assertOktoposHostAllowed(baseUrl, OKTOPOS_ALLOWED_HOSTS.value());
  return baseUrl;
}

// Pur & node-testbar: wirft, wenn der baseUrl-Host nicht exakt auf der
// kommagetrennten Allowlist steht oder eine private/link-local/Loopback-Adresse
// ist. Leere Allowlist = fail-closed (Betreiber muss OKTOPOS_ALLOWED_HOSTS
// beim Cutover setzen).
function assertOktoposHostAllowed(baseUrl, allowedHostsRaw) {
  let parsedUrl;
  try {
    parsedUrl = new URL(baseUrl);
  } catch (error) {
    throw new HttpsError(
      "failed-precondition", "OktoPOS baseUrl ist keine gueltige URL.",
    );
  }
  const host = parsedUrl.hostname.toLowerCase();
  const isPrivateHost = host === "localhost" ||
    host === "::1" ||
    /^127\./.test(host) ||
    /^10\./.test(host) ||
    /^192\.168\./.test(host) ||
    /^169\.254\./.test(host) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host);
  if (isPrivateHost) {
    throw new HttpsError(
      "failed-precondition",
      "OktoPOS baseUrl darf nicht auf private/lokale Adressen zeigen.",
    );
  }
  const allowed = stringOrEmpty(allowedHostsRaw)
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item.length > 0);
  if (allowed.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "OKTOPOS_ALLOWED_HOSTS ist nicht konfiguriert. Beim Deploy die " +
        "erlaubten Kassen-Hosts setzen (kommagetrennt), sonst bleiben " +
        "OktoPOS-Aufrufe gesperrt.",
    );
  }
  if (!allowed.includes(host)) {
    throw new HttpsError(
      "failed-precondition",
      `OktoPOS-Host ${host} steht nicht auf der Allowlist ` +
        "(OKTOPOS_ALLOWED_HOSTS).",
    );
  }
}

// H2 (Sicherheits-Audit 2026-07): siteId kommt aus dem Request — vor jeder
// Key-Aufloesung/jedem Kassen-Call pruefen, dass der Standort in der
// OktoPOS-Config DIESER Org existiert (kein Sync/Push fuer fremde oder
// unbekannte Sites).
function assertOktoposSiteConfigured(config, siteId) {
  if (!isPlainObject(config?.sites) || !isPlainObject(config.sites[siteId])) {
    throw new HttpsError(
      "failed-precondition",
      `Standort ${siteId} ist in config/oktoposSync nicht konfiguriert ` +
        "(sites-Eintrag fehlt).",
    );
  }
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
    // H2: siteId gegen die Org-Config validieren, BEVOR ein Key aufgeloest wird.
    assertOktoposSiteConfigured(config, siteId);
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

// Nur für Offline-Tests (functions/test, node --test): pure Serialisierungs-
// Helfer exportieren. KEIN Cloud-Function-Export — die Functions-Discovery
// registriert nur Exporte mit __endpoint, plain Functions werden ignoriert.
exports._testables = {
  parseShift,
  toFirestoreShift,
  fromFirestoreShift,
  resolveWorkEntryApproval,
  isReviewer,
  accountDeletion,
  enforceShiftOrg,
  singleRestGapViolations,
  shouldEnforceRestGap,
  assertOktoposHostAllowed,
  resolveOktoposApiKey,
  buildOktoposMovementId,
  buildOktoposReceiptId,
  oktoposLineDiscriminator,
  berlinNoonDate,
};
