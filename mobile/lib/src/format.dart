/// Small date/time formatting helpers (pure Dart, no `intl` dependency).
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "14:03"
String formatHm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "14:03:22"
String formatHms(DateTime t) => '${formatHm(t)}:${_two(t.second)}';

/// "14:03:22" for today, otherwise "9 Oct 14:03".
String formatTimestamp(DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final sameDay =
      local.year == ref.year &&
      local.month == ref.month &&
      local.day == ref.day;
  return sameDay
      ? formatHms(local)
      : '${local.day} ${_months[local.month - 1]} ${formatHm(local)}';
}

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String formatAgo(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// Wall-clock time in Europe/Bucharest (EET/EEST), computed from the EU DST
/// rule: UTC+3 from the last Sunday of March 01:00 UTC until the last Sunday of
/// October 01:00 UTC, otherwise UTC+2. Only the hour/minute fields of the
/// returned value are meaningful.
DateTime bucharestWallClock([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  final dstStart = _lastSundayUtc(utc.year, DateTime.march);
  final dstEnd = _lastSundayUtc(utc.year, DateTime.october);
  final inDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return utc.add(Duration(hours: inDst ? 3 : 2));
}

DateTime _lastSundayUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  final daysBack = lastDay.weekday % DateTime.daysPerWeek; // Sunday -> 0
  return DateTime.utc(year, month, lastDay.day - daysBack, 1);
}
