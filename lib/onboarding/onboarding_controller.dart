import 'dart:async';

import 'package:flutter/material.dart';

import 'modules/accept_invites_module.dart';
import 'modules/celebration_trash_talk_module.dart';
import 'modules/onboarding_module.dart';
import 'modules/report_progress_module.dart';
import 'onboarding_anchor.dart';
import 'onboarding_ids.dart';
import 'onboarding_repository.dart';
import 'onboarding_state.dart';
import 'onboarding_welcome_dialog.dart';

/// The single place that decides what onboarding is doing right now.
///
/// Screens stay ignorant of onboarding: they expose [OnboardingAnchor]s and
/// keep firing their normal product events. This controller loads the
/// user's persisted tutorial progress, runs at most one [OnboardingModule]
/// at a time, and publishes that module's guidance; OnboardingGuideLayer
/// renders whichever part of it applies to the screen the user is on.
///
/// Adding a tutorial later means adding a module and listing it in
/// [narrative] — no changes to Home, Notifications, or this class's flow.
class OnboardingController extends ChangeNotifier
    implements OnboardingModuleHost {
  OnboardingController._();
  static final OnboardingController instance = OnboardingController._();

  /// The order the guided narrative ("Yes, show me") runs modules in.
  /// Later parts append here; on every resume the first module that isn't
  /// completed becomes the active one, so a user who stopped mid-narrative
  /// picks up where they left off and finished modules are never replayed.
  static const List<OnboardingModuleId> narrative = [
    OnboardingModuleId.acceptInvites,
    OnboardingModuleId.reportProgress,
    OnboardingModuleId.celebrationTrashTalk,
  ];

  /// Modules that always run straight after another, whether or not the
  /// guided narrative is on: the Celebration/Trash Talk tutorial explains
  /// the celebration that Module 2's win itself produces, so starting
  /// Module 2 on its own (e.g. from a future checklist) must carry on into
  /// it rather than leave that celebration unexplained.
  static const Map<OnboardingModuleId, OnboardingModuleId> _continuations = {
    OnboardingModuleId.reportProgress: OnboardingModuleId.celebrationTrashTalk,
  };

  static OnboardingModule _createModule(OnboardingModuleId id) => switch (id) {
    OnboardingModuleId.acceptInvites => AcceptInvitesModule(),
    OnboardingModuleId.reportProgress => ReportProgressModule(),
    OnboardingModuleId.celebrationTrashTalk => CelebrationTrashTalkModule(),
  };

  /// Used to show the Welcome prompt and to unwind back to Home without a
  /// screen having to hand onboarding a BuildContext.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  final OnboardingRepository repository = OnboardingRepository();

  String? _uid;
  bool _loaded = false;
  OnboardingTutorialState _state = OnboardingTutorialState.empty;
  OnboardingModule? _activeModule;
  bool _welcomePresenting = false;
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

  /// True only between "this user has never answered the Welcome prompt"
  /// and their answer being recorded. False for everyone else, which is
  /// what keeps the guide layer inert for users not in onboarding.
  bool get wantsWelcome =>
      _loaded &&
      _state.welcome == null &&
      _activeModule == null &&
      !_welcomePresenting;

  List<OnboardingGuidance> get guidance =>
      _activeModule?.guidance ?? const <OnboardingGuidance>[];

  /// Whether the guide layer has any reason to inspect anchors at all.
  bool get isGuiding => wantsWelcome || guidance.isNotEmpty;

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
    _welcomePresenting = false;
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
    _activate(_createModule(target));
  }

  OnboardingModuleId? _nextModuleId() {
    final explicit = _state.activeModule;
    if (explicit != null &&
        _state.statusOf(explicit) != OnboardingModuleStatus.completed) {
      return explicit;
    }
    if (_state.welcome == OnboardingWelcomeChoice.accepted) {
      for (final id in narrative) {
        if (_state.statusOf(id) != OnboardingModuleStatus.completed) return id;
      }
    }
    return null;
  }

  void _activate(OnboardingModule module) {
    _activeModule = module;
    if (_state.activeModule != module.id ||
        _state.statusOf(module.id) != OnboardingModuleStatus.active) {
      _save(
        _state
            .copyWith(activeModule: module.id)
            .withModuleStatus(module.id, OnboardingModuleStatus.active),
      );
    }
    module.start(this);
  }

  /// Starts (or restarts) one module on its own — how the Welcome "Yes"
  /// path begins, and how a Home onboarding checklist will later launch an
  /// individual tutorial. Throws if the module can't be prepared.
  Future<void> startModule(OnboardingModuleId id) async {
    if (_uid == null) return;
    final session = _session;
    final module = _createModule(id);
    await module.prepare(this);
    if (session != _session) return;
    _activeModule?.stop();
    _activeModule = null;
    _activate(module);
    notifyListeners();
  }

  @override
  void guidanceChanged() => notifyListeners();

  @override
  void moduleCompleted(OnboardingModule module) {
    if (!identical(module, _activeModule)) return;
    module.stop();
    _activeModule = null;
    final next = _continuations[module.id];
    final continueWith =
        next != null &&
            _state.statusOf(next) != OnboardingModuleStatus.completed
        ? next
        : null;
    // Persisting the continuation as the explicit active module (in the
    // same write that completes this one) is what makes a relaunch between
    // the two resume into it.
    _save(
      _state
          .copyWith(
            activeModule: continueWith,
            clearActiveModule: continueWith == null,
          )
          .withModuleStatus(module.id, OnboardingModuleStatus.completed),
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
      // Whatever the narrative offers next starts here. After the last
      // available module (Celebration/Trash Talk, in Part 3) the guide
      // simply stops.
      _resume();
      notifyListeners();
    }());
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

  // ── Welcome prompt ────────────────────────────────────────────────────

  /// Called by the guide layer once Home is the settled, top-most screen.
  Future<void> presentWelcome() async {
    if (!wantsWelcome) return;
    _welcomePresenting = true;
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
    if (session != _session ||
        context == null ||
        !context.mounted ||
        !homeSettled ||
        _state.welcome != null) {
      // Not the right moment after all — retried on a later frame.
      if (session == _session) _welcomePresenting = false;
      return;
    }

    await showOnboardingWelcomeDialog(
      context: context,
      onAccept: acceptWelcome,
      onSkip: deferWelcome,
    );

    if (session != _session) return;
    _welcomePresenting = false;
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
    final first = narrative.first;
    await _createModule(first).prepare(this);
    if (session != _session) return;
    _save(_state.copyWith(welcome: OnboardingWelcomeChoice.accepted));
    _resume();
    notifyListeners();
  }

  /// "Skip": deferred, not dismissed — the modules stay available to run
  /// individually later, and the prompt itself never comes back.
  void deferWelcome() {
    if (_uid == null) return;
    _save(_state.copyWith(welcome: OnboardingWelcomeChoice.deferred));
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

  /// TEMPORARY: marks [ids] not started (and makes the first of them the
  /// active module) so they replay, without touching Welcome or earlier
  /// modules. Explicit `notStarted` entries are written rather than keys
  /// removed, because saves merge into Firestore. [whileDetached] runs
  /// with no module watching (e.g. a backend reset), so nothing reacts to
  /// the records it rewrites.
  Future<void> debugResetModules(
    List<OnboardingModuleId> ids, {
    Future<void> Function()? whileDetached,
  }) async {
    final uid = _uid;
    if (uid == null || ids.isEmpty) return;
    var next = _state.copyWith(activeModule: ids.first);
    for (final id in ids) {
      next = next.withModuleStatus(id, OnboardingModuleStatus.notStarted);
    }
    _detach();
    _uid = uid;
    notifyListeners();
    try {
      if (whileDetached != null) await whileDetached();
      await repository.saveState(uid, next);
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
    'guidance': guidance
        .map((g) => '${g.anchorIds.join(' + ')} => "${g.message}"')
        .toList(),
    'mountedAnchors': OnboardingAnchorRegistry.instance.mountedIds.toList(),
    if (_activeModule != null) ..._activeModule!.debugDescribe(),
  };
}
