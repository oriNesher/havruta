/// The empowering lines shown in the gap above the hold-to-submit button
/// while a hold is in progress.
///
/// The hold is four seconds of deliberate friction (see _HoldToSubmitButton)
/// — this fills that pause with a reason to want it instead of a countdown
/// to endure. Every line opens with "Take a moment to…" so the gap reads as
/// one recurring ritual, while the rest rotates on each submission (see
/// HoldStatementStore) so the ritual never turns into wallpaper.
///
/// Keep them short enough to finish reading inside one hold, and keep them
/// about the person rather than the number.
const List<String> kHoldStatements = [
  'Take a moment to feel this one. You earned it.',
  'Take a moment to notice that you showed up again.',
  'Take a moment to remember why you started this.',
  'Take a moment to be proud of the you that did not quit.',
  'Take a moment to let this count, because it does.',
  'Take a moment to trust that consistency beats intensity.',
  'Take a moment to see what real progress actually looks like.',
  'Take a moment to own choosing the harder thing today.',
  'Take a moment to thank yesterday-you for making this easier.',
  'Take a moment to notice how much closer you are than last week.',
  'Take a moment to claim this one. Nobody did it for you.',
  'Take a moment to breathe, then watch the bar move.',
  'Take a moment to recognize the habit forming under you.',
  'Take a moment to enjoy being the one who keeps going.',
];
