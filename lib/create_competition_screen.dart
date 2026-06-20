import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';
import 'goals_bucket_bottom_sheet.dart';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  final _challengeNameController = TextEditingController();
  final _personalGoalController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _rulesController = TextEditingController();

  String? _linkedGoalTitle;

  final _firestoreService = FirestoreService();
  final _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = false;
  String? _createdCompetitionId;
  String? _createdCompetitionTitle;

  Future<void> _openGoalsBucketForLinkedGoal() async {
    FocusScope.of(context).unfocus();

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GoalsBucketBottomSheet(uid: _user!.uid),
    );

    if (selected != null) {
      setState(() => _linkedGoalTitle = selected);
    }
  }

  Future<void> _createChallenge() async {
    final challengeName = _challengeNameController.text.trim();
    final personalGoal = _personalGoalController.text.trim();
    final targetText = _targetController.text.trim();
    final unit = _unitController.text.trim();
    final deadline = _deadlineController.text.trim();
    final rules = _rulesController.text.trim();

    if (challengeName.isEmpty || personalGoal.isEmpty || targetText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in Challenge name, My personal goal, and Target',
          ),
        ),
      );
      return;
    }

    final targetValue = int.tryParse(targetText);
    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target must be a positive number')),
      );
      return;
    }

    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user found')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = _user.uid;
      final creatorUsername = await _firestoreService.getMyUsername(uid);

      if (creatorUsername == null || creatorUsername.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find your username')),
        );
        return;
      }

      final competitionId = await _firestoreService.createCompetition(
        title: challengeName,
        description: rules,
        createdBy: uid,
        creatorUsername: creatorUsername,
        goalTitle: personalGoal,
        targetValue: targetValue,
        unit: unit,
        deadline: deadline.isNotEmpty ? deadline : null,
        linkedGoalTitle: _linkedGoalTitle,
      );

      final goalExists = await _firestoreService.goalExistsInBucket(
        uid,
        personalGoal,
      );
      if (!goalExists) {
        await _firestoreService.addGoal(uid, personalGoal);
      }

      if (!mounted) return;

      setState(() {
        _createdCompetitionId = competitionId;
        _createdCompetitionTitle = challengeName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Challenge created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating challenge: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _challengeNameController.dispose();
    _personalGoalController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    _deadlineController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  /// Renders a label row (text + tappable info icon) above the given field widget.
  Widget _fieldSection(String label, String tooltip, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.tap,
              preferBelow: false,
              child: const Icon(Icons.info_outline, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final alreadyCreated = _createdCompetitionId != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Challenge')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Format header
            Row(
              children: [
                Text(
                  'Personal Goal Challenge',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      "It's not always easy to find someone with the exact same goal as you. "
                      "Personal Goal Challenges let everyone work on their own goal, while still "
                      "sharing the motivation, accountability, and fun of a competition.",
                  triggerMode: TooltipTriggerMode.tap,
                  preferBelow: false,
                  child: const Icon(Icons.info_outline, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Work on your own goal, compete together.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 28),

            // Challenge name
            _fieldSection(
              'Challenge name',
              'The name of this challenge. e.g. "Family Health Challenge" or "Reading Challenge".',
              TextField(
                controller: _challengeNameController,
                enabled: !alreadyCreated,
                decoration: const InputDecoration(
                  hintText: 'Family Health Challenge',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // My personal goal
            _fieldSection(
              'My personal goal',
              'Something specific you can track with a number. '
              'e.g. "Run 30km" or "Read 4 books" — not a vague long-term aspiration.',
              TextField(
                controller: _personalGoalController,
                enabled: !alreadyCreated,
                decoration: const InputDecoration(
                  hintText: 'Run 30km / Read 4 books / Do 300 pushups',
                  helperText: 'Make it specific and measurable',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Target
            _fieldSection(
              'Target',
              'The number you need to reach to complete your goal. e.g. 30 or 4.',
              TextField(
                controller: _targetController,
                enabled: !alreadyCreated,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '30',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Optional section header (hidden after creation)
            if (!alreadyCreated) ...[
              Row(
                children: [
                  Text(
                    'Add more details',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'optional',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Unit
            _fieldSection(
              'Unit',
              'How your target is measured. e.g. days, books, km. '
              'Skip this and progress will show as a number or percentage.',
              TextField(
                controller: _unitController,
                enabled: !alreadyCreated,
                decoration: const InputDecoration(
                  hintText: 'days / books / km',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Connect to a bigger goal
            _fieldSection(
              'Connect to a bigger goal',
              'Link this challenge to one of your long-term goals. '
              'It connects the challenge to your personal growth journey.',
              InkWell(
                onTap: alreadyCreated ? null : _openGoalsBucketForLinkedGoal,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    enabled: !alreadyCreated,
                    suffixIcon: alreadyCreated
                        ? null
                        : const Icon(Icons.chevron_right),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  child: Text(
                    _linkedGoalTitle ??
                        (alreadyCreated ? '—' : 'Tap to select from your goals'),
                    style: TextStyle(
                      color: _linkedGoalTitle == null
                          ? (alreadyCreated
                              ? theme.disabledColor
                              : theme.hintColor)
                          : (alreadyCreated
                              ? theme.disabledColor
                              : theme.colorScheme.onSurface),
                    ),
                  ),
                ),
              ),
            ),
            if (!alreadyCreated && _linkedGoalTitle != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _linkedGoalTitle = null),
                  child: const Text('Remove'),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Deadline or duration
            _fieldSection(
              'Deadline or duration',
              'Add a time frame if you want. e.g. "30 days" or "By August 1st".',
              TextField(
                controller: _deadlineController,
                enabled: !alreadyCreated,
                decoration: const InputDecoration(
                  hintText: '30 days / By August 1st',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Rules or notes
            _fieldSection(
              'Rules or notes',
              'Any extra rules or clarifications. '
              'e.g. "Weekends count too" or "Only gym workouts count".',
              TextField(
                controller: _rulesController,
                enabled: !alreadyCreated,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Weekends count too...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Create button
            if (!alreadyCreated)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _createChallenge,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Challenge'),
                ),
              ),

            // Post-creation state
            if (alreadyCreated) ...[
              const SizedBox(height: 8),
              const Text('Challenge created! Invite people to join.'),
              const SizedBox(height: 24),
              CompetitionInviteSection(
                competitionId: _createdCompetitionId!,
                competitionTitle: _createdCompetitionTitle ?? '',
                currentUserUid: _user!.uid,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
