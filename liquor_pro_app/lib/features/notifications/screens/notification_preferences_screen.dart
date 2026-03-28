import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/notification_models.dart';
import '../providers/notification_provider.dart';

/// iOS 26 Style Notification Preferences Screen
/// Glassmorphism design with 100% backend API sync
/// Features: Channel toggles, Category settings, Time-based reminders, Quiet hours
/// ALL settings are synced to backend - no local-only storage
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen>
    with SingleTickerProviderStateMixin {
  // All preferences from backend API - 100% synced
  NotificationPreferences? _prefs;

  bool _isLoading = true;
  bool _hasChanges = false;
  bool _isSaving = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadAllSettings();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    setState(() => _isLoading = true);
    try {
      // Load ALL settings from backend API
      final prefsAsync = await ref.read(notificationPrefsProvider.future);

      if (mounted) {
        setState(() {
          _prefs = prefsAsync;
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      debugPrint('Error loading notification settings: $e');
      if (mounted) {
        setState(() {
          _prefs = NotificationPreferences();
          _isLoading = false;
        });
        _animController.forward();
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_prefs == null || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      // Save ALL preferences to backend API - 100% sync
      final notifier = ref.read(notificationNotifierProvider.notifier);
      final success = await notifier.updatePreferences(_prefs!);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasChanges = false;
        });

        if (success) {
          _showSuccessSheet();
        } else {
          _showErrorSheet('Failed to save preferences to server');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showErrorSheet('Error: $e');
      }
    }
  }

  void _updatePrefs(NotificationPreferences newPrefs) {
    HapticFeedback.selectionClick();
    setState(() {
      _prefs = newPrefs;
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        body: _isLoading
            ? _buildLoadingState(isDark)
            : _buildContent(isDark),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        _buildBackgroundGradient(isDark),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha:0.1)
                      : Colors.black.withValues(alpha:0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const CupertinoActivityIndicator(radius: 16),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading settings...',
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundGradient(bool isDark) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF0F0F1A)]
                : [const Color(0xFFF8F9FF), const Color(0xFFF2F2F7)],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return Stack(
      children: [
        _buildBackgroundGradient(isDark),
        _buildDecorativeCircles(isDark),
        CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            _buildAppBar(isDark),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Notification Channels', isDark),
                      const SizedBox(height: 8),
                      _buildChannelsCard(isDark),
                      const SizedBox(height: 28),
                      _buildSectionHeader('Category Settings', isDark),
                      const SizedBox(height: 8),
                      _buildCategoriesCard(isDark),
                      const SizedBox(height: 28),
                      _buildSectionHeader('Daily Reminders', isDark),
                      _buildSectionSubheader(
                        'Set times to receive alerts for important tasks',
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      ..._buildReminderCards(isDark),
                      const SizedBox(height: 28),
                      _buildSectionHeader('Quiet Hours', isDark),
                      const SizedBox(height: 8),
                      _buildQuietHoursCard(isDark),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_hasChanges) _buildFloatingSaveButton(isDark),
      ],
    );
  }

  Widget _buildDecorativeCircles(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cs.primary.withValues(alpha: isDark ? 0.3 : 0.15),
                  cs.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.purple.withValues(alpha: isDark ? 0.2 : 0.1),
                  Colors.purple.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 100,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: _buildGlassBackButton(isDark),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: FlexibleSpaceBar(
            centerTitle: true,
            title: Text(
              'Notifications',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [Colors.black.withValues(alpha:0.7), Colors.black.withValues(alpha:0.0)]
                      : [Colors.white.withValues(alpha:0.8), Colors.white.withValues(alpha:0.0)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBackButton(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (_hasChanges) {
            _showUnsavedChangesSheet();
          } else {
            Navigator.pop(context);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha:0.1)
                    : Colors.black.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha:0.1)
                      : Colors.black.withValues(alpha:0.05),
                ),
              ),
              child: Icon(
                CupertinoIcons.back,
                size: 20,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildSectionSubheader(String text, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  // ============================================================================
  // NOTIFICATION CHANNELS CARD
  // ============================================================================

  Widget _buildChannelsCard(bool isDark) {
    if (_prefs == null) return const SizedBox.shrink();

    return _buildGlassCard(
      isDark: isDark,
      child: Column(
        children: [
          _buildChannelToggle(
            icon: CupertinoIcons.app_badge_fill,
            iconColor: Colors.orange,
            title: 'In-App Notifications',
            subtitle: 'Show notifications within the app',
            value: _prefs!.channels.inApp,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(
              channels: _prefs!.channels.copyWith(inApp: v),
            )),
            isDark: isDark,
          ),
          _buildGlassDivider(isDark),
          _buildChannelToggle(
            icon: CupertinoIcons.bell_fill,
            iconColor: Theme.of(context).colorScheme.primary,
            title: 'Push Notifications',
            subtitle: 'Receive push alerts on this device',
            value: _prefs!.channels.push,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(
              channels: _prefs!.channels.copyWith(push: v),
            )),
            isDark: isDark,
          ),
          _buildGlassDivider(isDark),
          _buildChannelToggle(
            icon: CupertinoIcons.mail_solid,
            iconColor: Colors.blue,
            title: 'Email Notifications',
            subtitle: 'Receive important updates via email',
            value: _prefs!.channels.email,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(
              channels: _prefs!.channels.copyWith(email: v),
            )),
            isDark: isDark,
          ),
          _buildGlassDivider(isDark),
          _buildChannelToggle(
            icon: CupertinoIcons.chat_bubble_text_fill,
            iconColor: Colors.green,
            title: 'SMS Notifications',
            subtitle: 'Receive urgent alerts via SMS',
            value: _prefs!.channels.sms,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(
              channels: _prefs!.channels.copyWith(sms: v),
            )),
            isDark: isDark,
          ),
          _buildGlassDivider(isDark),
          _buildChannelToggle(
            icon: CupertinoIcons.phone_circle_fill,
            iconColor: const Color(0xFF25D366),
            title: 'WhatsApp Notifications',
            subtitle: 'Receive updates via WhatsApp',
            value: _prefs!.channels.whatsapp,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(
              channels: _prefs!.channels.copyWith(whatsapp: v),
            )),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha:0.2)),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: iconColor,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // CATEGORY SETTINGS
  // ============================================================================

  Widget _buildCategoriesCard(bool isDark) {
    if (_prefs == null) return const SizedBox.shrink();

    final categories = [
      {'key': 'sales', 'name': 'Sales', 'icon': CupertinoIcons.cart_fill, 'color': AppColors.success, 'description': 'Daily sales, transactions'},
      {'key': 'inventory', 'name': 'Inventory', 'icon': CupertinoIcons.cube_box_fill, 'color': Theme.of(context).colorScheme.primary, 'description': 'Stock alerts, low inventory'},
      {'key': 'finance', 'name': 'Finance', 'icon': CupertinoIcons.money_dollar_circle_fill, 'color': Colors.orange, 'description': 'Cash management, expenses'},
      {'key': 'audit', 'name': 'Audit', 'icon': CupertinoIcons.doc_checkmark_fill, 'color': Colors.purple, 'description': 'Compliance, reports'},
      {'key': 'theft', 'name': 'Security', 'icon': CupertinoIcons.shield_fill, 'color': Colors.red, 'description': 'Security alerts, theft detection'},
      {'key': 'system', 'name': 'System', 'icon': CupertinoIcons.gear_alt_fill, 'color': Theme.of(context).colorScheme.onSurfaceVariant, 'description': 'App updates, maintenance'},
    ];

    return _buildGlassCard(
      isDark: isDark,
      child: Column(
        children: categories.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          final key = cat['key'] as String;
          final pref = _prefs!.categoryPreferences[key] ?? ChannelPreference.defaults();
          final isLast = i == categories.length - 1;

          return Column(
            children: [
              _buildCategoryRow(
                icon: cat['icon'] as IconData,
                iconColor: cat['color'] as Color,
                title: cat['name'] as String,
                description: cat['description'] as String,
                pref: pref,
                onTap: () => _showCategorySettingsSheet(key, cat['name'] as String, cat['color'] as Color, pref, isDark),
                isDark: isDark,
              ),
              if (!isLast) _buildGlassDivider(isDark),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required ChannelPreference pref,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    int enabledCount = 0;
    if (pref.inApp) enabledCount++;
    if (pref.push) enabledCount++;
    if (pref.email) enabledCount++;
    if (pref.sms) enabledCount++;
    if (pref.whatsapp) enabledCount++;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withValues(alpha:0.2)),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: enabledCount > 0
                    ? iconColor.withValues(alpha:0.15)
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha:0.05)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$enabledCount active',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabledCount > 0 ? iconColor : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DAILY REMINDERS - Synced to backend
  // ============================================================================

  List<Widget> _buildReminderCards(bool isDark) {
    if (_prefs == null) return [];

    return _prefs!.reminders.asMap().entries.map((entry) {
      final index = entry.key;
      final reminder = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildReminderCard(reminder, index, isDark),
      );
    }).toList();
  }

  Widget _buildReminderCard(ReminderSettings reminder, int index, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final categoryIcons = {
      'sales': CupertinoIcons.cart_fill,
      'inventory': CupertinoIcons.cube_box_fill,
      'finance': CupertinoIcons.money_dollar_circle_fill,
      'security': CupertinoIcons.shield_fill,
      'system': CupertinoIcons.gear_alt_fill,
    };

    final categoryColors = {
      'sales': AppColors.success,
      'inventory': cs.primary,
      'finance': Colors.orange,
      'security': Colors.red,
      'system': Theme.of(context).colorScheme.onSurfaceVariant,
    };

    final icon = categoryIcons[reminder.category] ?? CupertinoIcons.bell_fill;
    final color = categoryColors[reminder.category] ?? cs.primary;

    return _buildGlassCard(
      isDark: isDark,
      borderColor: reminder.enabled ? color.withValues(alpha:0.3) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color.withValues(alpha:0.2), color.withValues(alpha:0.1)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha:0.3)),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reminder.description,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: reminder.enabled,
                  onChanged: (v) => _updateReminder(index, reminder.copyWith(enabled: v)),
                  activeTrackColor: color,
                ),
              ],
            ),
          ),
          if (reminder.enabled) ...[
            Divider(height: 1, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTimeButton(
                      label: 'Alert Time',
                      time: reminder.formattedTime,
                      icon: CupertinoIcons.clock_fill,
                      color: color,
                      onTap: () => _showTimePicker(reminder, index, color),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDaysButton(
                      label: 'Repeat',
                      days: reminder.formattedDays,
                      icon: CupertinoIcons.calendar,
                      color: color,
                      onTap: () => _showDaysPicker(reminder, index, color),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeButton({
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(time, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildDaysButton({
    required String label,
    required String days,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(days, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _updateReminder(int index, ReminderSettings reminder) {
    if (_prefs == null) return;
    final reminders = List<ReminderSettings>.from(_prefs!.reminders);
    reminders[index] = reminder;
    _updatePrefs(_prefs!.copyWith(reminders: reminders));
  }

  // ============================================================================
  // QUIET HOURS
  // ============================================================================

  Widget _buildQuietHoursCard(bool isDark) {
    if (_prefs == null) return const SizedBox.shrink();

    return _buildGlassCard(
      isDark: isDark,
      child: Column(
        children: [
          _buildChannelToggle(
            icon: CupertinoIcons.moon_fill,
            iconColor: Colors.indigo,
            title: 'Do Not Disturb',
            subtitle: 'Pause notifications during set hours',
            value: _prefs!.quietHoursEnabled,
            onChanged: (v) => _updatePrefs(_prefs!.copyWith(quietHoursEnabled: v)),
            isDark: isDark,
          ),
          if (_prefs!.quietHoursEnabled) ...[
            _buildGlassDivider(isDark),
            _buildQuietHoursSelector(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildQuietHoursSelector(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final start = _prefs?.quietHoursStartTime ?? const TimeOfDay(hour: 22, minute: 0);
    final end = _prefs?.quietHoursEndTime ?? const TimeOfDay(hour: 7, minute: 0);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _buildQuietTimeButton(label: 'From', time: start, onTap: () => _selectQuietTime(true), isDark: isDark)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(CupertinoIcons.arrow_right, size: 20, color: cs.onSurfaceVariant),
          ),
          Expanded(child: _buildQuietTimeButton(label: 'To', time: end, onTap: () => _selectQuietTime(false), isDark: isDark)),
        ],
      ),
    );
  }

  Widget _buildQuietTimeButton({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.indigo.withValues(alpha:isDark ? 0.2 : 0.1),
              Colors.purple.withValues(alpha:isDark ? 0.15 : 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.indigo.withValues(alpha:0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$hour:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.indigo.shade400),
                ),
                const SizedBox(width: 4),
                Text(period, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo.shade300)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // GLASS CARD COMPONENTS
  // ============================================================================

  Widget _buildGlassCard({required bool isDark, required Widget child, Color? borderColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha:0.08) : Colors.white.withValues(alpha:0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ?? (isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
              width: borderColor != null ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha:isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 74),
      child: Divider(height: 1, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
    );
  }

  // ============================================================================
  // FLOATING SAVE BUTTON
  // ============================================================================

  Widget _buildFloatingSaveButton(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: 20,
      right: 20,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: GestureDetector(
        onTap: _isSaving ? null : _saveSettings,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withBlue(200)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Center(
            child: _isSaving
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text('Save Changes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // iOS 26 STYLE BOTTOM SHEETS - SWIPE TO DISMISS
  // ============================================================================

  void _showTimePicker(ReminderSettings reminder, int index, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tod = reminder.timeOfDay;
    DateTime tempTime = DateTime(2025, 1, 1, tod.hour, tod.minute);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _iOS26Sheet(
        isDark: isDark,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSheetHandle(isDark),
            _buildSheetHeader(
              title: 'Set Alert Time',
              color: color,
              onCancel: () => Navigator.pop(ctx),
              onDone: () {
                Navigator.pop(ctx);
                final timeString = _formatTimeOfDayToString(TimeOfDay(hour: tempTime.hour, minute: tempTime.minute));
                _updateReminder(index, reminder.copyWith(time: timeString));
              },
              isDark: isDark,
            ),
            SizedBox(
              height: 220,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: tempTime,
                onDateTimeChanged: (dt) => tempTime = dt,
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showDaysPicker(ReminderSettings reminder, int index, Color color) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<String> selectedDays = List.from(reminder.days);

    final allDays = [
      {'key': 'mon', 'name': 'Monday', 'short': 'M'},
      {'key': 'tue', 'name': 'Tuesday', 'short': 'T'},
      {'key': 'wed', 'name': 'Wednesday', 'short': 'W'},
      {'key': 'thu', 'name': 'Thursday', 'short': 'T'},
      {'key': 'fri', 'name': 'Friday', 'short': 'F'},
      {'key': 'sat', 'name': 'Saturday', 'short': 'S'},
      {'key': 'sun', 'name': 'Sunday', 'short': 'S'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => _iOS26Sheet(
          isDark: isDark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(isDark),
              _buildSheetHeader(
                title: 'Repeat Days',
                color: color,
                onCancel: () => Navigator.pop(ctx),
                onDone: () {
                  Navigator.pop(ctx);
                  _updateReminder(index, reminder.copyWith(days: selectedDays.isEmpty ? ['daily'] : selectedDays));
                },
                isDark: isDark,
              ),
              // Quick Select
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    _buildQuickChip('Every Day', selectedDays.length == 7 || selectedDays.contains('daily'), () {
                      setSheetState(() => selectedDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']);
                    }, color, isDark),
                    const SizedBox(width: 8),
                    _buildQuickChip('Weekdays', selectedDays.length == 5 && !selectedDays.contains('sat') && !selectedDays.contains('sun'), () {
                      setSheetState(() => selectedDays = ['mon', 'tue', 'wed', 'thu', 'fri']);
                    }, color, isDark),
                    const SizedBox(width: 8),
                    _buildQuickChip('Weekends', selectedDays.length == 2 && selectedDays.contains('sat') && selectedDays.contains('sun'), () {
                      setSheetState(() => selectedDays = ['sat', 'sun']);
                    }, color, isDark),
                  ],
                ),
              ),
              // Days List
              SizedBox(
                height: 320,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: allDays.length,
                  itemBuilder: (_, i) {
                    final day = allDays[i];
                    final isSelected = selectedDays.contains(day['key']) || selectedDays.contains('daily');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() {
                            selectedDays.remove('daily');
                            if (isSelected) {
                              selectedDays.remove(day['key']);
                            } else {
                              selectedDays.add(day['key']!);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha:0.15) : (isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? color.withValues(alpha:0.4) : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isSelected ? color.withValues(alpha:0.2) : (isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    day['short']!,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? color : cs.onSurfaceVariant),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                day['name']!,
                                style: TextStyle(fontSize: 16, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? color : cs.onSurface),
                              ),
                              const Spacer(),
                              if (isSelected) Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 22),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, bool isSelected, VoidCallback onTap, Color color, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha:0.2) : (isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color.withValues(alpha:0.4) : Colors.transparent),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? color : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  String _formatTimeOfDayToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _selectQuietTime(bool isStart) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = isStart
        ? (_prefs?.quietHoursStartTime ?? const TimeOfDay(hour: 22, minute: 0))
        : (_prefs?.quietHoursEndTime ?? const TimeOfDay(hour: 7, minute: 0));
    DateTime tempTime = DateTime(2025, 1, 1, current.hour, current.minute);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _iOS26Sheet(
        isDark: isDark,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSheetHandle(isDark),
            _buildSheetHeader(
              title: isStart ? 'Start Time' : 'End Time',
              color: Colors.indigo,
              onCancel: () => Navigator.pop(ctx),
              onDone: () {
                Navigator.pop(ctx);
                final newTime = TimeOfDay(hour: tempTime.hour, minute: tempTime.minute);
                final timeString = _formatTimeOfDayToString(newTime);
                if (isStart) {
                  _updatePrefs(_prefs!.copyWith(quietHoursStart: timeString));
                } else {
                  _updatePrefs(_prefs!.copyWith(quietHoursEnd: timeString));
                }
              },
              isDark: isDark,
            ),
            SizedBox(
              height: 220,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: tempTime,
                onDateTimeChanged: (dt) => tempTime = dt,
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showCategorySettingsSheet(String key, String name, Color color, ChannelPreference pref, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          ChannelPreference currentPref = pref;

          return _iOS26Sheet(
            isDark: isDark,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSheetHandle(isDark),
                const SizedBox(height: 16),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha:0.2), color.withValues(alpha:0.1)]),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withValues(alpha:0.3)),
                        ),
                        child: Icon(CupertinoIcons.bell_fill, color: color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$name Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
                            Text('Configure alert channels', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Channel Options
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildChannelOption('In-App', CupertinoIcons.app_badge_fill, Colors.orange, currentPref.inApp, (v) {
                        setSheetState(() => currentPref = currentPref.copyWith(inApp: v));
                        _updateCategoryPref(key, currentPref);
                      }, isDark),
                      _buildChannelOption('Push', CupertinoIcons.bell_fill, cs.primary, currentPref.push, (v) {
                        setSheetState(() => currentPref = currentPref.copyWith(push: v));
                        _updateCategoryPref(key, currentPref);
                      }, isDark),
                      _buildChannelOption('Email', CupertinoIcons.mail_solid, Colors.blue, currentPref.email, (v) {
                        setSheetState(() => currentPref = currentPref.copyWith(email: v));
                        _updateCategoryPref(key, currentPref);
                      }, isDark),
                      _buildChannelOption('SMS', CupertinoIcons.chat_bubble_text_fill, Colors.green, currentPref.sms, (v) {
                        setSheetState(() => currentPref = currentPref.copyWith(sms: v));
                        _updateCategoryPref(key, currentPref);
                      }, isDark),
                      _buildChannelOption('WhatsApp', CupertinoIcons.phone_circle_fill, const Color(0xFF25D366), currentPref.whatsapp, (v) {
                        setSheetState(() => currentPref = currentPref.copyWith(whatsapp: v));
                        _updateCategoryPref(key, currentPref);
                      }, isDark),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelOption(String label, IconData icon, Color iconColor, bool value, ValueChanged<bool> onChanged, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: value ? iconColor.withValues(alpha:0.3) : (isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: value ? iconColor : cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface)),
            const Spacer(),
            CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: iconColor),
          ],
        ),
      ),
    );
  }

  void _updateCategoryPref(String key, ChannelPreference pref) {
    if (_prefs == null) return;
    // The new backend model uses a single channels object for all categories
    // Update the main channels settings based on category preference changes
    _updatePrefs(_prefs!.copyWith(
      channels: ChannelSettings(
        inApp: pref.inApp,
        push: pref.push,
        email: pref.email,
        sms: pref.sms,
        whatsapp: pref.whatsapp,
      ),
    ));
  }

  // ============================================================================
  // iOS 26 SHEET COMPONENTS
  // ============================================================================

  Widget _iOS26Sheet({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: child,
      ),
    );
  }

  Widget _buildSheetHandle(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildSheetHeader({
    required String title,
    required Color color,
    required VoidCallback onCancel,
    required VoidCallback onDone,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: onCancel,
            child: Text('Cancel', style: TextStyle(fontSize: 17, color: cs.onSurfaceVariant)),
          ),
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: onDone,
            child: Text('Done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // SUCCESS / ERROR / UNSAVED SHEETS
  // ============================================================================

  void _showSuccessSheet() {
    HapticFeedback.heavyImpact();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _iOS26Sheet(
        isDark: isDark,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(isDark),
              const SizedBox(height: 24),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.success.withValues(alpha:0.2), AppColors.success.withValues(alpha:0.1)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.checkmark_circle_fill, color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 20),
              Text('Settings Saved', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Your notification preferences have been updated',
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSheet(String message) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _iOS26Sheet(
        isDark: isDark,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(isDark),
              const SizedBox(height: 24),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.red.withValues(alpha:0.2), Colors.red.withValues(alpha:0.1)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red, size: 48),
              ),
              const SizedBox(height: 20),
              Text('Error', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: Colors.red,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnsavedChangesSheet() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parentNav = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _iOS26Sheet(
        isDark: isDark,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(isDark),
              const SizedBox(height: 24),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.orange.withValues(alpha:0.2), Colors.orange.withValues(alpha:0.1)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 36),
              ),
              const SizedBox(height: 20),
              Text('Unsaved Changes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text('Do you want to save your changes?', style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: Colors.red.withValues(alpha:0.15),
                      onPressed: () {
                        Navigator.pop(ctx);
                        parentNav.pop();
                      },
                      child: const Text('Discard', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _saveSettings();
                        if (mounted && !_hasChanges) {
                          parentNav.pop();
                        }
                      },
                      child: const Text('Save', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
