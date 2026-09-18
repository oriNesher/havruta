import 'package:flutter/foundation.dart';

/// The user's answer to the Welcome prompt. Absent (null) until they answer.
enum OnboardingWelcomeChoice {
  /// "Yes, show me" — the guided narrative runs module by module.
  accepted,

  /// "Skip" — the guided narrative doesn't run, but nothing is dismissed:
  /// every module stays available to start individually later (the Home
  /// onboarding checklist, not built yet).
  deferred,
}

/// Every onboarding module. The guided order lives in
/// OnboardingController.narrative, not here.
enum OnboardingModuleId {
  acceptInvites,
  // Later parts add: reportProgress, celebrationTrashTalk, eventsRespect,
  // createChallenge, invitePeople, ...
}

enum OnboardingModuleStatus { notStarted, active, completed }

/// The user's persisted tutorial progress, stored as the
/// `users/{uid}.onboardingTutorial` map.
///
/// This is cosmetic, client-written state (like the streak): it only
/// decides which tutorial guidance to show. The real onboarding challenges
/// and invites are server-created (startOnboarding), and what a module
/// considers "done" is always re-derived from those real records.
@immutable
class OnboardingTutorialState {
  static const firestoreField = 'onboardingTutorial';
  static const schemaVersion = 1;

  final OnboardingWelcomeChoice? welcome;

  /// The module currently being guided, if any. Null between modules and
  /// after the last available module finishes.
  final OnboardingModuleId? activeModule;

  final Map<OnboardingModuleId, OnboardingModuleStatus> modules;

  const OnboardingTutorialState({
    this.welcome,
    this.activeModule,
    this.modules = const {},
  });

  static const empty = OnboardingTutorialState();

  OnboardingModuleStatus statusOf(OnboardingModuleId id) =>
      modules[id] ?? OnboardingModuleStatus.notStarted;

  OnboardingTutorialState copyWith({
    OnboardingWelcomeChoice? welcome,
    OnboardingModuleId? activeModule,
    bool clearActiveModule = false,
  }) {
    return OnboardingTutorialState(
      welcome: welcome ?? this.welcome,
      activeModule:
          clearActiveModule ? null : (activeModule ?? this.activeModule),
      modules: modules,
    );
  }

  OnboardingTutorialState withModuleStatus(
    OnboardingModuleId id,
    OnboardingModuleStatus status,
  ) {
    return OnboardingTutorialState(
      welcome: welcome,
      activeModule: activeModule,
      modules: {...modules, id: status},
    );
  }

  /// Unknown values (e.g. a module id written by a newer app version) are
  /// dropped here rather than failing; since saves merge, they also survive
  /// untouched in Firestore.
  factory OnboardingTutorialState.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;

    final modules = <OnboardingModuleId, OnboardingModuleStatus>{};
    final rawModules = map['modules'];
    if (rawModules is Map) {
      for (final entry in rawModules.entries) {
        final id = _byName(OnboardingModuleId.values, entry.key);
        final rawStatus = entry.value is Map ? entry.value['status'] : null;
        final status = _byName(OnboardingModuleStatus.values, rawStatus);
        if (id != null && status != null) modules[id] = status;
      }
    }

    return OnboardingTutorialState(
      welcome: _byName(OnboardingWelcomeChoice.values, map['welcome']),
      activeModule: _byName(OnboardingModuleId.values, map['activeModule']),
      modules: modules,
    );
  }

  Map<String, Object?> toMap() => {
    'welcome': welcome?.name,
    'activeModule': activeModule?.name,
    'modules': {
      for (final entry in modules.entries)
        entry.key.name: {'status': entry.value.name},
    },
  };

  @override
  String toString() => toMap().toString();
}

T? _byName<T extends Enum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
