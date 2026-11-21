import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../app_theme.dart';
import '../home/home_pending_invites_section.dart';
import '../services/firestore_service.dart';
import '../services/respect_store.dart';
import 'respect_notifications_section.dart';

const _respectPurple = Color(0xFFB69CFB);

class PendingInvitesScreen extends StatefulWidget {
  const PendingInvitesScreen({super.key});

  @override
  State<PendingInvitesScreen> createState() => _PendingInvitesScreenState();
}

class _PendingInvitesScreenState extends State<PendingInvitesScreen> {
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _markRespectSeen();
  }

  @override
  void dispose() {
    // Again on the way out: Respect that landed while this screen was open
    // has been seen too, so it shouldn't pop on the bell back on Home.
    _markRespectSeen();
    super.dispose();
  }

  void _markRespectSeen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _firestoreService.markRespectSeen(uid).catchError(
      (Object e) => debugPrint('Marking Respect seen failed: $e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'RESPECT',
                  style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                ),
                const Spacer(),
                // Lifetime total, which lived on the Home Respect card
                // until that moved into the app bar's wallet chip. Kept live
                // by Home's user-doc listener (Home stays mounted under
                // this screen).
                ListenableBuilder(
                  listenable: RespectStore.instance,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${RespectStore.instance.totalReceived}',
                        style: AppTheme.mono(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _respectPurple,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const PhosphorIcon(
                        PhosphorIconsFill.pawPrint,
                        size: 14,
                        color: _respectPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'received',
                        style: AppTheme.display(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF8888A0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RespectNotificationsSection(uid: user.uid),
            const SizedBox(height: 24),
            Text(
              'INVITES',
              style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            HomePendingInvitesSection(uid: user.uid),
          ],
        ),
      ),
    );
  }
}
