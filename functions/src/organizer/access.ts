import {HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {ChallengeConfig, parseChallenge} from "../challenges/model";
import {OrganizerError} from "./errors";

/** A challenge loaded for an organizer action, inside a transaction. */
export interface OrganizerContext {
  ref: FirebaseFirestore.DocumentReference;
  data: FirebaseFirestore.DocumentData;
  challenge: ChallengeConfig;
  actorUid: string;
  actorUsername: string;
}

/**
 * The signed-in caller's uid and a validated competitionId, or an
 * HttpsError — the common preamble of every organizer callable.
 * @param {object} request The callable request.
 * @param {object} [request.auth] Its auth context.
 * @param {string} request.auth.uid The caller.
 * @param {unknown} request.data Its payload.
 * @return {{uid: string, competitionId: string}} The caller and challenge.
 */
export function requireCaller(request: {
  auth?: {uid: string};
  data: unknown;
}): {uid: string; competitionId: string} {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
  const competitionId = (request.data as {competitionId?: unknown} | null)
    ?.competitionId;
  if (typeof competitionId !== "string" || !competitionId) {
    throw new HttpsError("invalid-argument", "competitionId is required.");
  }
  return {uid, competitionId};
}

/**
 * Reads the challenge and the caller's name inside the transaction, and
 * refuses anyone who isn't one of its organizers. Every organizer power is
 * enforced here, server-side — firestore.rules give organizers no direct
 * write access beyond renaming.
 * @param {FirebaseFirestore.Transaction} tx The open transaction.
 * @param {string} competitionId The challenge.
 * @param {string} uid The caller.
 * @return {Promise<OrganizerContext>} The loaded challenge.
 */
export async function loadAsOrganizer(
  tx: FirebaseFirestore.Transaction,
  competitionId: string,
  uid: string
): Promise<OrganizerContext> {
  const db = admin.firestore();
  const ref = db.collection("competitions").doc(competitionId);
  const [snap, userSnap] = await Promise.all([
    tx.get(ref),
    tx.get(db.collection("users").doc(uid)),
  ]);
  if (!snap.exists) {
    throw new HttpsError("not-found", "This challenge no longer exists.");
  }
  const data = snap.data() ?? {};
  const challenge = parseChallenge(data);
  if (!challenge.organizerUids.includes(uid)) {
    throw new HttpsError(
      "permission-denied",
      "Only this challenge's organizers can do that."
    );
  }
  return {
    ref,
    data,
    challenge,
    actorUid: uid,
    actorUsername: userSnap.data()?.username ?? "An organizer",
  };
}

/** One audit-log record (the who/when fields are added for you). */
export interface AuditRecord {
  action:
    | "updateSettings"
    | "removeParticipant"
    | "reinstateParticipant"
    | "correctProgress"
    | "endEarly"
    | "addOrganizer"
    | "removeOrganizer";
  targetUid?: string | null;
  targetUsername?: string | null;
  before?: unknown;
  after?: unknown;
  reason?: string | null;
  entryId?: string | null;
}

/**
 * Writes an audit record in the transaction:
 * competitions/{id}/auditLog/{auto}. Organizer-readable, server-written
 * only (firestore.rules), so the history can't be edited after the fact.
 * @param {FirebaseFirestore.Transaction} tx The open transaction.
 * @param {OrganizerContext} ctx The loaded challenge and actor.
 * @param {AuditRecord} record What happened.
 */
export function writeAudit(
  tx: FirebaseFirestore.Transaction,
  ctx: OrganizerContext,
  record: AuditRecord
): void {
  tx.set(ctx.ref.collection("auditLog").doc(), {
    ...record,
    targetUid: record.targetUid ?? null,
    targetUsername: record.targetUsername ?? null,
    before: record.before ?? null,
    after: record.after ?? null,
    reason: record.reason ?? null,
    entryId: record.entryId ?? null,
    actorUid: ctx.actorUid,
    actorUsername: ctx.actorUsername,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Runs an organizer action, turning a planner's OrganizerError into a
 * failed-precondition HttpsError the client can show as-is.
 * @param {function(): Promise<T>} action The action.
 * @return {Promise<T>} Its result.
 * @template T
 */
export async function asCallable<T>(action: () => Promise<T>): Promise<T> {
  try {
    return await action();
  } catch (error) {
    if (error instanceof OrganizerError) {
      throw new HttpsError("failed-precondition", error.message);
    }
    throw error;
  }
}
