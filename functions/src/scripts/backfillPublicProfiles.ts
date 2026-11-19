// One-off: creates publicProfiles/{uid} for every existing users/{uid}, so
// users who haven't opened the app since syncPublicProfile shipped are
// still findable by username and show their names. Idempotent; dry run
// unless --apply is passed.
//
//   npm run build
//   node lib/scripts/backfillPublicProfiles.js            # dry run
//   node lib/scripts/backfillPublicProfiles.js --apply
//
// Credentials: Application Default Credentials for project havruta-app
// (GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>), or set
// FIRESTORE_EMULATOR_HOST to run it against the emulator.
import * as admin from "firebase-admin";
import {publicProfileFor} from "../users/publicProfile";

/**
 * Mirrors every users doc into publicProfiles.
 * @param {boolean} apply Write the profiles; otherwise only count them.
 * @return {Promise<void>} Resolves once done.
 */
async function main(apply: boolean): Promise<void> {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT ?? "havruta-app"});
  const db = admin.firestore();
  const users = await db.collection("users").get();

  const writer = db.bulkWriter();
  let mirrored = 0;
  let skipped = 0;
  for (const doc of users.docs) {
    const profile = publicProfileFor(doc.id, doc.data());
    if (!profile) {
      skipped++;
      continue;
    }
    mirrored++;
    if (apply) writer.set(db.collection("publicProfiles").doc(doc.id), profile);
  }
  await writer.close();

  console.log(
    `${apply ? "Wrote" : "Would write"} ${mirrored} public profiles ` +
      `(${skipped} users without a username skipped).`
  );
}

main(process.argv.includes("--apply")).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
