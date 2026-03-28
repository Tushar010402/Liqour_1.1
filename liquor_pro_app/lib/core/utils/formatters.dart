import 'package:intl/intl.dart';

/// Formatters - Best Practice Data Formatting
/// Centralized formatting utilities for consistent data display

class Formatters {
  // Private constructor to prevent instantiation
  Formatters._();

  // ==================== Currency Formatters ====================

  /// Format currency in Indian Rupees
  static String currency(double amount, {String symbol = '₹'}) {
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    return '$symbol${formatter.format(amount)}';
  }

  /// Alias for currency (backward compatible)
  static String formatCurrency(double amount, {String symbol = '₹'}) {
    return currency(amount, symbol: symbol);
  }

  /// Format currency without decimal
  static String currencyWithoutDecimal(double amount, {String symbol = '₹'}) {
    final formatter = NumberFormat('#,##,##0', 'en_IN');
    return '$symbol${formatter.format(amount)}';
  }

  /// Format currency with compact notation (e.g., ₹1.2K, ₹5.3M, ₹10Cr)
  static String currencyCompact(double amount, {String symbol = '₹'}) {
    if (amount >= 10000000) {
      return '$symbol${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(2)}K';
    } else {
      return '$symbol${amount.toStringAsFixed(2)}';
    }
  }

  /// Format currency for display (no decimals if whole number)
  static String currencyDisplay(double amount, {String symbol = '₹'}) {
    if (amount == amount.roundToDouble()) {
      return '$symbol${amount.toStringAsFixed(0)}';
    } else {
      return '$symbol${amount.toStringAsFixed(2)}';
    }
  }

  // ==================== Number Formatters ====================

  /// Number formatter
  static String number(double value, {int decimals = 2}) {
    return value.toStringAsFixed(decimals);
  }

  /// Format number with thousand separators
  static String numberWithSeparator(num value, {int decimals = 0}) {
    final formatter = NumberFormat('#,##,###', 'en_IN');
    if (decimals > 0) {
      return value.toStringAsFixed(decimals);
    }
    return formatter.format(value);
  }

  /// Percentage formatter
  static String percentage(double value, {int decimals = 1}) {
    return '${value.toStringAsFixed(decimals)}%';
  }

  /// Compact number (e.g., 1000 -> 1K, 1000000 -> 1M)
  static String compactNumber(double value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(2)}Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(2)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  /// Format decimal number
  static String decimal(double value, {int decimals = 2}) {
    return value.toStringAsFixed(decimals);
  }

  // ==================== Date & Time Formatters ====================

  /// Date formatter
  static String date(DateTime date, {String format = 'dd MMM yyyy'}) {
    final formatter = DateFormat(format);
    return formatter.format(date);
  }

  /// DateTime formatter
  static String dateTime(DateTime date, {String format = 'dd MMM yyyy, hh:mm a'}) {
    final formatter = DateFormat(format);
    return formatter.format(date);
  }

  /// Time formatter
  static String time(DateTime date, {String format = 'hh:mm a'}) {
    final formatter = DateFormat(format);
    return formatter.format(date);
  }

  /// Format date with day (e.g., "Monday, Jan 15, 2024")
  static String dateWithDay(DateTime date) {
    return DateFormat('EEEE, MMM dd, yyyy').format(date);
  }

  /// Format date short (e.g., "15/01/2024")
  static String dateShort(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Format date as YYYY-MM-DD for grouping
  static String dateOnly(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Relative time (e.g., "2 hours ago")
  /// Ensures both dates are in local timezone before calculating difference
  static String relativeTime(DateTime date) {
    final now = DateTime.now().toLocal();
    final localDate = date.toLocal();
    final difference = now.difference(localDate);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  /// Alias for relativeTime
  static String timeAgo(DateTime date) => relativeTime(date);

  /// Format date range (e.g., "Jan 15 - Jan 20, 2024")
  static String dateRange(DateTime start, DateTime end) {
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat('MMM dd').format(start)} - ${DateFormat('dd, yyyy').format(end)}';
    } else if (start.year == end.year) {
      return '${DateFormat('MMM dd').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
    } else {
      return '${DateFormat('MMM dd, yyyy').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
    }
  }

  /// Smart timestamp - context-aware date/time display
  /// Shows appropriate format based on how recent the date is:
  /// - Today: "X minutes/hours ago"
  /// - Yesterday: "Yesterday at HH:mm"
  /// - This week: "Mon at HH:mm"
  /// - This year: "15 Oct"
  /// - Older: "15 Oct 2023"
  static String smartTimestamp(DateTime date) {
    final now = DateTime.now().toLocal();
    final localDate = date.toLocal();
    final difference = now.difference(localDate);

    // Today (less than 24 hours)
    if (difference.inHours < 24 &&
        now.day == localDate.day &&
        now.month == localDate.month &&
        now.year == localDate.year) {
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return '$minutes min ago';
      } else {
        final hours = difference.inHours;
        return '$hours hr ago';
      }
    }

    // Yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (localDate.day == yesterday.day &&
        localDate.month == yesterday.month &&
        localDate.year == yesterday.year) {
      return 'Yesterday ${DateFormat('HH:mm').format(localDate)}';
    }

