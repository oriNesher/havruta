import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

export const onParticipantProgressUpdate = onDocumentUpdated(
  {
    document: "competitions/{competitionId}/participants/{participantId}",
    maxInstances: 5,
    concurrency: 1,
  },
  (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) {
      logger.info("Missing data");
      return;
    }

    const beforeProgress = before.progress;
    const afterProgress = after.progress;

    if (beforeProgress === afterProgress) {
      logger.info("Progress did not change");
      return;
    }

    if (afterProgress < beforeProgress) {
      logger.info("Progress decreased, skipping notification", {
        competitionId: event.params.competitionId,
        participantId: event.params.participantId,
        beforeProgress,
        afterProgress,
      });
      return;
    }

    logger.info("Progress changed!", {
      competitionId: event.params.competitionId,
      participantId: event.params.participantId,
      beforeProgress,
      afterProgress,
      userId: after.userId,
    });
  },
);

