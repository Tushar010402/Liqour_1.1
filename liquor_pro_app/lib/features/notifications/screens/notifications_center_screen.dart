import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/notification_navigation_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../models/notification_models.dart';
import '../providers/notification_provider.dart';
import 'notification_preferences_screen.dart';

/// iOS 18 Style Notifications Center Screen
/// Modern, beautiful design with grouped notifications, swipe actions, and animations
class NotificationsCenterScreen extends ConsumerStatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  ConsumerState<NotificationsCenterScreen> createState() => _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends ConsumerState<NotificationsCenterScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showUnreadOnly = ref.watch(showOnlyUnreadProvider);
    final notificationsAsync = ref.watch(activeNotificationsProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // iOS 18 Style Large Title App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.pop(),
            ),
            actions: [
              // Unread toggle
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    showUnreadOnly
                        ? Icons.mark_email_unread_rounded
                        : Icons.mark_email_read_rounded,
                    key: ValueKey(showUnreadOnly),
                    color: showUnreadOnly ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                onPressed: () {
                  HapticFeedbackUtil.lightImpact();
                  ref.read(showOnlyUnreadProvider.notifier).state = !showUnreadOnly;
                },
                tooltip: showUnreadOnly ? 'Show all' : 'Show unread only',
              ),
              // Settings
              IconButton(
                icon: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
                onPressed: () {
                  HapticFeedbackUtil.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationPreferencesScreen(),
                    ),
                  );
                },
                tooltip: 'Notification settings',
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Notifications',
                    style: AppTextStyles.h4.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Unread count badge
                  unreadCount.when(
                    data: (count) => count > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              count > 99 ? '99+' : count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              expandedTitleScale: 1.3,
            ),
          ),

          // Filter Chips Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mark all as read button
                  unreadCount.when(
                    data: (count) => count > 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: GestureDetector(
                              onTap: () => _markAllAsRead(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha:0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.done_all_rounded,
                                      size: 18,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Mark all as read',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip('All', null, Icons.notifications_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Sales', 'sales', Icons.shopping_cart_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Inventory', 'inventory', Icons.inventory_2_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Finance', 'finance', Icons.account_balance_wallet_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Audit', 'audit', Icons.fact_check_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Security', 'theft', Icons.security_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('System', 'system', Icons.settings_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notifications List
          notificationsAsync.when(
            data: (response) {
              if (response.notifications.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                );
              }

              // Group notifications by date
              final groupedNotifications = _groupNotificationsByDate(response.notifications);

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entries = groupedNotifications.entries.toList();
                    int currentIndex = 0;

                    for (var entry in entries) {
                      // Check if this index is a header
                      if (currentIndex == index) {
                        return _buildDateHeader(entry.key);
                      }
                      currentIndex++;

                      // Check if this index is one of the notifications in this group
                      for (var notification in entry.value) {
                        if (currentIndex == index) {
                          return _buildModernNotificationCard(notification, currentIndex);
                        }
                        currentIndex++;
                      }
                    }

                    return const SizedBox.shrink();
                  },
                  childCount: _calculateTotalItems(groupedNotifications),
                ),
              );
            },
            loading: () => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: _buildErrorState(),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final selectedFilter = ref.watch(selectedNotificationFilterProvider);
    final isSelected = selectedFilter == value;

    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.lightImpact();
        ref.read(selectedNotificationFilterProvider.notifier).state = value;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? cs.primary.withValues(alpha:0.3)
                  : Colors.black.withValues(alpha:0.05),
              blurRadius: isSelected ? 12 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : cs.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(String dateLabel) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Text(
        dateLabel,
        style: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildModernNotificationCard(AppNotification notification, int index) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = NotificationNavigationService.getColorForType(notification.type);
    final icon = NotificationNavigationService.getIconForType(notification.type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Dismissible(
        key: Key(notification.id),
        direction: DismissDirection.horizontal,
        background: _buildSwipeBackground(
          alignment: Alignment.centerLeft,
          color: Colors.blue,
          icon: Icons.mark_email_read_rounded,
          label: 'Read',
        ),
        secondaryBackground: _buildSwipeBackground(
          alignment: Alignment.centerRight,
          color: Colors.red,
          icon: Icons.delete_rounded,
          label: 'Delete',
        ),
        confirmDismiss: (direction) async {
          HapticFeedbackUtil.mediumImpact();
          if (direction == DismissDirection.endToStart) {
            // Delete
            return true;
          } else {
            // Mark as read
            await _markAsRead(notification.id);
            return false;
          }
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            _deleteNotification(notification.id);
          }
        },
        child: GestureDetector(
          onTap: () {
            HapticFeedbackUtil.lightImpact();
            if (!notification.isRead) {
              _markAsRead(notification.id);
            }
            _handleNotificationTap(notification);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: !notification.isRead
                  ? Border.all(
                      color: cs.primary.withValues(alpha:0.3),
                      width: 1.5,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon with priority indicator
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha:0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: iconColor, size: 24),
                      ),
                      if (notification.priority == NotificationPriority.urgent ||
                          notification.priority == NotificationPriority.high)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: notification.priority == NotificationPriority.urgent
                                  ? Colors.red
                                  : Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              Icons.priority_high_rounded,
                              size: 8,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: notification.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!notification.isRead)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.message,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Type badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                notification.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: iconColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Time
                            Text(
                              _formatTime(notification.createdAt),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Chevron
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha:0.5),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ]
            : [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 22),
              ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                size: 48,
                color: cs.primary.withValues(alpha:0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'All caught up!',
              style: AppTextStyles.h5.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no notifications right now.\nWe\'ll let you know when something arrives.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Something went wrong',
              style: AppTextStyles.h6.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unable to load notifications.\nPlease try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedbackUtil.lightImpact();
                ref.invalidate(activeNotificationsProvider);
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<AppNotification>> _groupNotificationsByDate(
      List<AppNotification> notifications) {
    final Map<String, List<AppNotification>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));

    for (var notification in notifications) {
      final notificationDate = DateTime(
        notification.createdAt.year,
        notification.createdAt.month,
        notification.createdAt.day,
      );

      String label;
      if (notificationDate == today) {
        label = 'Today';
      } else if (notificationDate == yesterday) {
        label = 'Yesterday';
      } else if (notificationDate.isAfter(thisWeek)) {
        label = 'This Week';
      } else {
        label = DateFormat('MMMM d, yyyy').format(notification.createdAt);
      }

      grouped.putIfAbsent(label, () => []);
      grouped[label]!.add(notification);
    }

    return grouped;
  }

  int _calculateTotalItems(Map<String, List<AppNotification>> grouped) {
    int count = 0;
    for (var entry in grouped.entries) {
      count++; // Header
      count += entry.value.length; // Notifications
    }
    return count;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    final success = await ref.read(notificationNotifierProvider.notifier).markAsRead(notificationId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to mark as read'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    HapticFeedbackUtil.mediumImpact();
    final success = await ref.read(notificationNotifierProvider.notifier).markAllAsRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'All notifications marked as read' : 'Failed to mark all as read'),
          backgroundColor: success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    final success = await ref.read(notificationNotifierProvider.notifier).deleteNotification(notificationId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete notification'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _handleNotificationTap(AppNotification notification) {
    // If there's an action URL, navigate to it
    if (notification.actionUrl != null && notification.actionUrl!.isNotEmpty) {
      NotificationNavigationService.handleNotificationTap(
        {
          'type': notification.type,
          'action_url': notification.actionUrl,
        },
        context,
      );
    } else {
      // Show notification details in a bottom sheet
      _showNotificationDetails(notification);
    }
  }

  void _showNotificationDetails(AppNotification notification) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = NotificationNavigationService.getColorForType(notification.type);
    final icon = NotificationNavigationService.getIconForType(notification.type);

    // Parse items from message (e.g., "HAYWARDS 5000 - 500ML, GOD FATHER - 500ML +4 more • 1 low stock")
    final parsedItems = _parseNotificationItems(notification.message);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Fixed Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Header with icon
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(icon, color: iconColor, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notification.title,
                                  style: AppTextStyles.h5.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: iconColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _getReadableType(notification.type),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: iconColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatTime(notification.createdAt),
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(color: cs.outlineVariant),
                    ],
                  ),
                ),

                // Scrollable Content
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show parsed items as cards if available
                        if (parsedItems.isNotEmpty) ...[
                          Text(
                            'Items',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...parsedItems.map((item) => _buildItemCard(item, iconColor)),
                          const SizedBox(height: 16),
                        ] else ...[
                          // Show raw message if no items parsed
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Text(
                              notification.message,
                              style: AppTextStyles.bodyMedium.copyWith(
                                height: 1.6,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Metadata if present
                        if (notification.metadata != null &&
                            notification.metadata!.isNotEmpty) ...[
                          Text(
                            'Details',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Column(
                              children: notification.metadata!.entries
                                  .where((e) => e.key != 'items' && e.key != 'products')
                                  .map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${_formatKey(entry.key)}:',
                                            style: AppTextStyles.bodySmall.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${entry.value}',
                                              style: AppTextStyles.bodySmall.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              NotificationNavigationService.handleNotificationTap(
                                {
                                  'type': notification.type,
                                  'action_url': notification.actionUrl ?? '',
                                },
                                context,
                              );
                            },
                            icon: Icon(
                              _getActionIcon(notification.type),
                              size: 20,
                            ),
                            label: Text(
                              _getActionLabel(notification),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: iconColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Build item card for notification detail
  Widget _buildItemCard(Map<String, String> item, Color iconColor) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item['status'] == 'out_of_stock'
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              color: item['status'] == 'out_of_stock' ? Colors.red : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'Unknown Item',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item['size'] != null)
                  Text(
                    item['size']!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: item['status'] == 'out_of_stock'
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item['status'] == 'out_of_stock' ? 'Out of Stock' : 'Low Stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: item['status'] == 'out_of_stock' ? Colors.red : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Parse notification message to extract items
  List<Map<String, String>> _parseNotificationItems(String message) {
    final items = <Map<String, String>>[];

    // Pattern: "BRAND NAME - SIZE, ANOTHER BRAND - SIZE +N more • M low stock"
    // Example: "HAYWARDS 5000 - 500ML, GOD FATHER - 500ML +4 more • 1 low stock → Tap to view"

    // Remove the trailing part
    String cleanMessage = message
        .replaceAll('→ Tap to view', '')
        .replaceAll('→ Tap to check', '')
        .trim();

    // Check if it's a stock alert type message
    if (!cleanMessage.contains(' - ')) {
      return items;
    }

    // Split by bullet point to separate items from summary
    final parts = cleanMessage.split('•');
    final itemsPart = parts.first.trim();

    // Check for "+N more" pattern
    final moreMatch = RegExp(r'\+(\d+) more').firstMatch(itemsPart);
    String itemsString = itemsPart;
    if (moreMatch != null) {
      itemsString = itemsPart.substring(0, moreMatch.start).trim();
      if (itemsString.endsWith(',')) {
        itemsString = itemsString.substring(0, itemsString.length - 1);
      }
    }

    // Split by comma and parse each item
    final itemStrings = itemsString.split(',');
    for (var itemStr in itemStrings) {
      itemStr = itemStr.trim();
      if (itemStr.isEmpty) continue;

      // Pattern: "BRAND NAME - SIZE"
      final dashIndex = itemStr.lastIndexOf(' - ');
      if (dashIndex > 0) {
        final name = itemStr.substring(0, dashIndex).trim();
        final size = itemStr.substring(dashIndex + 3).trim();
        items.add({
          'name': name,
          'size': size,
          'status': 'out_of_stock',
        });
      } else {
        items.add({
          'name': itemStr,
          'status': 'out_of_stock',
        });
      }
    }

    return items;
  }

  /// Get readable type name
  String _getReadableType(String type) {
    switch (type.toLowerCase()) {
      case 'system':
        return 'STOCK ALERT';
      case 'low_stock':
      case 'out_of_stock':
        return 'STOCK ALERT';
      case 'sales':
        return 'SALES';
      case 'cash':
        return 'CASH';
      case 'finance':
        return 'FINANCE';
      case 'inventory':
        return 'INVENTORY';
      default:
        return type.toUpperCase();
    }
  }

  String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');
  }

  /// Get action button icon based on notification type
  IconData _getActionIcon(String type) {
    final lowerType = type.toLowerCase();

    if (lowerType.contains('stock') || lowerType.contains('inventory')) {
      return Icons.inventory_2_rounded;
    }
    if (lowerType.contains('sales') || lowerType.contains('sale')) {
      return Icons.point_of_sale_rounded;
    }
    if (lowerType.contains('cash')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (lowerType.contains('finance')) {
      return Icons.attach_money_rounded;
    }

    return Icons.arrow_forward_rounded;
  }

  /// Get action button label based on notification
  String _getActionLabel(AppNotification notification) {
    // Use custom label if provided
    if (notification.actionLabel != null && notification.actionLabel!.isNotEmpty) {
      return notification.actionLabel!;
    }

    // Generate label based on type
    final lowerType = notification.type.toLowerCase();

    if (lowerType.contains('stock') || lowerType.contains('out_of')) {
      return 'View Inventory';
    }
    if (lowerType.contains('sales') || lowerType.contains('sale')) {
      return 'View Sales';
    }
    if (lowerType.contains('cash')) {
      return 'View Cash';
    }
    if (lowerType.contains('finance')) {
      return 'View Finance';
    }
    if (lowerType.contains('inventory')) {
      return 'View Inventory';
    }

    return 'View Details';
  }
}
