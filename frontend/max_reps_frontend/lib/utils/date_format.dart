// Formatting changes presentation only: all displayed times remain in UTC.
String formatUsUtc(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final hour = utc.hour % 12 == 0 ? 12 : utc.hour % 12;
  final period = utc.hour < 12 ? 'AM' : 'PM';
  return '$month/$day/${utc.year} at $hour:$minute $period UTC';
}
