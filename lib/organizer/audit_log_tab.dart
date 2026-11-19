import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../competitions/challenge.dart';
import 'format.dart';
import 'organizer_service.dart';

/// Every organizer action on this challenge — who, when, what changed
/// (before → after) and why. Server-written, so it can't be edited.
class AuditLogTab extends StatefulWidget {
  final Challenge challenge;

  const AuditLogTab({super.key, required this.challenge});

  @override
  State<AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<AuditLogTab> {
  // Created once: the dashboard rebuilds on every challenge-doc change.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _log =
      OrganizerService().auditLog(widget.challenge.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _log,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('No organizer actions yet. Corrections, removals, '
                'setting changes and the rest will be listed here.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final record = docs[index].data();
            final reason = record['reason'] as String?;
            final detail = _detail(record);
            return ListTile(
              leading: Icon(_icon(record['action'] as String?)),
              title: Text(_summary(record)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail != null) Text(detail),
                  if (reason != null && reason.isNotEmpty)
                    Text('Reason: $reason'),
                  Text(
                    formatDateTime((record['at'] as Timestamp?)?.toDate()),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }

  static IconData _icon(String? action) => switch (action) {
    'updateSettings' => Icons.tune,
    'removeParticipant' => Icons.person_remove_outlined,
    'reinstateParticipant' => Icons.restore,
    'correctProgress' => Icons.edit_outlined,
    'endEarly' => Icons.flag_outlined,
    'addOrganizer' || 'removeOrganizer' => Icons.admin_panel_settings_outlined,
    'createTeam' || 'renameTeam' || 'deleteTeam' || 'assignTeam' =>
      Icons.groups_outlined,
    _ => Icons.history,
  };

  static String _summary(Map<String, dynamic> r) {
    final actor = r['actorUsername'] as String? ?? 'An organizer';
    final target = r['targetUsername'] as String? ?? r['targetUid'] ?? 'someone';
    return switch (r['action'] as String?) {
      'updateSettings' => '$actor changed the challenge settings',
      'removeParticipant' => '$actor removed $target',
      'reinstateParticipant' => '$actor reinstated $target',
      'correctProgress' => "$actor corrected $target's progress",
      'endEarly' => '$actor ended the challenge early',
      'addOrganizer' => '$actor made $target an organizer',
      'removeOrganizer' => '$actor removed $target as organizer',
      'createTeam' => '$actor created a team',
      'renameTeam' => '$actor renamed a team',
      'deleteTeam' => '$actor deleted a team',
      'assignTeam' => "$actor changed $target's team",
      final other => '$actor: $other',
    };
  }

  /// "progress: 60 → 45" style lines from the record's before/after.
  static String? _detail(Map<String, dynamic> r) {
    final before = r['before'];
    final after = r['after'];
    if (before is! Map && after is! Map) return null;
    final b = before is Map ? before : const {};
    final a = after is Map ? after : const {};
    final keys = {...b.keys, ...a.keys};
    if (keys.isEmpty) return null;
    return keys
        .map((k) => '$k: ${_value(b[k])} → ${_value(a[k])}')
        .join('\n');
  }

  static String _value(Object? v) {
    if (v == null) return '—';
    if (v is List) return v.isEmpty ? '—' : v.join(', ');
    final s = v.toString();
    // ISO timestamps from date changes: keep them short.
    return RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s) ? s.substring(0, 10) : s;
  }
}
