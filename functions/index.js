"use strict";

const crypto = require("node:crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

admin.initializeApp();

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;
const REGION = "europe-west3";

exports.upsertShiftBatch = onCall({region: REGION}, async (request) => {
  const caller = await loadCallerProfile(request);
  assertScheduler(caller);

  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const rawShifts = asArray(request.data?.shifts);
  if (rawShifts.length === 0) {
    return {savedIds: [], issues: []};
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

exports.publishShiftBatch = onCall({region: REGION}, async (request) => {
  const caller = await loadCallerProfile(request);
  assertScheduler(caller);

  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const status = requiredString(request.data?.status, "status");
  const rawShifts = asArray(request.data?.shifts);
  if (rawShifts.length === 0) {
    return {savedIds: [], issues: []};
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

exports.upsertWorkEntry = onCall({region: REGION}, async (request) => {
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

exports.upsertWorkEntryBatch = onCall({region: REGION}, async (request) => {
  const caller = await loadCallerProfile(request);
  assertTimeEntryEditor(caller);
  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);
  const rawEntries = asArray(request.data?.entries);
  if (rawEntries.length === 0) {
    return {savedIds: [], validations: []};
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

exports.previewCompliance = onCall({region: REGION}, async (request) => {
  const caller = await loadCallerProfile(request);
  const orgId = requiredString(request.data?.orgId, "orgId");
  assertSameOrg(caller, orgId);

  if (Array.isArray(request.data?.shifts) && request.data.shifts.length > 0) {
    const shifts = request.data.shifts.map((item, index) =>
      parseShift(item, index, orgId),
    );
    const issues = await validateShiftBatch({orgId, shifts});
    return {issues};
  }

  if (request.data?.entry != null) {
    const entry = parseWorkEntry(request.data.entry);
    const validation = await validateWorkEntry({callerUid: caller.uid, entry});
    return validation;
  }

  throw new HttpsError(
    "invalid-argument",
    "Es wurde weder ein Schichtpaket noch ein Zeiteintrag uebergeben.",
  );
});

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
    absencesSnap,
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
    organizationCollection(orgId, "absenceRequests")
      .where("startDate", "<=", Timestamp.fromDate(maxEnd))
      .orderBy("startDate")
      .get(),
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
    absences: absencesSnap.docs
      .map(fromFirestoreAbsence)
      .filter((absence) => absence.status === "approved")
      .filter((absence) => userIds.includes(absence.userId)),
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
  const dayStart = new Date(
    entry.startTime.getFullYear(),
    entry.startTime.getMonth(),
    entry.startTime.getDate(),
  );
  const nextDay = new Date(
    entry.startTime.getFullYear(),
    entry.startTime.getMonth(),
    entry.startTime.getDate() + 1,
  );

  const collection = organizationCollection(entry.orgId, "workEntries");
  const existingRef = entry.id ? collection.doc(entry.id) : null;
  const [
    entriesSnap,
    contractsSnap,
    assignmentsSnap,
    rulesSnap,
    memberSnapshot,
    existingSnapshot,
  ] = await Promise.all([
    collection
      .where("userId", "==", entry.userId)
      .where("startTime", ">=", Timestamp.fromDate(dayStart))
      .where("startTime", "<", Timestamp.fromDate(nextDay))
      .orderBy("startTime")
      .get(),
    organizationCollection(entry.orgId, "employmentContracts").get(),
    organizationCollection(entry.orgId, "employeeSiteAssignments").get(),
    organizationCollection(entry.orgId, "ruleSets").get(),
    db.collection("users").doc(entry.userId).get(),
    existingRef ? existingRef.get() : Promise.resolve(null),
  ]);

  const existingEntries = entriesSnap.docs.map(fromFirestoreWorkEntry);
  const contracts = contractsSnap.docs.map(fromFirestoreContract);
  const siteAssignments = assignmentsSnap.docs.map(fromFirestoreSiteAssignment);
  const ruleSets = rulesSnap.docs.map(fromFirestoreRuleSet);
  const member = memberSnapshot.exists ? fromFirestoreMember(memberSnapshot) : null;
  const violations = validateSingleWorkEntry({
    entry,
    existingEntries,
    contracts,
    siteAssignments,
    ruleSets,
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

function validateSingleWorkEntry({
  entry,
  existingEntries,
  contracts,
  siteAssignments,
  ruleSets,
  member,
}) {
  const violations = [];
  const contract = activeContract(contracts, entry.userId, entry.startTime);
  const workRuleSettings = effectiveWorkRuleSettings(member);
  const ruleSet = resolveRuleSet(ruleSets, entry.siteId, contract);
  const assignment = siteAssignments.find(
    (item) => item.userId === entry.userId && item.siteId === entry.siteId,
  );

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

  const sameDayMinutes = existingEntries
    .filter((candidate) => candidate.id !== entry.id && isSameDay(candidate.startTime, entry.startTime))
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
