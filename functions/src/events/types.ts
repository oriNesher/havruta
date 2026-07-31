export interface ParticipantData {
  uid: string;
  username?: string;
  progress?: number;
  targetValue?: number;
}

export interface ExistingOpenEvent {
  id: string;
  data: FirebaseFirestore.DocumentData;
}

export interface EventsContext {
  competitionId: string;
  competitionTitle: string;
  actorUid: string;
  actorUsername: string;
  actorTargetValue: number;
  beforeProgress: number;
  afterProgress: number;
  participants: ParticipantData[];
  participantUids: string[];
  existingOpenProgressEvent: ExistingOpenEvent | null;
  previousUpdatedAt: FirebaseFirestore.Timestamp | null;
  currentUpdatedAt: FirebaseFirestore.Timestamp | null;
  firedCloseRaceCheckpoints: number[];
  completionsCount: number;
  todayDateStr: string;
  isNewActiveDay: boolean;
  newStreakCount: number;
}

export type EventDraftTarget =
  | {kind: "create"}
  | {kind: "update"; docId: string};

export interface EventDraft {
  type: string;
  recipients: string[];
  target: EventDraftTarget;
  payload: Record<string, unknown>;
}
