import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_service.dart';

class CompetitionInviteSection extends StatefulWidget {
  final String competitionId;
  final String competitionTitle;
  final String currentUserUid;
  final String competitionType;
  final String? sharedGoalTitle;
  final int? sharedTargetValue;
  final String? sharedUnit;
  final String? creatorGoalTitle;
  final int? creatorTargetValue;
  final String? creatorUnit;

  const CompetitionInviteSection({
    super.key,
    required this.competitionId,
    required this.competitionTitle,
    required this.currentUserUid,
    this.competitionType = 'personalGoalChallenge',
    this.sharedGoalTitle,
    this.sharedTargetValue,
    this.sharedUnit,
    this.creatorGoalTitle,
    this.creatorTargetValue,
    this.creatorUnit,
  });

  @override
  State<CompetitionInviteSection> createState() =>
      _CompetitionInviteSectionState();
}

class _CompetitionInviteSectionState extends State<CompetitionInviteSection> {
  final TextEditingController usernameController = TextEditingController();
  final FirestoreService firestoreService = FirestoreService();

  bool isLoading = false;

  Future<void> inviteUser() async {
    final input = usernameController.text.trim();

    if (input.isEmpty) return;

    setState(() {
      isLoading = true;
    });

    try {
      final userDoc = input.contains('@')
          ? await firestoreService.findUserByEmail(input)
          : await firestoreService.findUserByUsername(input);

      if (userDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }

      final data = userDoc.data();
      final toUid = data['uid'];
      final toUsername = data['username'] ?? '';

      if (toUid == widget.currentUserUid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot invite yourself')),
        );
        return;
      }

      final alreadyParticipant = await firestoreService.isAlreadyParticipant(
        competitionId: widget.competitionId,
        uid: toUid,
      );

      if (alreadyParticipant) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User is already participating')),
        );
        return;
      }

      final exists = await firestoreService.inviteAlreadyExists(
        competitionId: widget.competitionId,
        toUid: toUid,
      );

      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invite already sent')));
        return;
      }

      await firestoreService.sendCompetitionInvite(
        competitionId: widget.competitionId,
        competitionTitle: widget.competitionTitle,
        fromUid: widget.currentUserUid,
        toUid: toUid,
        toUsername: toUsername,
        competitionType: widget.competitionType,
        sharedGoalTitle: widget.sharedGoalTitle,
        sharedTargetValue: widget.sharedTargetValue,
        sharedUnit: widget.sharedUnit,
        creatorGoalTitle: widget.creatorGoalTitle,
        creatorTargetValue: widget.creatorTargetValue,
        creatorUnit: widget.creatorUnit,
      );

      usernameController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending invite: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Invite users',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'Username or email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isLoading ? null : inviteUser,
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Invite'),
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Pending invites',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestoreService.getCompetitionPendingInvites(
            widget.competitionId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              debugPrint('Pending invites error: ${snapshot.error}');
              return Text('Error: ${snapshot.error}');
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Text('No pending invites'),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: docs.map((doc) {
                final data = doc.data();
                final username = data['toUsername'] ?? '';
                final toUid = data['toUid'] ?? '';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(
                      username.toString().isNotEmpty ? username : toUid,
                    ),
                    subtitle: const Text('Pending'),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
