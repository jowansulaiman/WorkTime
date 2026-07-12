"use strict";

// Klassifikation aller nutzergebundenen Daten für die komplette Konto-Löschung
// (Plan plan/account-loeschung.md). PURE Datentabellen + Helfer — KEIN
// Firestore-/Admin-SDK-Zugriff, damit node-testbar (functions/test). Die
// eigentliche I/O-Orchestrierung liegt in index.js (runAccountDeletion).
//
// Nutzerentscheidung 08.07.: persönliche Daten HART löschen,
// aufbewahrungspflichtige Zeit-/Lohn-/Vertrags-/Kassendaten behalten, aber die
// Personen-Verknüpfung ANONYMISIEREN (Art. 17 Abs. 3 lit. b DSGVO vs.
// GoBD/ArbZG/§147 AO).

const crypto = require("node:crypto");

// Anonymer, pro Nutzer STABILER Marker (gleiche uid -> gleicher Marker), damit
// aufbewahrungspflichtige Aggregate (Lohn/Zeit je Person) über Dokumente hinweg
// zusammenhängend bleiben, die Person aber nicht mehr identifizierbar ist.
function anonSentinel(uid) {
  const hash = crypto
    .createHash("sha256")
    .update(String(uid))
    .digest("hex")
    .slice(0, 12);
  return `geloescht:${hash}`;
}

// A) HART LÖSCHEN — Doc-ID == uid (persönliche Daten ohne Aufbewahrungspflicht).
// Org-skopiert: organizations/{orgId}/<name>/{uid}.
const DOC_ID_DELETE = [
  "shiftPreferences",
  "employeeProfiles",
  "payrollProfiles",
  "userSecrets",
  "kioskRoster",
  "kioskPresence",
];

// A) HART LÖSCHEN — feld-basiert (Query where(field == uid)). `shifts` mit
// gelöscht, das löst das `userId`-required-Problem und gibt die Planung frei.
const FIELD_DELETE = [
  {collection: "absenceRequests", field: "userId"},
  {collection: "workTemplates", field: "userId"},
  {collection: "shiftTemplates", field: "userId"},
  {collection: "shifts", field: "userId"},
  {collection: "sollzeitProfiles", field: "userId"},
  {collection: "employeeSiteAssignments", field: "userId"},
  {collection: "employeeChildren", field: "userId"},
  {collection: "employeeNotes", field: "userId"},
  {collection: "employeeQualifications", field: "userId"},
  {collection: "employeeAusbildungen", field: "userId"},
  {collection: "kioskSessions", field: "employeeId"},
  {collection: "notifications", field: "recipientUid"},
];

// B) ANONYMISIEREN — Doc BLEIBT, nur die genannten Link-Felder werden auf den
// Marker gesetzt. Fachliche Nutzdaten (Stunden/Beträge) bleiben für
// Steuer/Prüfung erhalten. `auditLog.actorUid` wird anonymisiert; die deutschen
// Summaries bleiben (admin-only lesbar, Forensik — dokumentiertes Residuum).
const ANONYMIZE = [
  // Alle uid-Link-Felder erfassen: auch als Freigeber/Korrektor/Ersteller in
  // FREMDEN (aufbewahrten) Datensätzen, sonst bleibt die uid des Gelöschten dort
  // roh stehen (Konsistenz mit zeitkontoSnapshots/payrollRecords.createdByUid).
  {collection: "workEntries", fields: ["userId", "approvedByUid", "correctedByUid"]},
  {collection: "clockEntries", fields: ["userId", "createdByUid", "korrigiertVonUid"]},
  {collection: "zeitkontoSnapshots", fields: ["userId", "createdByUid"]},
  {collection: "employmentContracts", fields: ["userId"]},
  {collection: "payrollRecords", fields: ["userId", "createdByUid"]},
  {collection: "cashCounts", fields: ["createdByUid", "countedByUserId"]},
  {collection: "cashClosings", fields: ["closedByUid"]},
  {collection: "journalEntries", fields: ["createdByUid"]},
  {collection: "stockMovements", fields: ["createdByUid"]},
  {collection: "auditLog", fields: ["actorUid"]},
  {collection: "shiftSwapRequests", fields: ["requesterUid", "targetUid"]},
  {collection: "swapCredits", fields: ["creditorUid", "debtorUid"]},
  // Urlaub ist Arbeitszeit-/Lohn-nah (BUrlG/§147 AO): behalten, Personenbezug
  // anonymisieren statt hart löschen (spiegelt zeitkontoSnapshots, Plan C).
  {collection: "urlaubskontoJahre", fields: ["userId"]},
  {collection: "urlaubsanpassungen", fields: ["userId"]},
];

// B') ANONYMISIEREN in PRODUKT-Subcollections (collectionGroup, org-gefiltert).
// priceHistory liegt unter organizations/{org}/products/{pid}/priceHistory —
// die org-Top-Level-Query würde ins Leere greifen. Braucht einen
// collectionGroup-Index (orgId + <field>) in firestore.indexes.json.
const SUBCOLLECTION_ANONYMIZE = [
  {group: "priceHistory", orgField: "orgId", fields: ["changedByUid"]},
];

// Berechnet das Update-Fragment für ein Doc: jedes Link-Feld, das aktuell exakt
// die zu löschende uid trägt, wird auf den Marker gesetzt. Felder, die eine
// ANDERE Person referenzieren (z. B. targetUid bei einem swapRequest, dessen
// requester gelöscht wird), bleiben unangetastet. Leeres Objekt == nichts zu tun.
function computeAnonymizeUpdate(data, uid, sentinel, linkFields) {
  const update = {};
  if (!data || typeof data !== "object") {
    return update;
  }
  for (const field of linkFields) {
    if (data[field] === uid) {
      update[field] = sentinel;
    }
  }
  return update;
}

// Doc-ID für userInvites (E-Mail-basiert): getrimmt, lowercase, "/" -> "_".
// Spiegelt firestore_service.dart `_inviteDocId` — sonst bleibt die Einladung
// liegen (Bootstrap-Falle beim nächsten Login).
function inviteDocId(email) {
  return String(email || "").trim().toLowerCase().replace(/\//g, "_");
}

module.exports = {
  anonSentinel,
  computeAnonymizeUpdate,
  inviteDocId,
  DOC_ID_DELETE,
  FIELD_DELETE,
  ANONYMIZE,
  SUBCOLLECTION_ANONYMIZE,
};
