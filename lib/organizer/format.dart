const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Nov 19, 14:05" in local time; "—" for null.
String formatDateTime(DateTime? time) {
  if (time == null) return '—';
  final t = time.toLocal();
  return '${_months[t.month - 1]} ${t.day}, ${_two(t.hour)}:${_two(t.minute)}';
}

/// "Nov 19, 2026".
String formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// "Today" / "Yesterday" / "Nov 17" for a YYYY-MM-DD challenge day.
String formatDayKey(String dayKey, String todayKey) {
  final day = DateTime.tryParse(dayKey);
  final today = DateTime.tryParse(todayKey);
  if (day == null || today == null) return dayKey;
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_months[day.month - 1]} ${day.day}';
}

/// "3m ago", "5h ago", "2d ago", or a date — for "last update" columns.
String formatAgo(DateTime? time, DateTime now) {
  if (time == null) return '—';
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(time.toLocal());
}
