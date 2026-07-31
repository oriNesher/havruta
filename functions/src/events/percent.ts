/**
 * Rounds a 0-1 progress fraction to a whole percent, so ranking comparisons
 * aren't fooled by floating-point noise or participants with different
 * target values that are "basically tied" but never divide to equal floats.
 * @param {number} fraction A progress/targetValue ratio.
 * @return {number} The nearest whole percent.
 */
export function toWholePercent(fraction: number): number {
  return Math.round(fraction * 100);
}
