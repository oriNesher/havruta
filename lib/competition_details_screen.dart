import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';

class CompetitionDetailsScreen extends StatefulWidget {
  final String competitionId;
  final String title;
  final String description;
  final String status;
  final String createdBy;

  const CompetitionDetailsScreen({
    super.key,
    required this.competitionId,
    required this.title,
    required this.description,
    required this.status,
    required this.createdBy,
  });

  @override
  State<CompetitionDetailsScreen> createState() =>
      _CompetitionDetailsScreenState();
}

class _CompetitionDetailsScreenState extends State<CompetitionDetailsScreen> {
  final FirestoreService firestoreService = FirestoreService();
  bool _isDeleting = false;

  Future<void> _confirmAndDeleteCompetition() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Competition'),
          content: const Text(
            'Are you sure you want to delete this competition? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await firestoreService.deleteCompetition(widget.competitionId);

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Competition deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete competition: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isCreator = user != null && user.uid == widget.createdBy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Competition Details'),
        actions: [
          if (isCreator)
            IconButton(
              onPressed: _isDeleting ? null : _confirmAndDeleteCompetition,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Delete Competition',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),

              if (widget.description.isNotEmpty) ...[
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(widget.description),
                const SizedBox(height: 20),
              ],

              Text('Status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(widget.status),
              const SizedBox(height: 20),

              Text(
                'Created By',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              FutureBuilder<String?>(
                future: firestoreService.getUsernameByUid(widget.createdBy),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  }

                  if (snapshot.hasError) {
                    return Text(widget.createdBy);
                  }

                  final username = snapshot.data;

                  return Text(
                    username != null && username.isNotEmpty
                        ? username
                        : widget.createdBy,
                  );
                },
              ),
              const SizedBox(height: 32),

              if (isCreator) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isDeleting
                        ? null
                        : _confirmAndDeleteCompetition,
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(
                      _isDeleting ? 'Deleting...' : 'Delete Competition',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (user != null) ...[
                CompetitionInviteSection(
                  competitionId: widget.competitionId,
                  competitionTitle: widget.title,
                  currentUserUid: user.uid,
                ),
                const SizedBox(height: 32),
              ],

              Text(
                'Participants',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firestoreService.getCompetitionParticipants(
                  widget.competitionId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Text('No participants yet');
                  }

                  final participants = docs.map((doc) => doc.data()).toList();

                  participants.sort((a, b) {
                    final progressA = a['progress'] ?? 0;
                    final progressB = b['progress'] ?? 0;
                    final targetA = a['targetValue'] ?? 0;
                    final targetB = b['targetValue'] ?? 0;

                    final percentA = targetA > 0 ? progressA / targetA : 0.0;
                    final percentB = targetB > 0 ? progressB / targetB : 0.0;

                    return percentB.compareTo(percentA);
                  });

                  return Column(
                    children: participants.map((participant) {
                      final username = participant['username'] ?? '';
                      final uid = participant['uid'] ?? '';
                      final progress = participant['progress'] ?? 0;
                      final goalTitle = participant['goalTitle'] ?? '';
                      final targetValue = participant['targetValue'] ?? 0;
                      final unit = participant['unit'] ?? '';

                      final displayName = username.toString().isNotEmpty
                          ? username
                          : uid;
                      final isMe = user != null && uid == user.uid;

                      final progressRatio = targetValue > 0
                          ? (progress / targetValue)
                          : 0.0;

                      final progressBarValue = progressRatio.clamp(0.0, 1.0);

                      final percentText = targetValue > 0
                          ? '${(progressRatio * 100).toStringAsFixed(0)}%'
                          : '0%';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.08)
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isMe ? '$displayName (You)' : displayName,
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  percentText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (goalTitle.toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(goalTitle),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              '$progress / $targetValue ${unit.toString()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progressBarValue,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}