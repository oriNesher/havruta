/// Every first-time feature tip, in priority order: when several could show
/// on the same screen at once, the earliest one here wins and the rest wait
/// for a later visit.
///
/// [id] is what's persisted in `users/{uid}.seenTips` — never rename one,
/// or everyone who already saw that tip sees it again.
enum FeatureTip {
  /// Create Challenge's "How do you win?" options.
  challengeGoal(
    id: 'challengeGoal',
    title: 'One goal, everyone in',
    message:
        'Everyone in a Challenge works toward the same goal. Not sure how '
        'to win it? Race is the simplest way to start.',
  ),

  /// The invite-link card, after creating a Challenge or on its details.
  inviteLink(
    id: 'inviteLink',
    title: 'Bring your friends',
    message:
        "Friends who aren't on Havruta yet can still join — the link gets "
        'them in, even if they install the app first.',
  ),

  /// A Challenge's Add Progress button (Home card or details).
  addProgress(
    id: 'addProgress',
    title: 'Log your progress',
    message:
        'Tap here whenever you make progress. Everyone in the Challenge '
        'sees it.',
  ),

  /// A Last One Standing Challenge's daily-minimum chip on Home.
  dailyMinimum(
    id: 'dailyMinimum',
    title: "Don't miss a day",
    message:
        'Hit this minimum every day to stay in. Miss one and you\'re out — '
        'the last one left wins.',
  ),

  /// The Give Respect button on someone else's event.
  giveRespect(
    id: 'giveRespect',
    title: 'Give Respect',
    message:
        "Respect is how you cheer someone on. You get one a day, so save it "
        'for when it\'s earned.',
  ),

  /// The Aggressor Badge, wherever it first appears.
  aggressor(
    id: 'aggressor',
    title: 'The Aggressor',
    message:
        "This badge goes to whoever's pushing hardest lately. Tap it any "
        'time to see how it works.',
  ),

  /// Trash Talk's Share button.
  trashTalk(
    id: 'trashTalk',
    title: 'Talk a little trash',
    message:
        'A bit of friendly rivalry raises the stakes. Make the message '
        'yours, then share it with the group.',
  );

  final String id;
  final String title;
  final String message;

  const FeatureTip({
    required this.id,
    required this.title,
    required this.message,
  });
}
