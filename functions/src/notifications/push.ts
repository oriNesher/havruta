import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {INVITE_LINK_BASE_URL} from "../invites/config";

/** FCM's per-call limit for sendEachForMulticast. */
const MAX_TOKENS_PER_CALL = 500;

/** Result of a push fan-out. */
export interface PushResult {
  tokenCount: number;
  successCount: number;
  failureCount: number;
}

/**
 * Splits a list into chunks of at most `size`.
 * @param {Array<T>} items The items.
 * @param {number} size Max chunk size.
 * @return {Array<Array<T>>} The chunks, in order.
 * @template T
 */
export function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/**
 * Sends one notification to every device of the given users — native app
 * and (once enabled) web push alike, since both register into
 * users/{uid}.fcmTokens. Batches past FCM's 500-token limit, and prunes
 * tokens FCM reports as dead from their owner's doc.
 * @param {string[]} uids Recipients.
 * @param {object} notification What to show.
 * @param {string} notification.title Notification title.
 * @param {string} notification.body Notification body.
 * @param {Record<string, string>} data Data payload for the app.
 * @return {Promise<PushResult>} Delivery counts.
 */
export async function pushToUsers(
  uids: string[],
  notification: {title: string; body: string},
  data: Record<string, string>
): Promise<PushResult> {
  const db = admin.firestore();
  const unique = [...new Set(uids)];
  const userSnaps = unique.length === 0 ? [] :
    await db.getAll(...unique.map((uid) => db.collection("users").doc(uid)));

  const ownerOf = new Map<string, string>();
  for (const snap of userSnaps) {
    const tokens = snap.data()?.fcmTokens;
    if (!Array.isArray(tokens)) continue;
    for (const token of tokens) {
      if (typeof token === "string" && token.trim()) {
        ownerOf.set(token, snap.id);
      }
    }
  }

  const tokens = [...ownerOf.keys()];
  const result: PushResult = {
    tokenCount: tokens.length,
    successCount: 0,
    failureCount: 0,
  };
  const dead = new Map<string, string[]>();

  for (const batch of chunk(tokens, MAX_TOKENS_PER_CALL)) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens: batch,
      notification,
      data,
      // Clicking a web notification opens the web app (native apps route
      // by the data payload instead).
      webpush: {fcmOptions: {link: `${INVITE_LINK_BASE_URL}/`}},
    });
    result.successCount += response.successCount;
    result.failureCount += response.failureCount;
    response.responses.forEach((resp, index) => {
      const code = resp.error?.code ?? "";
      if (code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered") {
        const token = batch[index];
        const owner = ownerOf.get(token);
        if (owner) dead.set(owner, [...(dead.get(owner) ?? []), token]);
      }
    });
  }

  await Promise.all([...dead.entries()].map(([uid, stale]) =>
    db.collection("users").doc(uid).update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...stale),
    })));
  if (dead.size > 0) {
    logger.info("Pruned dead push tokens", {users: dead.size});
  }
  return result;
}
