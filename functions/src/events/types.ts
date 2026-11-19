import {ChallengeConfig} from "../challenges/model";
import {Audience} from "./audience";

export interface ParticipantData {
  uid: string;
  username?: string;
  progress?: number;
  targetValue?: number;
  updatedAt?: FirebaseFirestore.Timestamp;
  dailyProgress?: Record<string, number>;
  eliminatedOnDay?: string;
  teamId?: string;
}

export interface ExistingOpenEvent {
  id: string;
  data: FirebaseFirestore.DocumentData;
}

export interface EventsContext {
  competitionId: string;
  competitionTitle: string;
  challenge: ChallengeConfig;
  actorUid: string;
  actorUsername: string;
  actorTargetValue: number;
  beforeProgress: number;
  afterProgress: number;
  participants: ParticipantData[];
  participantUids: string[];
  openTiedEvents: ExistingOpenEvent[];
  previousUpdatedAt: FirebaseFirestore.Timestamp | null;
  currentUpdatedAt: FirebaseFirestore.Timestamp | null;
  firedCloseRaceCheckpoints: number[];
  completionsCount: number;
  hasFirstBloodEvent: boolean;
  todayDateStr: string;
  isNewActiveDay: boolean;
  newStreakCount: number;
  /**
   * Who events reach in a large challenge (see audience.ts); null or
   * absent for a small one, where everyone else hears everything.
   */
  audience?: Audience | null;
}

export type EventDraftTarget =
  | {kind: "create"}
  | {kind: "update"; docId: string}
  | {kind: "upsertProgress"};

export interface EventDraft {
  type: string;
  recipients: string[];
  target: EventDraftTarget;
  payload: Record<string, unknown>;
}
