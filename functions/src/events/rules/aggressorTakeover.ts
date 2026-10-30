import {EventDraft} from "../types";
import {AggressorScore} from "../../challenges/aggressor";

/**
 * What prompted an Aggressor Badge re-evaluation.
 * - progress: someone logged progress.
 * - progressRemoved: someone took progress back.
 * - dayRollover: the window moved on at the challenge's midnight.
 * - holderLeft: the holder left the challenge.
 */
export type AggressorCause =
  | "progress"
  | "progressRemoved"
  | "dayRollover"
  | "holderLeft";

/** One decided badge re-evaluation, as the settling transaction saw it. */
export interface AggressorTransfer {
  competitionTitle: string;
  /** Everyone in the challenge. */
  participants: {uid: string; username: string}[];
  previousHolderUid: string | null;
  /** Previous holder's name, kept for when they're no longer a participant. */
  previousHolderUsername: string | null;
  newHolderUid: string | null;
  cause: AggressorCause;
  /** Whose progress write prompted this, if one did. */
  reporterUid: string | null;
  scores: AggressorScore[];
  windowDays: string[];
}

/**
 * Creates the "aggressorTakeover" event when the badge actually changes
 * hands — including a first claim, where there's no previous holder (its
 * target is then null). Nothing when the holder stays the same, when the
 * badge goes vacant, or when it passes on only because its holder left
 * (nobody took it).
 *
 * Shown to everyone but the new holder. Celebrated only when the new
 * holder won it with their own progress report; a transfer they didn't
 * cause (a rival taking progress back, the window moving at midnight) is
 * news, not a moment — it's marked already-celebrated so the celebration
 * gate ignores it.
 *
 * Called inside the transaction that records the new holder, so each real
 * transfer yields exactly one draft and retries yield none.
 * @param {AggressorTransfer} transfer The decided re-evaluation.
 * @return {EventDraft[]} Zero or one takeover draft.
 */
export function detectAggressorTakeoverEvents(
  transfer: AggressorTransfer
): EventDraft[] {
  const {
    competitionTitle,
    participants,
    previousHolderUid,
    previousHolderUsername,
    newHolderUid,
    cause,
    reporterUid,
    scores,
    windowDays,
  } = transfer;

  if (
    newHolderUid === null ||
    newHolderUid === previousHolderUid ||
    cause === "holderLeft"
  ) {
    return [];
  }

  const usernameOf = (uid: string) =>
    participants.find((p) => p.uid === uid)?.username;
  const windowTotalOf = (uid: string | null) =>
    uid === null ? null : scores.find((s) => s.uid === uid)?.windowTotal ?? 0;
  const celebrate = cause === "progress" && reporterUid === newHolderUid;

  return [{
    type: "aggressorTakeover",
    recipients: participants
      .map((p) => p.uid)
      .filter((uid) => uid !== newHolderUid),
    target: {kind: "create"},
    payload: {
      competitionTitle,
      actorUid: newHolderUid,
      actorUsername: usernameOf(newHolderUid) ?? "Someone",
      targetUid: previousHolderUid,
      targetUsername: previousHolderUid === null ?
        null :
        usernameOf(previousHolderUid) ?? previousHolderUsername ?? "Someone",
      // Overrides the actorCelebrated: false every celebration type gets.
      actorCelebrated: !celebrate,
      metadata: {
        cause,
        windowDays,
        actorWindowTotal: windowTotalOf(newHolderUid),
        targetWindowTotal: windowTotalOf(previousHolderUid),
      },
    },
  }];
}
