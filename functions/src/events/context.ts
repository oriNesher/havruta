import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {EventsContext, ParticipantData} from "./types";

export interface BuildContextParams {
  competitionId: string;
  participantId: string;
  before: FirebaseFirestore.DocumentData;
  after: FirebaseFirestore.DocumentData;
}

/**
 * Reads everything the event rules need for one participant update and
 * applies the early-exit checks that used to live inline in the trigger.
 * @param {BuildContextParams} params Update identifiers and before/after data.
 * @return {Promise<EventsContext | null>} Null when no event evaluation
 *   should happen for this update.
 */
export async function buildEventsContext(
  params: BuildContextParams
): Promise<EventsContext | null> {
  const {competitionId, participantId, before, after} = params;

  const beforeProgress = before.progress ?? 0;
  const afterProgress = after.progress ?? 0;

  if (beforeProgress === afterProgress) {
    logger.info("Progress did not change, skipping event creation");
    return null;
  }

  if (afterProgress < beforeProgress) {
    logger.info("Progress decreased, skipping event creation", {
      competitionId,
      participantId,
      beforeProgress,
      afterProgress,
    });
    return null;
  }

  const actorUid = after.uid;
  const actorUsername = after.username ?? "Someone";
  const actorTargetValue = after.targetValue ?? 0;

  if (!actorUid) {
    logger.info("Missing updater uid for event creation");
    return null;
  }

  const db = admin.firestore();
  const competitionRef = db.collection("competitions").doc(competitionId);
  const eventsRef = competitionRef.collection("events");

  const competitionSnap = await competitionRef.get();

  if (!competitionSnap.exists) {
    logger.info("Competition not found for event creation", {competitionId});
    return null;
  }

  const competitionData = competitionSnap.data() || {};
  const competitionTitle = competitionData.title ?? "Competition";
  const competitionStatus = competitionData.status ?? "active";

  if (competitionStatus !== "active") {
    logger.info("Competition is not active, skipping event creation", {
      competitionId,
      competitionStatus,
    });
    return null;
  }

  const participantsSnap = await competitionRef
    .collection("participants")
    .get();

  const participants: ParticipantData[] = participantsSnap.docs
    .map((doc) => doc.data() as ParticipantData)
    .filter((participant) => !!participant.uid);

  const participantUids = [
    ...new Set(participants.map((participant) => participant.uid)),
  ];

  if (participantUids.length < 2) {
    logger.info("Not enough participants for event creation", {
      competitionId,
      participantCount: participantUids.length,
    });
    return null;
  }

  const existingEventSnap = await eventsRef
    .where("type", "==", "progress")
    .where("actorUid", "==", actorUid)
    .where("status", "==", "open")
    .limit(1)
    .get();

  const existingOpenProgressEvent = existingEventSnap.empty ?
    null :
    {
      id: existingEventSnap.docs[0].id,
      data: existingEventSnap.docs[0].data(),
    };

  return {
    competitionId,
    competitionTitle,
    actorUid,
    actorUsername,
    actorTargetValue,
    beforeProgress,
    afterProgress,
    participants,
    participantUids,
    existingOpenProgressEvent,
  };
}
