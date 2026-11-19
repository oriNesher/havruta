import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'pending_invite_store.dart';
import 'platform_web.dart';

/// Catches incoming invite-link URLs — both cold start (app opened directly
/// via the link) and warm start (link tapped while the app is already
/// running) — and stashes the token so it survives whatever interruption
/// (login, registration, app install) happens before the user can actually
/// redeem it. See PendingInviteStore for the persistence side.
///
/// Native uses Android App Links / iOS Universal Links via app_links. On web
/// the link is just the URL the tab was opened with, read once at startup;
/// there is no equivalent of a warm-start stream, since arriving at a new
/// URL reloads the app.
class DeepLinkService {
  /// A challenge whose organizer dashboard the web app was opened at
  /// (/organize/{competitionId}); AuthGate opens it once the user is
  /// signed in, then clears it. In memory only — the URL itself is what
  /// survives a reload.
  static String? pendingOrganizerDashboard;

  final _appLinks = AppLinks();
  final _pendingInviteStore = PendingInviteStore();
  StreamSubscription<Uri>? _subscription;

  Future<void> init() async {
    if (kIsWeb) {
      pendingOrganizerDashboard = extractOrganizerDashboardId(Uri.base);
      await _handleUri(Uri.base);
      return;
    }

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) await _handleUri(initialUri);

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('Deep link stream error: $e'),
    );
  }

  Future<void> _handleUri(Uri uri) async {
    final linkId = extractInviteLinkId(uri);
    if (linkId == null) return;
    await _pendingInviteStore.savePendingInviteToken(linkId);

    // Take the token back out of the address bar once it's stashed. Leaving
    // it there would re-stash it on every reload, and invites them to be
    // copied out and shared as if they were the app's own URL.
    if (kIsWeb) replaceUrlPath('/');
  }

  /// Pulls an invite token out of any of the shapes an invite link can
  /// arrive in:
  ///
  /// - `https://<host>/i/{linkId}` — what gets shared, and what App Links
  ///   and Universal Links hand to the native app.
  /// - `https://<host>/join/{linkId}` — the web equivalent. `/i/` can't be
  ///   reused on web: Hosting rewrites it to the `inviteLanding` function,
  ///   so the Flutter app never sees it.
  /// - `https://<host>/#/join/{linkId}` — the same token in the fragment,
  ///   which works even where a path isn't routed to the app (a plain
  ///   static server, or before the Hosting SPA rewrite is in place).
  ///
  /// Returns null for any URL that isn't an invite link.
  @visibleForTesting
  static String? extractInviteLinkId(Uri uri) {
    final fromPath = _linkIdFromSegments(uri.pathSegments);
    if (fromPath != null) return fromPath;

    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    return _linkIdFromSegments(Uri.parse(fragment).pathSegments);
  }

  /// The challenge id in a web organizer-dashboard URL,
  /// `https://<host>/organize/{competitionId}`, or null.
  @visibleForTesting
  static String? extractOrganizerDashboardId(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'organize') return null;
    return segments[1].isEmpty ? null : segments[1];
  }

  static const _invitePrefixes = {'i', 'join'};

  static String? _linkIdFromSegments(List<String> segments) {
    if (segments.length < 2) return null;
    if (!_invitePrefixes.contains(segments[0])) return null;
    final linkId = segments[1];
    return linkId.isEmpty ? null : linkId;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
