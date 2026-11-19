import * as admin from "firebase-admin";
import {ParticipantGoalFields} from "./joining";

/**
 * Adds a participant inside the caller's transaction: their uid onto
 * competition.participantUids and a fresh participants/{uid} doc. The one
 * write shape for every server-side join path (invite links, direct
 * invites) — clients can no longer add themselves, see firestore.rules.
 * @param {FirebaseFirestore.Transaction} tx The open transaction.
 * @param {FirebaseFirestore.DocumentReference} competitionRef The challenge.
 * @param {string} uid The joiner.
 * @param {string} username The joiner's display name.
 * @param {ParticipantGoalFields} goalFields Goal fields to copy on.
 */
export function writeParticipantJoin(
  tx: FirebaseFirestore.Transaction,
  competitionRef: FirebaseFirestore.DocumentReference,
  uid: string,
  username: string,
  goalFields: ParticipantGoalFields
): void {
  tx.update(competitionRef, {
    participantUids: admin.firestore.FieldValue.arrayUnion(uid),
  });

  tx.set(competitionRef.collection("participants").doc(uid), {
    uid,
    username,
    ...goalFields,
    progress: 0,
    joinedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}
