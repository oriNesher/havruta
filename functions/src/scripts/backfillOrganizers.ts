// One-off: gives every challenge created before the organizer role an
// explicit organizerUids = [createdBy]. Not needed for correctness —
// firestore.rules, parseChallenge and Challenge.fromDoc already treat a
// missing organizerUids as the creator — but it makes "challenges I
// organize" queries (organizerUids array-contains) complete. The creator
// stays a participant; nothing else changes. Idempotent; dry run unless
// --apply is passed.
//
//   npm run build
//   node lib/scripts/backfillOrganizers.js            # dry run
//   node lib/scripts/backfillOrganizers.js --apply
//
// Credentials as for backfillPublicProfiles.js.
import * as admin from "firebase-admin";
import {organizersToBackfill} from "../organizer/organizers";

/**
 * Backfills organizerUids on every challenge that lacks it.
 * @param {boolean} apply Write; otherwise only count.
 * @return {Promise<void>} Resolves once done.
 */
async function main(apply: boolean): Promise<void> {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT ?? "havruta-app"});
  const db = admin.firestore();
  const competitions = await db.collection("competitions").get();

  const writer = db.bulkWriter();
  let migrated = 0;
  for (const doc of competitions.docs) {
    const organizerUids = organizersToBackfill(doc.data());
    if (!organizerUids) continue;
    migrated++;
    if (apply) writer.update(doc.ref, {organizerUids});
  }
  await writer.close();

  console.log(
    `${apply ? "Migrated" : "Would migrate"} ${migrated} of ` +
      `${competitions.size} challenges.`
  );
}

main(process.argv.includes("--apply")).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