    // This week (within last 7 days)
    if (difference.inDays < 7) {
      return '${DateFormat('EEE').format(localDate)} ${DateFormat('HH:mm').format(localDate)}';
    }

    // This year (show date without year)
    if (localDate.year == now.year) {
      return DateFormat('dd MMM').format(localDate);
    }

    // Older (show full date with year)
    return DateFormat('dd MMM yyyy').format(localDate);
  }

  // ==================== String Formatters ====================

  /// Capitalize first letter
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Title case
  static String titleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) => capitalize(word)).join(' ');
  }

  /// Convert to uppercase
  static String uppercase(String text) {
    return text.toUpperCase();
  }

  /// Convert to lowercase
  static String lowercase(String text) {
    return text.toLowerCase();
  }

  /// Truncate text
  static String truncate(String text, int maxLength, {String suffix = '...'}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}$suffix';
  }

  /// Format phone number
  static String phoneNumber(String phone) {
    if (phone.length == 10) {
      return '+91 ${phone.substring(0, 5)} ${phone.substring(5)}';
    }
    return phone;
  }

  // ==================== Business Formatters ====================

  /// Format SKU (e.g., "SKU-12345")
  static String sku(String sku) {
    return sku.toUpperCase();
  }

  /// Format barcode
  static String barcode(String barcode) {
    return barcode.toUpperCase();
  }

  /// Format GST number
  static String gst(String gst) {
    return gst.toUpperCase();
  }

  /// Format PAN number
  static String pan(String pan) {
    return pan.toUpperCase();
  }

  /// Format size (e.g., 180ml, 750ml, 1L)
  static String size(String size) {
    return size.toUpperCase();
  }

  /// Stock quantity formatter
  static String stockQuantity(int quantity, {int? reorderLevel}) {
    if (reorderLevel != null && quantity <= reorderLevel) {
      return '$quantity (Low Stock)';
    }
    return quantity.toString();
  }

  /// Format stock status
  static String stockStatus(int currentStock, int reorderLevel) {
    if (currentStock <= 0) {
      return 'Out of Stock';
    } else if (currentStock <= reorderLevel) {
      return 'Low Stock';
    } else {
      return 'In Stock';
    }
  }

  /// Format order status
  static String orderStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'processing':
        return 'Processing';
      case 'shipped':
        return 'Shipped';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'returned':
        return 'Returned';
      default:
        return titleCase(status);
    }
  }

  /// Format duty percentage
  static String dutyPercentage(double dutyAmount, double costPrice) {
    if (costPrice <= 0) return '0%';
    final percentage = (dutyAmount / costPrice) * 100;
    return '${percentage.toStringAsFixed(1)}%';
  }

  // ==================== File Size Formatters ====================

  /// File size formatter
  static String fileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  // ==================== List Formatters ====================

  /// Format list to comma-separated string
  static String list(List<String> items, {String separator = ', '}) {
    return items.join(separator);
  }

  /// Format list with "and" for last item (e.g., "Item 1, Item 2 and Item 3")
  static String listWithAnd(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} and ${items[1]}';

    final allButLast = items.sublist(0, items.length - 1).join(', ');
    return '$allButLast and ${items.last}';
  }

  // ==================== Quantity Formatters ====================

  /// Format quantity with unit (e.g., "5 units", "1 unit")
  static String quantity(int quantity, {String unit = 'unit'}) {
    if (quantity == 1) {
      return '$quantity $unit';
    } else {
      return '$quantity ${unit}s';
    }
  }

  /// Format weight (e.g., "750 ml", "1 L")
  static String weight(double value, String unit) {
    if (value == value.roundToDouble()) {
      return '${value.toStringAsFixed(0)} $unit';
    } else {
      return '${value.toStringAsFixed(2)} $unit';
    }
  }

  // ==================== Duration Formatters ====================

  /// Format duration (e.g., "2 hours 30 minutes")
  static String duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      if (minutes > 0) {
        return '$hours ${hours == 1 ? 'hour' : 'hours'} $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
      }
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    } else if (minutes > 0) {
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    } else {
      return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    }
  }

  /// Format duration compact (e.g., "2h 30m")
  static String durationCompact(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${hours}h';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  // ==================== Custom Formatters ====================

  /// Format with prefix and suffix
  static String withPrefixSuffix(
    String value, {
    String? prefix,
    String? suffix,
  }) {
    return '${prefix ?? ''}$value${suffix ?? ''}';
  }

  /// Format nullable value with fallback
  static String nullable<T>(T? value, {String fallback = 'N/A'}) {
    return value?.toString() ?? fallback;
  }

  /// Format boolean as Yes/No
  static String yesNo(bool value) {
    return value ? 'Yes' : 'No';
  }

  /// Format boolean as Active/Inactive
  static String activeInactive(bool value) {
    return value ? 'Active' : 'Inactive';
  }

  /// Format boolean as Enabled/Disabled
  static String enabledDisabled(bool value) {
    return value ? 'Enabled' : 'Disabled';
  }
}
