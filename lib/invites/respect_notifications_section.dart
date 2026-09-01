import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../app_theme.dart';
import '../services/firestore_service.dart';

/// "X gave you Respect" feed for the notifications screen.
class RespectNotificationsSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();

  RespectNotificationsSection({super.key, required this.uid});

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getRespectNotifications(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          debugPrint('Respect notifications error: ${snapshot.error}');
          return Text('Error: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No Respect yet');

        final colorScheme = Theme.of(context).colorScheme;
        final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final fromUsername = data['fromUsername'] as String? ?? 'Someone';
            final createdAt = data['createdAt'] as Timestamp?;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsFill.barbell,
                    size: 18,
                    color: colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: base,
                        children: [
                          TextSpan(
                            text: fromUsername,
                            style: base.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: ' gave you Respect for your progress.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _relativeTime(createdAt),
                    style: AppTheme.display(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
