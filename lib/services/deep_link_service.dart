import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'pending_invite_store.dart';

/// Catches incoming invite-link URLs (Android App Links) — both cold start
/// (app opened directly via the link) and warm start (link tapped while the
/// app is already running) — and stashes the token so it survives whatever
/// interruption (login, registration, app install) happens before the user
/// can actually redeem it. See PendingInviteStore for the persistence side.
class DeepLinkService {
  final _appLinks = AppLinks();
  final _pendingInviteStore = PendingInviteStore();
  StreamSubscription<Uri>? _subscription;

  Future<void> init() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) await _handleUri(initialUri);

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('Deep link stream error: $e'),
    );
  }

  Future<void> _handleUri(Uri uri) async {
    final linkId = _extractInviteLinkId(uri);
    if (linkId == null) return;
    await _pendingInviteStore.savePendingInviteToken(linkId);
  }

  /// Expects URLs of the form `https://<host>/i/{linkId}`.
  static String? _extractInviteLinkId(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'i') return null;
    final linkId = segments[1];
    return linkId.isEmpty ? null : linkId;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
