"use strict";

// Passwortmanager — pure Zugriffs-/Validierungslogik (PM-M3, §11). Ohne Admin
// SDK, damit die Autorisierung (Sichtbarkeit/Verwaltung) und die Payload-
// Validierung mit `node --test` offline prüfbar sind. Die Callables in index.js
// rufen ausschließlich diese Funktionen — die Sichtbarkeit ist server-
// authoritativ und wird LIVE gegen die Filialzuordnung gerechnet (nie gegen
// materialisierte audienceUids als Autorität).

const MAX_TITLE = 200;
const MAX_AUDIENCE = 200;

function invalid(message) {
  const err = new Error(message);
  err.invalidArgument = true;
  return err;
}

function _strList(v) {
  return Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
}

/**
 * Darf der Aufrufer diesen Eintrag SEHEN/ANZEIGEN? (camelCase-Entry)
 * @param {object} entry            {scope, ownerUid, audienceUids,
 *                                   audienceRoles, audienceSiteIds}
 * @param {object} caller           {uid, role, isAdmin}
 * @param {string[]} callerSiteIds  LIVE geladene Filialzuordnung des Aufrufers
 */
function canViewEntry(entry, caller, callerSiteIds) {
  if (caller.isAdmin) return true;
  const scope = entry.scope === "shared" ? "shared" : "personal";
  if (scope === "personal") return entry.ownerUid === caller.uid;
  const aud = _strList(entry.audienceUids);
  const roles = _strList(entry.audienceRoles);
  const sites = _strList(entry.audienceSiteIds);
  if (aud.includes(caller.uid)) return true;
  if (caller.role && roles.includes(caller.role)) return true;
  for (const s of callerSiteIds || []) {
    if (sites.includes(s)) return true;
  }
  return false;
}

/**
 * Darf der Aufrufer diesen Eintrag ANLEGEN/ÄNDERN/LÖSCHEN?
 * @param {object} opts {teamleadEnabled}
 */
function canManageEntry(entry, caller, callerSiteIds, opts) {
  const teamleadEnabled = !!(opts && opts.teamleadEnabled);
  const scope = entry.scope === "shared" ? "shared" : "personal";
  if (scope === "personal") {
    return entry.ownerUid === caller.uid || caller.isAdmin;
  }
  if (caller.isAdmin) return true;
  if (teamleadEnabled && caller.role === "teamlead" && entry.siteId &&
      (callerSiteIds || []).includes(entry.siteId)) {
    return true;
  }
  return false;
}

/** Validiert ein normalisiertes (camelCase) Entry-Objekt. Wirft invalid. */
function validateEntry(entry) {
  const title = typeof entry.title === "string" ? entry.title.trim() : "";
  if (!title) throw invalid("Titel fehlt.");
  if (title.length > MAX_TITLE) throw invalid("Titel ist zu lang.");
  if (entry.scope !== "personal" && entry.scope !== "shared") {
    throw invalid("Ungültiger Scope.");
  }
  for (const key of ["audienceUids", "audienceRoles", "audienceSiteIds"]) {
    const v = entry[key];
    if (v.length > MAX_AUDIENCE) throw invalid(`Zielgruppe (${key}) zu groß.`);
  }
  return true;
}

/**
 * Parst die snake_case-Callable-Payload (PasswordEntry.toMap()) in ein
 * normalisiertes camelCase-Entry-Objekt und validiert es.
 */
function parseEntryPayload(raw) {
  if (!raw || typeof raw !== "object") throw invalid("entry fehlt.");
  const str = (v) => (typeof v === "string" ? v : (v == null ? null : String(v)));
  const entry = {
    orgId: str(raw.org_id) || "",
    title: (str(raw.title) || "").trim(),
    category: str(raw.category) || "other",
    siteId: str(raw.site_id),
    siteName: str(raw.site_name),
    ownerUid: str(raw.owner_uid),
    scope: raw.scope === "shared" ? "shared" : "personal",
    audienceUids: _strList(raw.audience_uids),
    audienceRoles: _strList(raw.audience_roles),
    audienceSiteIds: _strList(raw.audience_site_ids),
    url: str(raw.url),
  };
  validateEntry(entry);
  return entry;
}

/** Validiert das Klartext-Secret (username/password/notes) aus der Payload. */
function parseSecretPayload(raw) {
  const str = (v) => (typeof v === "string" ? v : "");
  const password = str(raw.plain_password);
  if (password.length > 4096) throw invalid("Passwort ist zu lang.");
  return {
    u: str(raw.plain_username),
    p: password,
    n: str(raw.plain_notes),
  };
}

module.exports = {
  canViewEntry,
  canManageEntry,
  validateEntry,
  parseEntryPayload,
  parseSecretPayload,
  MAX_TITLE,
  MAX_AUDIENCE,
};
