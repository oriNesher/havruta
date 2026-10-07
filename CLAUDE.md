# Havruta

Havruta turns personal goals into social competitions: a user defines a
measurable target, invites friends, and everyone logs their own progress
toward it. The core loop is progress → activity event → celebration/Respect
— the social payoff is the point, not a bolt-on.

Every challenge has one shared goal (`sharedGoalTitle`/`sharedUnit`) and a
`winCondition` deciding how it's won: `firstToTarget` (Race — first to
`sharedTargetValue`), `lastStanding` (Last One Standing — meet
`rules.dailyMinimum` every challenge day or you're eliminated), or
`mostProgress` (most total by `endsAt`). Extra constraints live in the
`rules` map; a new mode is a new win condition plus a module in
`functions/src/challenges/winConditions/`, not a new challenge system.
Interpret a competition doc only through `parseChallenge`
(`functions/src/challenges/model.ts`) / `Challenge.fromDoc`
(`lib/competitions/challenge.dart`) — hand-synced mirrors, like the
standings and day-key logic next to them. Docs without `winCondition` are
legacy races; `type: 'personalGoalChallenge'` ones are legacy per-participant
races (no new ones are created; `type` is still written only for old
builds). Outcomes (`winnerUids`, `status: completed`, eliminations) are
server-written: race finishes in the progress trigger, everything
time-based in the hourly `settleChallenges` job.
**User-facing copy should consistently say "Challenge"**, even though
internal identifiers (collection names, `CompetitionDetailsScreen`,
`competitionId`, etc.) still say "competition" — that's legacy naming, not
something to rename wholesale unless explicitly asked.

## Architecture

- Flutter client (`lib/`) + Firebase backend: Firestore (`firestore.rules`),
  Cloud Functions (`functions/`, TypeScript), Hosting (`web/`) serving the
  invite landing page and the App/Universal Links `.well-known` files.
- State management is `StatefulWidget` + Firestore `Stream`/`FutureBuilder`,
  plain `Navigator.push`, and two singleton `ChangeNotifier` stores
  (`RespectStore`, `ProgressSnapshotCache`) for cross-widget state.
  `riverpod` and `go_router` are pubspec dependencies but are not part of
  this architecture — don't adopt them for new code; only introduce them as
  part of an explicitly-requested state-management/navigation migration.
- Trust boundary: cosmetic fields (streak count, `lastOpenedDate`) are
  written directly by the client. Anything socially visible or currency-like
  (Respect balance, invite redemption, celebration state) goes through a
  Cloud Functions callable inside a transaction — never a direct client
  write. Preserve this split for new features.
- The events pipeline (`functions/src/events/`) drives Activity,
  Celebrations, and Respect: every progress write triggers
  `onParticipantProgressCreateEvents`, which builds an `EventsContext` and
  runs it through independent rule modules (`rules/*.ts`) that each return
  `EventDraft[]`. Drafts from one trigger share a `batchId`, which is how the
  client groups several event types into one celebration screen. Add a new
  event type as a new rule module; update `celebrationTypes.ts` and its
  hand-synced Dart mirror (`lib/celebrations/celebration_types.dart`) if it
  should be celebration-eligible.

## Conventions

- Small private widgets (`_Foo`) live in the file of the screen that uses
  them; promote to `widgets/` only once actually reused elsewhere.
- Progress/currency writes use `FieldValue.increment` or a Firestore
  transaction, never read-modify-write — rapid repeated taps (quick-add
  chips, Respect spends) are expected usage.
- Use `lib/app_theme.dart`'s helpers (`AppTheme.display` for headings,
  `AppTheme.mono` for numbers/stats) instead of hardcoding text styles.
- Hard-to-undo, progress-altering writes get deliberate friction (see the
  hold-to-submit gesture on Add Progress) — match this for similar actions
  rather than a plain tap.

## Workflows (definition of done)

- Cloud Functions changes: `npm run lint` (Google TS style, required JSDoc
  on exports) must pass, and `npm run test` — the real test coverage, in
  `functions/src/events/__tests__/` — must include a case for any changed
  event rule.
- Flutter side has no working automated test suite to lean on; verify
  changes with `flutter analyze` plus a manual/visual check, not by trusting
  `flutter test`.
- Android release prep: use the `release-agent` subagent rather than doing
  it by hand.
- iOS-native changes (Xcode project, entitlements, `Podfile`, signing) can
  only be verified by actually building if Xcode and `pod install` are
  available in the current environment — check before claiming a build or
  archive succeeded. When they aren't available, verify statically
  (file/plist/pbxproj correctness) and say so explicitly rather than
  asserting a build worked.

## Havruta Feature Atlas

The structured inventory of every user-facing feature (status, location,
conditions, dependencies) is a published Claude artifact, not a repo file:
`https://claude.ai/code/artifact/4686e6d1-d006-418b-9ba4-989eb8db4dd4`. It
has no local source across sessions — `Artifact(action: "read", url: ...)`
to fetch current content before editing, then republish with the same
`url`.

**IMPORTANT:** whenever a feature is added, or an existing feature's
behavior, visibility, location, or dependencies meaningfully change, update
the Feature Atlas in the same session. Treat this as part of finishing the
change, not a follow-up.

## Working style

**IMPORTANT:** before starting non-trivial feature work, briefly surface
high-value improvements, extensions, or edge cases worth considering — even
if not explicitly asked. Keep it short. Never expand implementation scope to
include them without explicit approval; suggest, then wait.
