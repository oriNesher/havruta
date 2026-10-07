import 'package:cloud_functions/cloud_functions.dart';

import '../competitions/challenge.dart';

/// Preview data for an invite link, as returned by the `getInvite` callable.
class InvitePreview {
  final bool valid;
  final String? reason; // 'not_found' | 'revoked' | 'expired' | 'full'
  final String? competitionId;
  final String? competitionTitle;
  final String? competitionType;
  final String? winCondition;
  final int? dailyMinimum;
  final String? createdByUsername;
  final String? sharedGoalTitle;
  final int? sharedTargetValue;
  final String? sharedUnit;
  final String? creatorGoalTitle;
  final int? creatorTargetValue;
  final String? creatorUnit;

  InvitePreview({
    required this.valid,
    this.reason,
    this.competitionId,
    this.competitionTitle,
    this.competitionType,
    this.winCondition,
    this.dailyMinimum,
    this.createdByUsername,
    this.sharedGoalTitle,
    this.sharedTargetValue,
    this.sharedUnit,
    this.creatorGoalTitle,
    this.creatorTargetValue,
    this.creatorUnit,
  });

  /// The linked challenge as far as the preview describes it — enough to
  /// say how it's won and what the goal is.
  Challenge get challenge => Challenge.fromDoc(competitionId ?? '', {
    'title': competitionTitle,
    'type': competitionType,
    'winCondition': ?winCondition,
    'sharedGoalTitle': sharedGoalTitle,
    'sharedTargetValue': sharedTargetValue,
    'sharedUnit': sharedUnit,
    'rules': {'dailyMinimum': ?dailyMinimum},
  });

  bool get isLegacyPersonal => challenge.isLegacyPersonal;

  factory InvitePreview.fromMap(Map<String, dynamic> data) {
    return InvitePreview(
      valid: data['valid'] == true,
      reason: data['reason'] as String?,
      competitionId: data['competitionId'] as String?,
      competitionTitle: data['competitionTitle'] as String?,
      competitionType: data['competitionType'] as String?,
      winCondition: data['winCondition'] as String?,
      dailyMinimum: (data['dailyMinimum'] as num?)?.toInt(),
      createdByUsername: data['createdByUsername'] as String?,
      sharedGoalTitle: data['sharedGoalTitle'] as String?,
      sharedTargetValue: (data['sharedTargetValue'] as num?)?.toInt(),
      sharedUnit: data['sharedUnit'] as String?,
      creatorGoalTitle: data['creatorGoalTitle'] as String?,
      creatorTargetValue: (data['creatorTargetValue'] as num?)?.toInt(),
      creatorUnit: data['creatorUnit'] as String?,
    );
  }
}

/// Thin wrapper around the invite-related Cloud Functions callables.
/// Redemption and unauthenticated preview reads must go through the server
/// (see functions/src/invites/) rather than direct Firestore access, since a
/// link token is a bearer credential — see the invite-flow redesign plan.
class InviteService {
  final _functions = FirebaseFunctions.instance;

  Future<({String linkId, String url})> createInvite({
    required String competitionId,
  }) async {
    final callable = _functions.httpsCallable('createInvite');
    final result = await callable.call<Map<String, dynamic>>({
      'competitionId': competitionId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (linkId: data['linkId'] as String, url: data['url'] as String);
  }

  Future<InvitePreview> getInvite({required String linkId}) async {
    final callable = _functions.httpsCallable('getInvite');
    final result = await callable.call<Map<String, dynamic>>({
      'linkId': linkId,
    });
    return InvitePreview.fromMap(Map<String, dynamic>.from(result.data as Map));
  }

  Future<({String competitionId, bool alreadyJoined})> redeemInvite({
    required String linkId,
    String? goalTitle,
    int? targetValue,
    String? unit,
  }) async {
    final callable = _functions.httpsCallable('redeemInvite');
    final result = await callable.call<Map<String, dynamic>>({
      'linkId': linkId,
      if (goalTitle != null) 'goalTitle': goalTitle,
      if (targetValue != null) 'targetValue': targetValue,
      if (unit != null) 'unit': unit,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      competitionId: data['competitionId'] as String,
      alreadyJoined: data['alreadyJoined'] == true,
    );
  }

  Future<void> revokeInvite({required String linkId}) async {
    final callable = _functions.httpsCallable('revokeInvite');
    await callable.call<Map<String, dynamic>>({'linkId': linkId});
  }
}
