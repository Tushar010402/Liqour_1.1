import 'package:intl/intl.dart';

/// DateTime Helper - Best Practice Date & Time Utilities
/// Centralized date/time operations and calculations

class DateTimeHelper {
  // Private constructor to prevent instantiation
  DateTimeHelper._();

  // ==================== Current DateTime ====================

  /// Get current date time
  static DateTime now() => DateTime.now();

  /// Get current date (without time)
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Get current time (as Duration from midnight)
  static Duration currentTime() {
    final now = DateTime.now();
    return Duration(hours: now.hour, minutes: now.minute, seconds: now.second);
  }

  // ==================== Date Creation ====================

  /// Create date from components
  static DateTime createDate(int year, int month, int day) {
    return DateTime(year, month, day);
  }

  /// Create datetime from components
  static DateTime createDateTime(
    int year,
    int month,
    int day, {
    int hour = 0,
    int minute = 0,
    int second = 0,
  }) {
    return DateTime(year, month, day, hour, minute, second);
  }

  /// Parse date from string
  static DateTime? parseDate(String dateString, {String format = 'yyyy-MM-dd'}) {
    try {
      final formatter = DateFormat(format);
      return formatter.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  /// Parse datetime from ISO 8601 string
  static DateTime? parseIso(String isoString) {
    try {
      return DateTime.parse(isoString);
    } catch (e) {
      return null;
    }
  }

  // ==================== Date Manipulation ====================

  /// Add days to date
  static DateTime addDays(DateTime date, int days) {
    return date.add(Duration(days: days));
  }

  /// Subtract days from date
  static DateTime subtractDays(DateTime date, int days) {
    return date.subtract(Duration(days: days));
  }

  /// Add months to date
  static DateTime addMonths(DateTime date, int months) {
    int year = date.year;
    int month = date.month + months;

    while (month > 12) {
      month -= 12;
      year++;
    }

    while (month < 1) {
      month += 12;
      year--;
    }

    // Handle day overflow (e.g., Jan 31 + 1 month = Feb 28/29)
    int day = date.day;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    if (day > lastDayOfMonth) {
      day = lastDayOfMonth;
    }

    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }

  /// Subtract months from date
  static DateTime subtractMonths(DateTime date, int months) {
    return addMonths(date, -months);
  }

  /// Add years to date
  static DateTime addYears(DateTime date, int years) {
    return DateTime(
      date.year + years,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  /// Subtract years from date
  static DateTime subtractYears(DateTime date, int years) {
    return addYears(date, -years);
  }

  // ==================== Date Getters ====================

  /// Get start of day (midnight)
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day (23:59:59)
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// Get start of week (Monday)
  static DateTime startOfWeek(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return startOfDay(subtractDays(date, daysFromMonday));
  }

  /// Get end of week (Sunday)
  static DateTime endOfWeek(DateTime date) {
    final daysToSunday = 7 - date.weekday;
    return endOfDay(addDays(date, daysToSunday));
  }

  /// Get start of month
  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  /// Get end of month
  static DateTime endOfMonth(DateTime date) {
    final lastDay = DateTime(date.year, date.month + 1, 0).day;
    return DateTime(date.year, date.month, lastDay, 23, 59, 59);
  }

  /// Get start of year
  static DateTime startOfYear(DateTime date) {
    return DateTime(date.year, 1, 1);
  }

  /// Get end of year
  static DateTime endOfYear(DateTime date) {
    return DateTime(date.year, 12, 31, 23, 59, 59);
  }

  // ==================== Date Comparisons ====================

  /// Check if two dates are the same day
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    return isSameDay(date, DateTime.now());
  }

  /// Check if date is yesterday
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return isSameDay(date, yesterday);
  }

  /// Check if date is tomorrow
  static bool isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return isSameDay(date, tomorrow);
  }

  /// Check if date is in the past
  static bool isPast(DateTime date) {
    return date.isBefore(DateTime.now());
  }

  /// Check if date is in the future
  static bool isFuture(DateTime date) {
    return date.isAfter(DateTime.now());
  }

  /// Check if date is in current week
  static bool isThisWeek(DateTime date) {
    final now = DateTime.now();
    final weekStart = startOfWeek(now);
    final weekEnd = endOfWeek(now);
    return date.isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
        date.isBefore(weekEnd.add(const Duration(seconds: 1)));
  }

  /// Check if date is in current month
  static bool isThisMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  /// Check if date is in current year
  static bool isThisYear(DateTime date) {
    return date.year == DateTime.now().year;
  }

  // ==================== Date Differences ====================

  /// Get difference in days between two dates
  static int daysBetween(DateTime date1, DateTime date2) {
    final d1 = startOfDay(date1);
    final d2 = startOfDay(date2);
    return d2.difference(d1).inDays;
  }

  /// Get difference in months between two dates
  static int monthsBetween(DateTime date1, DateTime date2) {
    return (date2.year - date1.year) * 12 + date2.month - date1.month;
  }

  /// Get difference in years between two dates
  static int yearsBetween(DateTime date1, DateTime date2) {
    return date2.year - date1.year;
  }

  /// Get age from birth date
  static int getAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;

    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  // ==================== Business Date Operations ====================

  /// Get next business day (skip weekends)
  static DateTime nextBusinessDay(DateTime date) {
    DateTime next = addDays(date, 1);
    while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
      next = addDays(next, 1);
    }
    return next;
  }

  /// Get previous business day (skip weekends)
  static DateTime previousBusinessDay(DateTime date) {
    DateTime prev = subtractDays(date, 1);
    while (prev.weekday == DateTime.saturday || prev.weekday == DateTime.sunday) {
      prev = subtractDays(prev, 1);
    }
    return prev;
  }

