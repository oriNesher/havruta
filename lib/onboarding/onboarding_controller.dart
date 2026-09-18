import 'dart:async';

import 'package:flutter/material.dart';

import 'modules/onboarding_module.dart';
import 'onboarding_anchor.dart';
import 'onboarding_completion_dialog.dart';
import 'onboarding_ids.dart';
import 'onboarding_registry.dart';
import 'onboarding_repository.dart';
import 'onboarding_state.dart';
import 'onboarding_welcome_dialog.dart';

/// How one module shows up in the Home onboarding checklist right now.
enum OnboardingChecklistItemState {
  /// Never started at its current version: "Start".
  notStarted,

  /// Started before and left unfinished ("Not now"): "Continue".
  deferred,

  /// The module being guided right now — offered no second launch.
  inProgress,
}

@immutable
class OnboardingChecklistItem {
  final OnboardingModuleDefinition definition;
  final OnboardingChecklistItemState state;

  const OnboardingChecklistItem({
    required this.definition,
    required this.state,
  });

  OnboardingModuleId get id => definition.id;
  OnboardingChecklistEntry get entry => definition.checklist!;
}

/// The single place that decides what onboarding is doing right now.
///
/// Screens stay ignorant of onboarding: they expose [OnboardingAnchor]s and
/// keep firing their normal product events. This controller loads the
/// user's persisted tutorial progress, runs at most one [OnboardingModule]
/// at a time, and publishes that module's guidance; OnboardingGuideLayer
/// renders whichever part of it applies to the screen the user is on.
///
/// Modules come from [OnboardingModuleRegistry]; the same module serves the
/// initial guided [narrative] and a later individual launch ([startModule],
/// e.g. from the Home checklist, which [checklist] derives centrally).
class OnboardingController extends ChangeNotifier
    implements OnboardingModuleHost {
  OnboardingController._();
  static final OnboardingController instance = OnboardingController._();

  /// The order the initial guided narrative ("Yes, show me") runs modules
  /// in. While it's in progress, every resume makes the first module not
  /// yet done the active one, so a user who stopped mid-narrative picks up
  /// where they left off and finished modules are never replayed. Once it
  /// has finished it never runs again — later modules and new versions
  /// surface individually through the checklist instead.
  static const List<OnboardingModuleId> narrative = [
    OnboardingModuleId.acceptInvites,
    OnboardingModuleId.reportProgress,
    OnboardingModuleId.celebrationTrashTalk,
    OnboardingModuleId.eventsRespect,
    OnboardingModuleId.createChallenge,
    OnboardingModuleId.invitePeople,
  ];

  /// The exit offered on individually launched modules' guidance.
  static const finishLaterLabel = 'Finish later';

  /// Used to show the Welcome prompt and to unwind back to Home without a
  /// screen having to hand onboarding a BuildContext.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  final OnboardingRepository repository = OnboardingRepository();

  String? _uid;
  bool _loaded = false;
  OnboardingTutorialState _state = OnboardingTutorialState.empty;
  OnboardingModule? _activeModule;
  bool _promptPresenting = false;
  ModalRoute<dynamic>? _lastGuidedRoute;

  /// Bumped on every user change/reset so async work started for a previous
  /// session can't land on the current one.
  int _session = 0;

  @override
  String get uid => _uid!;

  String? get currentUid => _uid;
  bool get isLoaded => _loaded;
  OnboardingTutorialState get state => _state;
  OnboardingModule? get activeModule => _activeModule;

  // ── Module status (versioned) ─────────────────────────────────────────

  /// [id]'s status for its current registry version — completing or
  /// dismissing an older version reads as not started.
  OnboardingModuleStatus statusOf(OnboardingModuleId id) => _statusIn(_state, id);

  static OnboardingModuleStatus _statusIn(
    OnboardingTutorialState state,
    OnboardingModuleId id,
  ) {
    return state
        .progressOf(id)
        .effectiveStatus(
          OnboardingModuleRegistry.versionOf(id),
          dismissAllVersions: OnboardingModuleRegistry.of(
            id,
          ).dismissAllVersions,
        );
  }

  static bool _resolvedIn(OnboardingTutorialState state, OnboardingModuleId id) {
    final status = _statusIn(state, id);
    return status == OnboardingModuleStatus.completed ||
        status == OnboardingModuleStatus.dismissed;
  }

  /// A narrative step is done once completed at any version (a newer
  /// version of it must not rewind the narrative) or currently dismissed.
  static bool _narrativeStepDoneIn(
    OnboardingTutorialState state,
    OnboardingModuleId id,
  ) =>
      state.progressOf(id).everCompleted ||
      _statusIn(state, id) == OnboardingModuleStatus.dismissed;

  static bool _narrativeInProgressIn(OnboardingTutorialState state) =>
      state.welcome == OnboardingWelcomeChoice.accepted &&
      state.narrative == null &&
      narrative.any((id) => !_narrativeStepDoneIn(state, id));

  /// The user chose the guided narrative and it hasn't finished. While
  /// true, modules run in [narrative] order and the checklist stays away.
  bool get narrativeInProgress => _narrativeInProgressIn(_state);

  OnboardingEligibilityContext get _eligibilityContext =>
      OnboardingEligibilityContext(state: _state, statusOf: statusOf);

  bool isEligible(OnboardingModuleId id) =>
      OnboardingModuleRegistry.of(id).eligibleIn(_eligibilityContext);

  // ── Prompts (Welcome, final completion message) ───────────────────────

  /// True only between "this user has never answered the Welcome prompt"
  /// and their answer being recorded. False for everyone else, which is
  /// what keeps the guide layer inert for users not in onboarding.
  bool get wantsWelcome =>
      _loaded &&
      _state.welcome == null &&
      _activeModule == null &&
      !_promptPresenting;

  /// The initial narrative was genuinely completed and its final message
  /// hasn't been acknowledged yet.
  bool get wantsCompletionMessage =>
      _loaded &&
      _state.narrative == OnboardingNarrativeStatus.completed &&
      _activeModule == null &&
      !_promptPresenting;

  /// A prompt is owed, to be shown once Home is the settled top screen.
  bool get wantsPrompt => wantsWelcome || wantsCompletionMessage;

  List<OnboardingGuidance> get guidance {
    final module = _activeModule;
    if (module == null) return const <OnboardingGuidance>[];
    final raw = module.guidance;
    if (narrativeInProgress) return raw;
    // Run on its own (e.g. from the checklist): every bubble gets a way
    // out, so a modal spotlight never traps someone who changed their mind.
    final finishLater = OnboardingGuidanceAction(
      label: finishLaterLabel,
      primary: false,
      onPressed: () => deferModule(module.id),
    );
    return [
      for (final entry in raw)
        entry.message.isEmpty
            ? entry
            : entry.withActions([...entry.actions, finishLater]),
    ];
  }

  /// Whether the guide layer has any reason to inspect anchors at all.
  bool get isGuiding => wantsPrompt || guidance.isNotEmpty;

  // ── Home checklist ────────────────────────────────────────────────────

  /// Whether Home should show the onboarding checklist at all: once the
  /// Welcome prompt was answered, and never alongside the guided narrative
  /// or its pending final message. Still true after the narrative has
  /// finished, so modules added or updated later can surface.
  bool get showsChecklist =>
      _loaded &&
      _uid != null &&
      _state.welcome != null &&
      !narrativeInProgress &&
      _state.narrative != OnboardingNarrativeStatus.completed;

  /// The checklist, in registry order: every checklist module that is
  /// unresolved for its current version and eligible right now. Empty
  /// whenever [showsChecklist] is false.
  List<OnboardingChecklistItem> get checklist {
    if (!showsChecklist) return const [];
    final context = _eligibilityContext;
    final items = <OnboardingChecklistItem>[];
    for (final definition in OnboardingModuleRegistry.definitions) {
      if (definition.checklist == null) continue;
      final OnboardingChecklistItemState itemState;
      if (_activeModule?.id == definition.id) {
        itemState = OnboardingChecklistItemState.inProgress;
      } else {
        switch (statusOf(definition.id)) {
          case OnboardingModuleStatus.completed:
          case OnboardingModuleStatus.dismissed:
            continue;
          case OnboardingModuleStatus.notStarted:
            itemState = OnboardingChecklistItemState.notStarted;
          // Persisted active but not running (interrupted) reads as left.
          case OnboardingModuleStatus.active:
          case OnboardingModuleStatus.deferred:
            itemState = OnboardingChecklistItemState.deferred;
        }
        if (!definition.eligibleIn(context)) continue;
      }
      items.add(
        OnboardingChecklistItem(definition: definition, state: itemState),
      );
    }
    return items;
  }

  // ── Session lifecycle ─────────────────────────────────────────────────

  /// Called when the user reaches the real Home experience.
  Future<void> attachUser(String uid) async {
    if (_uid == uid) return;
    _detach();
    _uid = uid;
    await _load();
  }

  /// Called on sign-out.
  void reset() {
    _detach();
    notifyListeners();
  }

  /// Re-reads persisted progress, the way a fresh app launch would.
  Future<void> reload() async {
    final uid = _uid;
    if (uid == null) return;
    _detach();
    _uid = uid;
    notifyListeners();
    await _load();
  }

  void _detach() {
    _session++;
    _activeModule?.stop();
    _activeModule = null;
    _uid = null;
    _loaded = false;
    _state = OnboardingTutorialState.empty;
    _promptPresenting = false;
    _lastGuidedRoute = null;
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    final session = _session;
    try {
      final loaded = await repository.loadState(uid);
      if (session != _session) return;
      _state = loaded;
      _loaded = true;
      _recordNarrativeCompletionIfDue();
      _resume();
      notifyListeners();
    } catch (e) {
      // Fail closed: with no idea where the user is, show no onboarding at
      // all rather than risk re-showing Welcome or replaying a finished
      // step. Clearing _uid lets the next Home entry retry.
      debugPrint('Onboarding state load error: $e');
      if (session == _session) _uid = null;
    }
  }

  // ── Module orchestration ──────────────────────────────────────────────

  void _resume() {
    final target = _nextModuleId();
    if (_activeModule?.id == target) return;
    _activeModule?.stop();
    _activeModule = null;
    if (target == null) return;
    _activate(OnboardingModuleRegistry.of(target).create());
  }

  OnboardingModuleId? _nextModuleId() {
    final explicit = _state.activeModule;
    if (explicit != null && !_resolvedIn(_state, explicit)) return explicit;
    if (narrativeInProgress) {
      for (final id in narrative) {
        if (!_narrativeStepDoneIn(_state, id)) return id;
      }
    }
    return null;
  }

  void _activate(OnboardingModule module) {
    final id = module.id;
    _activeModule = module;
    var next = _state;
    if (statusOf(id) == OnboardingModuleStatus.notStarted &&
        next.dataOf(id).isNotEmpty) {
      // A fresh run at this version: durable facts from an earlier run
      // (e.g. an old tracked Challenge) must not carry into it. Issued
      // before the save below, so Firestore applies them in that order.
      next = next.withoutModuleData([id]);
      unawaited(
        repository.clearModuleData(uid, [id]).catchError((Object e) {
          debugPrint('Onboarding module data clear error: $e');
        }),
      );
    }
    if (next.activeModule != id ||
        statusOf(id) != OnboardingModuleStatus.active) {
      next = next
          .copyWith(activeModule: id)
          .withModuleStatus(
            id,
            OnboardingModuleStatus.active,
            version: OnboardingModuleRegistry.versionOf(id),
          );
    }
    if (!identical(next, _state)) _save(next);
    module.start(this);
  }

  /// Starts (or restarts) one module on its own — how the Welcome "Yes"
  /// path begins and how the Home checklist launches an individual
  /// tutorial. A module that was running is left as deferred, not lost.
  /// Throws if the module can't be prepared.
  Future<void> startModule(OnboardingModuleId id) async {
    if (_uid == null) return;
    final session = _session;
    final module = OnboardingModuleRegistry.of(id).create();
    await module.prepare(this);
    if (session != _session) return;
    final previous = _activeModule;
    _activeModule = null;
    previous?.stop();
    if (previous != null && previous.id != id) {
      _save(
        _state.withModuleStatus(
          previous.id,
          OnboardingModuleStatus.deferred,
          version: OnboardingModuleRegistry.versionOf(previous.id),
        ),
      );
    }
    _activate(module);
    notifyListeners();
  }

  /// "Not now": stops [id] if it's running and keeps it in the checklist.
  void deferModule(OnboardingModuleId id) =>
      _setByUser(id, OnboardingModuleStatus.deferred);

  /// "I don't want to see this": stops [id] if it's running and hides it
  /// for its current version.
  void dismissModule(OnboardingModuleId id) =>
      _setByUser(id, OnboardingModuleStatus.dismissed);

  void _setByUser(OnboardingModuleId id, OnboardingModuleStatus status) {
    if (_uid == null) return;
    if (_activeModule?.id == id) {
      _activeModule!.stop();
      _activeModule = null;
    }
    var next = _state.withModuleStatus(
      id,
      status,
      version: OnboardingModuleRegistry.versionOf(id),
    );
    if (next.activeModule == id) next = next.copyWith(clearActiveModule: true);
    _save(next);
    notifyListeners();
  }

  @override
  void guidanceChanged() => notifyListeners();

  @override
  Map<String, Object?> moduleData(OnboardingModuleId id) => _state.dataOf(id);

  @override
  void saveModuleData(OnboardingModuleId id, Map<String, Object?> data) {
    if (_uid == null) return;
    _save(_state.withModuleData(id, data));
  }

  @override
  void moduleCompleted(OnboardingModule module) {
    if (!identical(module, _activeModule)) return;
    module.stop();
    _activeModule = null;
    final next = OnboardingModuleRegistry.of(module.id).continueWith;
    final continueWith = next != null && !_resolvedIn(_state, next)
        ? next
        : null;
    // Persisting the continuation as the explicit active module (in the
    // same write that completes this one) is what makes a relaunch between
    // the two resume into it; the narrative's completion rides along in
    // that write too, so it can't be lost to a relaunch either.
    _save(
      _withNarrativeCompletionIfDue(
        _state
            .copyWith(
              activeModule: continueWith,
              clearActiveModule: continueWith == null,
            )
            .withModuleStatus(
              module.id,
              OnboardingModuleStatus.completed,
              version: OnboardingModuleRegistry.versionOf(module.id),
            ),
      ),
    );
    notifyListeners();

    final session = _session;
    unawaited(() async {
      switch (module.unwindOnComplete) {
        case OnboardingUnwind.toHome:
          await _returnHome();
        case OnboardingUnwind.guidedRoute:
          await _popGuidedRoute();
        case OnboardingUnwind.none:
          break;
      }
      if (session != _session) return;
      // Whatever comes next (a continuation, or the narrative's next
      // module) starts here. After the narrative's last module nothing
      // does, and the final message is shown once Home settles.
      _resume();
      notifyListeners();
    }());
  }

  /// The narrative is genuinely complete once the user chose it and every
  /// narrative module was completed (dismissals don't count).
  static OnboardingTutorialState _withNarrativeCompletionIfDue(
    OnboardingTutorialState state,
  ) {
    if (state.welcome != OnboardingWelcomeChoice.accepted ||
        state.narrative != null ||
        !narrative.every((id) => state.progressOf(id).everCompleted)) {
      return state;
    }
    return state.copyWith(narrative: OnboardingNarrativeStatus.completed);
  }

  /// On load: records a completion the narrative write didn't carry — for
  /// users who finished all six modules before `narrative` existed.
  void _recordNarrativeCompletionIfDue() {
    final next = _withNarrativeCompletionIfDue(_state);
    if (!identical(next, _state)) _save(next);
  }

  /// Unwinds the screen the guide led the user onto (Notifications) back to
  /// Home, once the accept dialog it was used from has closed. Deliberately
  /// narrow: it never pops a route onboarding didn't guide the user to, so
  /// it can't swallow something like a celebration.
  Future<void> _returnHome() async {
    final route = _lastGuidedRoute;
    final navigator = navigatorKey.currentState;
    if (route == null || navigator == null || route.isFirst) return;

    final session = _session;
    for (var i = 0; i < 40; i++) {
      if (!route.isActive || session != _session) return;
      if (route.isCurrent) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!route.isActive || !route.isCurrent || session != _session) return;

    // Let the "Invite accepted" confirmation land before moving them.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!route.isActive || !route.isCurrent || session != _session) return;
    navigator.popUntil((r) => r.isFirst);
  }

  /// Pops just the screen the guide last pointed at (e.g. Trash Talk), the
  /// same as the user closing it, so whatever product flow pushed it
  /// unwinds itself normally — CelebrationScreen pops itself after Trash
  /// Talk, and CelebrationGate then marks the batch celebrated and moves
  /// its queue on. Never pops anything else.
  ///
  /// Waits for the app to be back in the foreground first: completing a
  /// module can coincide with the native share sheet (or the app the user
  /// shared to) being in front, and the user should see the screen they
  /// left before it goes away.
  Future<void> _popGuidedRoute() async {
    final route = _lastGuidedRoute;
    final navigator = navigatorKey.currentState;
    if (route == null || navigator == null || route.isFirst) return;

    final session = _session;
    bool ready() =>
        route.isCurrent &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

    // Generous: the user may take a while in another app after sharing.
    // If they close the screen themselves meanwhile, route.isActive ends it.
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (true) {
      while (!ready()) {
        if (!route.isActive || session != _session) return;
        if (DateTime.now().isAfter(deadline)) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      // A beat on the screen before it closes — and a re-check, in case the
      // share sheet was only just opening and took the foreground meanwhile.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!route.isActive || session != _session) return;
      if (ready()) break;
    }
    navigator.pop();
  }

  // ── Welcome / completion prompts ──────────────────────────────────────

  /// Called by the guide layer once Home is the settled, top-most screen
  /// and [wantsPrompt]: shows the Welcome prompt or the final completion
  /// message, whichever is owed.
  Future<void> presentPrompt() async {
    if (!wantsPrompt) return;
    final completion = wantsCompletionMessage;
    _promptPresenting = true;
    final session = _session;

    // A beat after Home settles, so the prompt doesn't collide with Home's
    // first paint or a celebration that is about to be pushed over it.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final context = navigatorKey.currentState?.overlay?.context;
    final homeSettled =
        OnboardingAnchorRegistry.instance.settled(
          OnboardingAnchorIds.homeScreen,
        ) !=
        null;
    final stillOwed = completion
        ? _state.narrative == OnboardingNarrativeStatus.completed &&
              _activeModule == null
        : _state.welcome == null;
    if (session != _session ||
        context == null ||
        !context.mounted ||
        !homeSettled ||
        !stillOwed) {
      // Not the right moment after all — retried on a later frame.
      if (session == _session) _promptPresenting = false;
      return;
    }

    if (completion) {
      await showOnboardingCompletionDialog(
        context: context,
        onDone: acknowledgeCompletion,
      );
    } else {
      await showOnboardingWelcomeDialog(
        context: context,
        onAccept: acceptWelcome,
        onSkip: deferWelcome,
      );
    }

    if (session != _session) return;
    _promptPresenting = false;
    notifyListeners();
  }

  /// "Yes, show me": creates the real onboarding challenges/invitations and
  /// waits for them to be confirmed before recording the choice, so a
  /// failure here leaves the prompt to be retried rather than stranding the
  /// user in a guide with nothing to point at. Throws on failure.
  Future<void> acceptWelcome() async {
    final uid = _uid;
    if (uid == null) return;
    final session = _session;
    await OnboardingModuleRegistry.of(narrative.first).create().prepare(this);
    if (session != _session) return;
    _save(_state.copyWith(welcome: OnboardingWelcomeChoice.accepted));
    _resume();
    notifyListeners();
  }

  /// "Skip": deferred, not dismissed — the modules stay available to run
  /// individually from the Home checklist, and the prompt itself never
  /// comes back.
  void deferWelcome() {
    if (_uid == null) return;
    _save(_state.copyWith(welcome: OnboardingWelcomeChoice.deferred));
    notifyListeners();
  }

  /// "Let's go" on the final message: the initial narrative is over for
  /// good. Module states are untouched, so later modules still surface.
  void acknowledgeCompletion() {
    if (_uid == null ||
        _state.narrative != OnboardingNarrativeStatus.completed) {
      return;
    }
    _save(_state.copyWith(narrative: OnboardingNarrativeStatus.acknowledged));
    notifyListeners();
  }

  // ── Guide layer callbacks ─────────────────────────────────────────────

  /// The guide layer is now showing [guidance] on [route]. Remembers the
  /// route (for unwinding) and tells the active module.
  void noteGuidanceShown(
    OnboardingGuidance guidance,
    ModalRoute<dynamic>? route,
  ) {
    _lastGuidedRoute = route;
    _activeModule?.guidanceShown(guidance);
  }

  // ── Persistence ───────────────────────────────────────────────────────

  void _save(OnboardingTutorialState next) {
    _state = next;
    final uid = _uid;
    if (uid == null) return;
    // Not awaited: Firestore only resolves a write on server ack, and the
    // tutorial has to keep moving offline. Local state is already updated;
    // the write lands when connectivity returns.
    unawaited(
      repository.saveState(uid, next).catchError((Object e) {
        debugPrint('Onboarding state save error: $e');
      }),
    );
  }

  // ── TEMPORARY (debug harness only) ────────────────────────────────────

  /// TEMPORARY: wipes this user's tutorial progress, and with
  /// [includeBackendData] also their onboarding challenges/invites, so the
  /// flow can be replayed. Remove with the onboarding debug screen.
  Future<Map<String, dynamic>?> debugResetTutorial({
    bool includeBackendData = false,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    // Detach first so the running module doesn't react to its own records
    // being deleted (and try to repair them) mid-reset.
    _detach();
    _uid = uid;
    notifyListeners();
    Map<String, dynamic>? result;
    if (includeBackendData) {
      result = await repository.resetOnboardingForTesting();
    }
    await repository.clearState(uid);
    await _load();
    return result;
  }

  /// TEMPORARY: marks [ids] not started — history included — and clears
  /// their module data so they replay, without touching Welcome or other
  /// modules. With [activate] the first of them becomes the active module.
  /// Explicit entries are written rather than keys removed, because saves
  /// merge into Firestore. [whileDetached] runs with no module watching
  /// (e.g. a backend reset), so nothing reacts to the records it rewrites.
  Future<void> debugResetModules(
    List<OnboardingModuleId> ids, {
    Future<void> Function()? whileDetached,
    bool activate = true,
  }) async {
    final uid = _uid;
    if (uid == null || ids.isEmpty) return;
    var next = _state.withoutModuleData(ids);
    if (activate) {
      next = next.copyWith(activeModule: ids.first);
    } else if (ids.contains(next.activeModule)) {
      next = next.copyWith(clearActiveModule: true);
    }
    for (final id in ids) {
      next = next.withModuleProgress(
        id,
        OnboardingModuleProgress(
          version: OnboardingModuleRegistry.versionOf(id),
        ),
      );
    }
    _detach();
    _uid = uid;
    notifyListeners();
    try {
      if (whileDetached != null) await whileDetached();
      await repository.clearModuleData(uid, ids);
      await repository.saveState(uid, next);
    } finally {
      await _load();
    }
  }

  /// TEMPORARY: records [status] for [id] at its current version, as if
  /// the user had done so (a running [id] is stopped first).
  void debugSetModuleStatus(
    OnboardingModuleId id,
    OnboardingModuleStatus status,
  ) {
    if (status == OnboardingModuleStatus.deferred ||
        status == OnboardingModuleStatus.dismissed) {
      _setByUser(id, status);
      return;
    }
    if (_uid == null) return;
    if (_activeModule?.id == id) {
      _activeModule!.stop();
      _activeModule = null;
    }
    var next = _state.withModuleStatus(
      id,
      status,
      version: OnboardingModuleRegistry.versionOf(id),
    );
    if (next.activeModule == id) next = next.copyWith(clearActiveModule: true);
    _save(next);
    notifyListeners();
  }

  /// TEMPORARY: sets (or clears) the narrative's completion state.
  void debugSetNarrative(OnboardingNarrativeStatus? status) {
    if (_uid == null) return;
    _save(
      _state.copyWith(narrative: status, clearNarrative: status == null),
    );
    notifyListeners();
  }

  /// TEMPORARY: deletes [id]'s persisted record entirely, as if the module
  /// had just been added to the app, then reloads.
  Future<void> debugForgetModule(OnboardingModuleId id) async {
    final uid = _uid;
    if (uid == null) return;
    _detach();
    _uid = uid;
    notifyListeners();
    try {
      await repository.debugDeleteModuleRecord(uid, id);
    } finally {
      await _load();
    }
  }

  /// TEMPORARY: snapshot of everything the debug screen inspects.
  Map<String, Object?> debugDescribe() => {
    'uid': _uid ?? '(none)',
    'loaded': _loaded,
    'persisted': _state.toString(),
    'activeModule': _activeModule?.id.name ?? '(none)',
    'wantsWelcome': wantsWelcome,
    'wantsCompletionMessage': wantsCompletionMessage,
    'narrativeInProgress': narrativeInProgress,
    'showsChecklist': showsChecklist,
    'checklist': checklist.map((i) => '${i.id.name}:${i.state.name}').toList(),
    'guidance': guidance
        .map((g) => '${g.anchorIds.join(' + ')} => "${g.message}"')
        .toList(),
    'mountedAnchors': OnboardingAnchorRegistry.instance.mountedIds.toList(),
    if (_activeModule != null) ..._activeModule!.debugDescribe(),
  };
}
