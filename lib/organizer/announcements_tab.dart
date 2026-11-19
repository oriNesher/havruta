import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../competitions/challenge.dart';
import 'format.dart';
import 'organizer_service.dart';

/// Write to everyone in the challenge at once: it lands in their activity
/// feed and on the Challenge page, and as a notification on every device
/// with notifications on. Rate-limited server-side (10 a day).
class AnnouncementsTab extends StatefulWidget {
  final Challenge challenge;
  final String uid;

  const AnnouncementsTab({super.key, required this.challenge, required this.uid});

  @override
  State<AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<AnnouncementsTab> {
  final _organizer = OrganizerService();
  final _text = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _history =
      _organizer.announcements(widget.challenge.id);
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _audience => {
    ...widget.challenge.participantUids,
    ...widget.challenge.organizerUids,
  }.where((uid) => uid != widget.uid).length;

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final audience = _audience;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Send to $audience ${audience == 1 ? 'person' : 'people'}?'),
        content: Text(
          'It appears in everyone\'s activity feed and on the Challenge '
          'page, and as a notification where notifications are on.\n\n'
          '"$text"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final count = await _organizer.sendAnnouncement(widget.challenge.id, text);
      _text.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent to $count ${count == 1 ? 'person' : 'people'}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(organizerErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New announcement',
                  style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Goes to everyone in the challenge. Up to 10 a day, so '
                  'they stay worth reading.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Group run Saturday 7:00 at the park gate',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _sending ||
                            _text.text.trim().isEmpty ||
                            !widget.challenge.isActive
                        ? null
                        : _send,
                    icon: const Icon(Icons.campaign, size: 18),
                    label: Text(_sending ? 'Sending…' : 'Send'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Sent', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text('Nothing sent yet.', style: theme.textTheme.bodySmall);
            }
            return Column(
              children: [
                for (final doc in docs)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: Text(doc.data()['text'] as String? ?? ''),
                      subtitle: Text(
                        '${doc.data()['byUsername'] ?? 'An organizer'} · '
                        '${formatDateTime((doc.data()['createdAt'] as Timestamp?)?.toDate())}',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