  /// Check if date is a weekend
  static bool isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Check if date is a weekday
  static bool isWeekday(DateTime date) {
    return !isWeekend(date);
  }

  /// Get business days between two dates
  static int businessDaysBetween(DateTime start, DateTime end) {
    int count = 0;
    DateTime current = startOfDay(start);
    final endDate = startOfDay(end);

    while (current.isBefore(endDate) || isSameDay(current, endDate)) {
      if (isWeekday(current)) {
        count++;
      }
      current = addDays(current, 1);
    }

    return count;
  }

  // ==================== Date Range Operations ====================

  /// Get list of dates between two dates
  static List<DateTime> dateRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    DateTime current = startOfDay(start);
    final endDate = startOfDay(end);

    while (current.isBefore(endDate) || isSameDay(current, endDate)) {
      dates.add(current);
      current = addDays(current, 1);
    }

    return dates;
  }

  /// Get list of months between two dates
  static List<DateTime> monthRange(DateTime start, DateTime end) {
    final months = <DateTime>[];
    DateTime current = DateTime(start.year, start.month, 1);
    final endMonth = DateTime(end.year, end.month, 1);

    while (current.isBefore(endMonth) || isSameDay(current, endMonth)) {
      months.add(current);
      current = addMonths(current, 1);
    }

    return months;
  }

  // ==================== Predefined Date Ranges ====================

  /// Get today's date range
  static DateRange getTodayRange() {
    final today = DateTime.now();
    return DateRange(
      start: startOfDay(today),
      end: endOfDay(today),
    );
  }

  /// Get yesterday's date range
  static DateRange getYesterdayRange() {
    final yesterday = subtractDays(DateTime.now(), 1);
    return DateRange(
      start: startOfDay(yesterday),
      end: endOfDay(yesterday),
    );
  }

  /// Get this week's date range
  static DateRange getThisWeekRange() {
    final now = DateTime.now();
    return DateRange(
      start: startOfWeek(now),
      end: endOfWeek(now),
    );
  }

  /// Get last week's date range
  static DateRange getLastWeekRange() {
    final lastWeek = subtractDays(DateTime.now(), 7);
    return DateRange(
      start: startOfWeek(lastWeek),
      end: endOfWeek(lastWeek),
    );
  }

  /// Get this month's date range
  static DateRange getThisMonthRange() {
    final now = DateTime.now();
    return DateRange(
      start: startOfMonth(now),
      end: endOfMonth(now),
    );
  }

  /// Get last month's date range
  static DateRange getLastMonthRange() {
    final lastMonth = subtractMonths(DateTime.now(), 1);
    return DateRange(
      start: startOfMonth(lastMonth),
      end: endOfMonth(lastMonth),
    );
  }

  /// Get this year's date range
  static DateRange getThisYearRange() {
    final now = DateTime.now();
    return DateRange(
      start: startOfYear(now),
      end: endOfYear(now),
    );
  }

  /// Get last N days range
  static DateRange getLastNDaysRange(int days) {
    final now = DateTime.now();
    return DateRange(
      start: startOfDay(subtractDays(now, days - 1)),
      end: endOfDay(now),
    );
  }

  /// Get last N months range
  static DateRange getLastNMonthsRange(int months) {
    final now = DateTime.now();
    final startDate = subtractMonths(now, months - 1);
    return DateRange(
      start: startOfMonth(startDate),
      end: endOfMonth(now),
    );
  }

  // ==================== Time Operations ====================

  /// Get time from DateTime
  static TimeOfDay toTimeOfDay(DateTime dateTime) {
    return TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
  }

  /// Combine date and time
  static DateTime combineDateTime(DateTime date, TimeOfDay time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  /// Format time duration
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  // ==================== Utility Methods ====================

  /// Get day name (Monday, Tuesday, etc.)
  static String getDayName(DateTime date) {
    return DateFormat('EEEE').format(date);
  }

  /// Get short day name (Mon, Tue, etc.)
  static String getShortDayName(DateTime date) {
    return DateFormat('EEE').format(date);
  }

  /// Get month name (January, February, etc.)
  static String getMonthName(DateTime date) {
    return DateFormat('MMMM').format(date);
  }

  /// Get short month name (Jan, Feb, etc.)
  static String getShortMonthName(DateTime date) {
    return DateFormat('MMM').format(date);
  }

  /// Get quarter (1-4)
  static int getQuarter(DateTime date) {
    return ((date.month - 1) ~/ 3) + 1;
  }

  /// Get days in month
  static int getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  /// Check if leap year
  static bool isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  }
}

/// Date range model
class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({
    required this.start,
    required this.end,
  });

  /// Check if date is in range
  bool contains(DateTime date) {
    return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
        date.isBefore(end.add(const Duration(seconds: 1)));
  }

  /// Get number of days in range
  int get days {
    return DateTimeHelper.daysBetween(start, end) + 1;
  }

  /// Get formatted string
  String format() {
    final formatter = DateFormat('MMM dd, yyyy');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  @override
  String toString() => format();
}

/// Time of day helper
class TimeOfDay {
  final int hour;
  final int minute;

  TimeOfDay({required this.hour, required this.minute});

  /// Format as string (12-hour)
  String format12Hour() {
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  /// Format as string (24-hour)
  String format24Hour() {
    final displayHour = hour.toString().padLeft(2, '0');
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute';
  }

  @override
  String toString() => format12Hour();
}
