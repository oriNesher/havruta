import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../onboarding/onboarding_anchor.dart';
import '../onboarding/onboarding_ids.dart';
import '../services/app_signals.dart';
import '../services/firestore_service.dart';
import 'challenge.dart';
import 'challenge_invite_screen.dart';
import 'goals_bucket_bottom_sheet.dart';
import 'widgets/challenge_creation_stepper.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  WinCondition _mode = WinCondition.firstToTarget;

  final _titleController = TextEditingController();
  final _goalController = TextEditingController();
  final _targetController = TextEditingController();
  final _dailyMinimumController = TextEditingController();
  final _unitController = TextEditingController();
  final _rulesController = TextEditingController();

  /// Last calendar day of the challenge (inclusive), in the creator's
  /// local calendar. Required for Most Progress, optional otherwise.
  DateTime? _endDate;

  /// Last One Standing only: whether today already counts as day 1.
  bool _startsToday = false;

  String? _linkedGoalTitle;

  /// The creator's IANA zone; becomes the challenge calendar. Null (UTC)
  /// only if the platform couldn't report one.
  String? _timeZone;

  final _firestoreService = FirestoreService();
  final _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = false;
  bool _requiredDetailsComplete = false;

  @override
  void initState() {
    super.initState();
    _goalController.addListener(_syncTargetFromGoal);
    for (final controller in [
      _goalController,
      _targetController,
      _dailyMinimumController,
    ]) {
      controller.addListener(_reportDraft);
    }
    AppSignals.instance.emit(
      const ChallengeDraftChanged(requiredDetailsComplete: false),
    );
    _loadTimeZone();
  }

  Future<void> _loadTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      _timeZone = info.identifier;
    } catch (e) {
      debugPrint('CREATE_CHALLENGE: no local time zone -> $e');
    }
  }

  int? _positiveInt(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  /// Whether the current mode's required fields are filled — mirrors
  /// _createChallenge's own validation.
  bool get _hasRequiredDetails {
    if (_goalController.text.trim().isEmpty) return false;
    return switch (_mode) {
      WinCondition.firstToTarget => _positiveInt(_targetController) != null,
      WinCondition.lastStanding =>
        _positiveInt(_dailyMinimumController) != null,
      WinCondition.mostProgress => _endDate != null,
    };
  }

  void _reportDraft() {
    final complete = _hasRequiredDetails;
    if (complete == _requiredDetailsComplete) return;
    _requiredDetailsComplete = complete;
    AppSignals.instance.emit(
      ChallengeDraftChanged(requiredDetailsComplete: complete),
    );
  }

  // Detects the first number typed in the goal field (e.g. "Run 30km") and
  // mirrors it into Target. Always resyncs on every goal edit — a manual
  // edit to Target sticks only until the goal text changes again. Races
  // only: in the other modes a number in the goal isn't a finish line.
  void _syncTargetFromGoal() {
    if (_mode != WinCondition.firstToTarget) return;
    final match = RegExp(r'\d+').firstMatch(_goalController.text);
    if (match != null) _targetController.text = match.group(0)!;
  }

  void _onModeChanged(WinCondition mode) {
    setState(() => _mode = mode);
    _reportDraft();
  }

  Future<void> _pickEndDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Challenge ends after',
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
    _reportDraft();
  }

  void _setEndDate(DateTime? date) {
    setState(() => _endDate = date);
    _reportDraft();
  }

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

  String? _missingDetailsMessage() {
    if (_goalController.text.trim().isEmpty) {
      return 'Please fill in what everyone is doing';
    }
    return switch (_mode) {
      WinCondition.firstToTarget when _positiveInt(_targetController) == null =>
        'Target must be a positive number',
      WinCondition.lastStanding
          when _positiveInt(_dailyMinimumController) == null =>
        'Daily minimum must be a positive number',
      WinCondition.mostProgress when _endDate == null =>
        'Please pick when the challenge ends',
      _ => null,
    };
  }

  Future<void> _createChallenge() async {
    final missing = _missingDetailsMessage();
    if (missing != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(missing)));
      return;
    }

    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user found')),
      );
      return;
    }

    final goalText = _goalController.text.trim();
    final titleText = _titleController.text.trim();
    final challengeName = titleText.isEmpty ? goalText : titleText;
    final unit = _unitController.text.trim();
    final now = DateTime.now();
    final endDate = _endDate;

    // Day boundaries in the creator's own calendar, which is the
    // challenge's calendar (timeZone below).
    final startsAt = _mode == WinCondition.lastStanding
        ? DateTime(now.year, now.month, now.day + (_startsToday ? 0 : 1))
        : null;
    final endsAt = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day + 1);

    if (startsAt != null && endsAt != null && !endsAt.isAfter(startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The end date must be after the start')),
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

      final targetValue = _mode == WinCondition.firstToTarget
          ? _positiveInt(_targetController)
          : null;
      final rules = ChallengeRules(
        dailyMinimum: _mode == WinCondition.lastStanding
            ? _positiveInt(_dailyMinimumController)
            : null,
      );

      final competitionId = await _firestoreService.createChallenge(
        title: challengeName,
        description: _rulesController.text.trim(),
        createdBy: uid,
        creatorUsername: creatorUsername,
        winCondition: _mode,
        goalTitle: goalText,
        unit: unit,
        targetValue: targetValue,
        rules: rules,
        timeZone: _timeZone,
        startsAt: startsAt,
        endsAt: endsAt,
        linkedGoalTitle: _linkedGoalTitle,
      );

      final challenge = Challenge(
        id: competitionId,
        title: challengeName,
        createdBy: uid,
        winCondition: _mode,
        goalTitle: goalText,
        unit: unit,
        targetValue: targetValue,
        rules: rules,
        timeZone: _timeZone,
        startsAt: startsAt,
        endsAt: endsAt,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChallengeInviteScreen(challenge: challenge, currentUserUid: uid),
        ),
      );
      AppSignals.instance.emit(
        ChallengeCreated(competitionId: competitionId, winCondition: _mode),
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
    _goalController.removeListener(_syncTargetFromGoal);
    for (final controller in [
      _goalController,
      _targetController,
      _dailyMinimumController,
    ]) {
      controller.removeListener(_reportDraft);
    }
    _titleController.dispose();
    _goalController.dispose();
    _targetController.dispose();
    _dailyMinimumController.dispose();
    _unitController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

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

  Widget _goalField() {
    final (hint, helper) = switch (_mode) {
      WinCondition.firstToTarget => (
        'Run 30km / Read 4 books / Do 300 pushups',
        'Everyone races toward this same goal',
      ),
      WinCondition.lastStanding => (
        'Study / Walk / Read',
        'What everyone has to do every day',
      ),
      WinCondition.mostProgress => (
        'Run / Read pages / Workouts',
        'Whatever everyone is counting',
      ),
    };
    return _fieldSection(
      'Goal',
      'The specific, measurable thing everyone does. '
          'e.g. "Run 30km" or "Read".',
      TextField(
        controller: _goalController,
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _numberField({
    required String label,
    required String tooltip,
    required TextEditingController controller,
    required String hint,
  }) {
    return _fieldSection(
      label,
      tooltip,
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  /// The mode-specific required field(s) under Goal.
  List<Widget> _modeRequiredFields() {
    return switch (_mode) {
      WinCondition.firstToTarget => [
        _numberField(
          label: 'Target',
          tooltip:
              'The number to reach to win. e.g. 30 for "Run 30km".',
          controller: _targetController,
          hint: '30',
        ),
      ],
      WinCondition.lastStanding => [
        _numberField(
          label: 'Daily minimum',
          tooltip:
              'How much everyone must log every day to stay in. '
              'Miss it once and you\'re out.',
          controller: _dailyMinimumController,
          hint: '30',
        ),
        const SizedBox(height: 16),
        _fieldSection(
          'Day 1',
          'Starting tomorrow gives everyone a full first day. '
              'Days end at midnight in your time zone, for everyone.',
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Tomorrow')),
              ButtonSegment(value: true, label: Text('Today')),
            ],
            selected: {_startsToday},
            onSelectionChanged: (selection) =>
                setState(() => _startsToday = selection.first),
          ),
        ),
      ],
      WinCondition.mostProgress => [
        _EndDateField(
          label: 'Ends after',
          endDate: _endDate,
          onPick: _pickEndDate,
          onPreset: _setEndDate,
          requiredField: true,
        ),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Challenge')),
      bottomNavigationBar: const ChallengeCreationStepper(currentStep: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How do you win?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            OnboardingAnchor(
              id: OnboardingAnchorIds.createChallengeTypeSelector,
              child: Column(
                children: [
                  for (final mode in WinCondition.values) ...[
                    _ModeOption(
                      mode: mode,
                      selected: mode == _mode,
                      onTap: () => _onModeChanged(mode),
                    ),
                    if (mode != WinCondition.values.last)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Required details for the chosen mode.
            OnboardingAnchor(
              id: OnboardingAnchorIds.createChallengeRequiredDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _goalField(),
                  const SizedBox(height: 16),
                  ..._modeRequiredFields(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Create button — right after the required details, so everything
            // below it reads as optional extras rather than more steps.
            OnboardingAnchor(
              id: OnboardingAnchorIds.createChallengeSubmit,
              child: SizedBox(
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
            ),
            const SizedBox(height: 32),

            // Optional section header
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

            // Title
            _fieldSection(
              'Title',
              'A name for this challenge. Leave it blank and the goal text will be used instead. '
              'e.g. "Family Health Challenge" or "Reading Challenge".',
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Family Health Challenge',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Unit
            _fieldSection(
              'Unit',
              'How progress is measured. e.g. minutes, pages, km. '
              'Skip this and progress will show as a plain number.',
              TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  hintText: 'minutes / pages / km',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // End date — required (and shown above) for Most Progress.
            if (_mode != WinCondition.mostProgress) ...[
              _EndDateField(
                label: _mode == WinCondition.lastStanding
                    ? 'End date'
                    : 'Deadline',
                endDate: _endDate,
                onPick: _pickEndDate,
                onPreset: _setEndDate,
                requiredField: false,
              ),
              const SizedBox(height: 16),
            ],

            // Connect to a bigger goal
            _fieldSection(
              'Connect to a bigger goal',
              'Link this challenge to one of your long-term goals. '
              'It connects the challenge to your personal growth journey.',
              InkWell(
                onTap: _openGoalsBucketForLinkedGoal,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    suffixIcon: Icon(Icons.chevron_right),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  child: Text(
                    _linkedGoalTitle ?? 'Tap to select from your goals',
                    style: TextStyle(
                      color: _linkedGoalTitle == null
                          ? theme.hintColor
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            if (_linkedGoalTitle != null) ...[
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

            // Rules or notes
            _fieldSection(
              'Rules or notes',
              'Any extra rules or clarifications. '
              'e.g. "Weekends count too" or "Only gym workouts count".',
              TextField(
                controller: _rulesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Weekends count too...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Mode option card
// ─────────────────────────────────────────────

class _ModeOption extends StatelessWidget {
  final WinCondition mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon => switch (mode) {
    WinCondition.firstToTarget => Icons.flag_outlined,
    WinCondition.lastStanding => Icons.shield_outlined,
    WinCondition.mostProgress => Icons.leaderboard_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.tagline,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// End date picker field with quick presets
// ─────────────────────────────────────────────

class _EndDateField extends StatelessWidget {
  final String label;
  final DateTime? endDate;
  final VoidCallback onPick;
  final ValueChanged<DateTime?> onPreset;
  final bool requiredField;

  const _EndDateField({
    required this.label,
    required this.endDate,
    required this.onPick,
    required this.onPreset,
    required this.requiredField,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final presets = <String, DateTime>{
      '1 week': today.add(const Duration(days: 6)),
      '30 days': today.add(const Duration(days: 29)),
      'End of month': DateTime(today.year, today.month + 1, 0),
    };
    final date = endDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: requiredField
                  ? 'The challenge ends at midnight after this day. '
                        'Whoever has the most progress by then wins.'
                  : 'Optional. The challenge ends at midnight after this day.',
              triggerMode: TooltipTriggerMode.tap,
              preferBelow: false,
              child: const Icon(Icons.info_outline, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: date != null && !requiredField
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear date',
                      onPressed: () => onPreset(null),
                    )
                  : const Icon(Icons.calendar_today_outlined),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
            ),
            child: Text(
              date != null ? _formatDate(date) : 'Pick a date',
              style: TextStyle(
                color: date == null
                    ? theme.hintColor
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in presets.entries)
              ChoiceChip(
                label: Text(entry.key),
                selected: date != null && date == entry.value,
                onSelected: (_) => onPreset(entry.value),
              ),
          ],
        ),
      ],
    );
  }
}
