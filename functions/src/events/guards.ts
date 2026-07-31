/**
 * Returns the numeric values of a metadata field across every existing
 * event of a given type in this competition — used for one-time-per-value
 * guards like checkpoints or milestones, so they don't fire more than once.
 * @param {FirebaseFirestore.CollectionReference} eventsRef The competition's
 *   events subcollection.
 * @param {string} type The event type to look up.
 * @param {string} metadataField The metadata field holding the guard value.
 * @return {Promise<number[]>} The guard values that have already fired.
 */
export async function fetchFiredValues(
  eventsRef: FirebaseFirestore.CollectionReference,
  type: string,
  metadataField: string
): Promise<number[]> {
  const snap = await eventsRef.where("type", "==", type).get();

  return snap.docs
    .map((doc) => doc.data().metadata?.[metadataField])
    .filter((value): value is number => typeof value === "number");
}

/**
 * Counts existing events of any of the given types in this competition —
 * used to determine completion order for Won/Finished in Position.
 * @param {FirebaseFirestore.CollectionReference} eventsRef The competition's
 *   events subcollection.
 * @param {string[]} types The event types to count.
 * @return {Promise<number>} How many such events already exist.
 */
export async function countEvents(
  eventsRef: FirebaseFirestore.CollectionReference,
  types: string[]
): Promise<number> {
  const snap = await eventsRef.where("type", "in", types).get();
  return snap.size;
}
