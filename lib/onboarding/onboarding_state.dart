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
  reportProgress,
  celebrationTrashTalk,
  eventsRespect,
  createChallenge,
  invitePeople,
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

  /// Small, module-owned durable facts (e.g. which real Challenge a module
  /// is tracking), stored as `modules.<id>.data`. Only modules that need to
  /// survive a relaunch mid-step keep anything here.
  final Map<OnboardingModuleId, Map<String, Object?>> moduleData;

  const OnboardingTutorialState({
    this.welcome,
    this.activeModule,
    this.modules = const {},
    this.moduleData = const {},
  });

  static const empty = OnboardingTutorialState();

  OnboardingModuleStatus statusOf(OnboardingModuleId id) =>
      modules[id] ?? OnboardingModuleStatus.notStarted;

  Map<String, Object?> dataOf(OnboardingModuleId id) =>
      moduleData[id] ?? const {};

  OnboardingTutorialState copyWith({
    OnboardingWelcomeChoice? welcome,
    OnboardingModuleId? activeModule,
    bool clearActiveModule = false,
  }) {
    return OnboardingTutorialState(
      welcome: welcome ?? this.welcome,
      activeModule: clearActiveModule
          ? null
          : (activeModule ?? this.activeModule),
      modules: modules,
      moduleData: moduleData,
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
      moduleData: moduleData,
    );
  }

  /// Merges [data] into [id]'s module data. Add-only by design: saves
  /// merge, so a key can't be removed this way (see [withoutModuleData]).
  OnboardingTutorialState withModuleData(
    OnboardingModuleId id,
    Map<String, Object?> data,
  ) {
    final merged = {...dataOf(id), ...data};
    return OnboardingTutorialState(
      welcome: welcome,
      activeModule: activeModule,
      modules: modules,
      moduleData: {...moduleData, id: merged},
    );
  }

  OnboardingTutorialState withoutModuleData(Iterable<OnboardingModuleId> ids) {
    return OnboardingTutorialState(
      welcome: welcome,
      activeModule: activeModule,
      modules: modules,
      moduleData: {...moduleData}..removeWhere((id, _) => ids.contains(id)),
    );
  }

  /// Unknown values (e.g. a module id written by a newer app version) are
  /// dropped here rather than failing; since saves merge, they also survive
  /// untouched in Firestore.
  factory OnboardingTutorialState.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;

    final modules = <OnboardingModuleId, OnboardingModuleStatus>{};
    final moduleData = <OnboardingModuleId, Map<String, Object?>>{};
    final rawModules = map['modules'];
    if (rawModules is Map) {
      for (final entry in rawModules.entries) {
        final id = _byName(OnboardingModuleId.values, entry.key);
        final rawStatus = entry.value is Map ? entry.value['status'] : null;
        final status = _byName(OnboardingModuleStatus.values, rawStatus);
        if (id != null && status != null) modules[id] = status;
        final rawData = entry.value is Map ? entry.value['data'] : null;
        if (id != null && rawData is Map && rawData.isNotEmpty) {
          moduleData[id] = Map<String, Object?>.from(rawData);
        }
      }
    }

    return OnboardingTutorialState(
      welcome: _byName(OnboardingWelcomeChoice.values, map['welcome']),
      activeModule: _byName(OnboardingModuleId.values, map['activeModule']),
      modules: modules,
      moduleData: moduleData,
    );
  }

  /// Saved with a merge, so module data keys absent here are left as they
  /// are in Firestore (removing them takes an explicit delete — see
  /// OnboardingRepository.clearModuleData).
  Map<String, Object?> toMap() => {
    'welcome': welcome?.name,
    'activeModule': activeModule?.name,
    'modules': {
      for (final id in {...modules.keys, ...moduleData.keys})
        id.name: {
          if (modules[id] != null) 'status': modules[id]!.name,
          if (moduleData[id] != null) 'data': moduleData[id],
        },
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
