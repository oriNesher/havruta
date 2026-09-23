/** Most Respect a user can hold; mirrored in respect_store.dart. */
export const RESPECT_WALLET_CAPACITY = 6;

/** What a daily grant does to the user's Respect wallet. */
export interface DailyGrantDecision {
  balance: number;
  /** Whether respectBalance/respectLastGrantDate should be written. */
  write: boolean;
}

/**
 * Decides a daily Respect grant. The first-ever call only starts the clock
 * (new users begin with an empty wallet), and a day's grant is forfeited —
 * not banked — while the wallet is full.
 * @param {object} input The user's current wallet state.
 * @param {number} input.balance Current respectBalance.
 * @param {string|undefined} input.lastGrantDate Last UTC grant date, if any.
 * @param {string} input.today Today's UTC date (YYYY-MM-DD).
 * @return {DailyGrantDecision} The resulting balance and whether to write.
 */
export function decideDailyGrant(input: {
  balance: number;
  lastGrantDate: string | undefined;
  today: string;
}): DailyGrantDecision {
  const {balance, lastGrantDate, today} = input;
  if (lastGrantDate === today) return {balance, write: false};
  if (lastGrantDate === undefined || balance >= RESPECT_WALLET_CAPACITY) {
    return {balance, write: true};
  }
  return {balance: balance + 1, write: true};
}
