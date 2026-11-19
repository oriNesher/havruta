import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../competitions/competition_details_screen.dart';
import '../services/firestore_service.dart';
import '../services/platform_web.dart';
import '../web_shell.dart';
import 'announcements_tab.dart';
import 'audit_log_tab.dart';
import 'format.dart';
import 'participants_tab.dart';
import 'settings_tab.dart';

/// The organizer's control room for one challenge: participants (status,
/// progress, paid, corrections, removal), announcements, settings and the
/// audit log. Built for a desktop browser — it lifts the web app's
/// phone-width column while open — but lays out on a phone too.
///
/// On web it lives at /organize/{competitionId}, so an organizer can
/// bookmark it; AuthGate opens it from that URL after sign-in.
class OrganizerDashboardScreen extends StatefulWidget {
  final String competitionId;

  const OrganizerDashboardScreen({super.key, required this.competitionId});

  static Future<void> open(BuildContext context, String competitionId) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrganizerDashboardScreen(competitionId: competitionId),
      ),
    );
  }

  @override
  State<OrganizerDashboardScreen> createState() =>
      _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState extends State<OrganizerDashboardScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _challengeStream =
      FirestoreService().getCompetitionDoc(widget.competitionId);

  @override
  void initState() {
    super.initState();
    WebShellWide.acquire();
    if (kIsWeb) replaceUrlPath('/organize/${widget.competitionId}');
  }

  @override
  void dispose() {
    WebShellWide.release();
    if (kIsWeb) replaceUrlPath('/');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _challengeStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message(
            'This challenge is unavailable: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data();
        if (data == null) {
          return const _Message('This challenge no longer exists.');
        }
        final challenge = Challenge.fromDoc(widget.competitionId, data);
        if (uid == null || !challenge.isOrganizer(uid)) {
          return const _Message(
            "Only this challenge's organizers can open its dashboard.",
          );
        }
        return _Dashboard(challenge: challenge, uid: uid);
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  final Challenge challenge;
  final String uid;

  const _Dashboard({required this.challenge, required this.uid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final endsAt = challenge.endsAt;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                challenge.title.isEmpty ? 'Challenge' : challenge.title,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  'Organizer',
                  challenge.modeLabel,
                  if (!challenge.isActive)
                    'Ended'
                  else if (endsAt != null)
                    'Ends ${formatDate(endsAt.subtract(const Duration(days: 1)))}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CompetitionDetailsScreen(challenge: challenge),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Challenge page'),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Participants'),
              Tab(text: 'Announcements'),
              Tab(text: 'Settings'),
              Tab(text: 'Activity log'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Page(child: ParticipantsTab(challenge: challenge)),
            _Page(child: AnnouncementsTab(challenge: challenge, uid: uid)),
            _Page(child: SettingsTab(challenge: challenge, uid: uid)),
            _Page(child: AuditLogTab(challenge: challenge)),
          ],
        ),
      ),
    );
  }
}

/// Centers a tab's content at a readable maximum width on big monitors.
class _Page extends StatelessWidget {
  final Widget child;

  const _Page({required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: child,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;

  const _Message(this.message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizer dashboard')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
