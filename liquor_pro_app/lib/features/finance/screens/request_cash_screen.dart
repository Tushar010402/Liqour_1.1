import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider_pkg;
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../providers/cash_provider.dart';
import '../models/cash_models.dart';

/// Modern iOS 16 Request Cash Screen
/// Features:
/// - Shows available cash balances
/// - Frontend validation to prevent over-requesting
/// - Settings-style bordered containers
/// - User-friendly error messages
/// - Can be embedded in a bottom sheet or used standalone
class RequestCashScreen extends ConsumerStatefulWidget {
  /// Optional scroll controller for when embedded in a DraggableScrollableSheet
  final ScrollController? scrollController;

  /// Whether this screen is embedded (e.g., in a bottom sheet)
  /// When embedded, the Scaffold and AppBar are not shown
  final bool isEmbedded;

  /// Callback when the cash request is successfully created
  final VoidCallback? onSuccess;

  const RequestCashScreen({
    super.key,
    this.scrollController,
    this.isEmbedded = false,
    this.onSuccess,
  });

  @override
  ConsumerState<RequestCashScreen> createState() => _RequestCashScreenState();
}

class _RequestCashScreenState extends ConsumerState<RequestCashScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _amountFocusNode = FocusNode();

  String? _selectedUserId;
  double? _selectedUserAvailableCash;
  bool _isSubmitting = false;
  String? _currentUserId; // To filter out self from list

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load current user ID to filter out self from list
    if (_currentUserId == null) {
      _loadCurrentUserId();
    }
  }

  Future<void> _loadCurrentUserId() async {
    final authService = provider_pkg.Provider.of<AuthService>(context, listen: false);
    final userId = await authService.getUserId();
    if (mounted && _currentUserId == null) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myBalanceAsync = ref.watch(cashBalanceProvider);
    final teamBalancesAsync = ref.watch(teamBalancesProvider);
    final tenantUsersAsync = ref.watch(tenantUsersProvider);

    // Build the main content widget
    Widget content = FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          // My Balance Card
          _buildMyBalanceCard(myBalanceAsync),

          // Main Content
          Expanded(
            child: tenantUsersAsync.when(
              data: (users) {
                if (users.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildContent(users, teamBalancesAsync);
              },
              loading: () => const Center(
                child: CupertinoActivityIndicator(radius: 16),
              ),
              error: (error, _) => _buildErrorState(error.toString()),
            ),
          ),
        ],
      ),
    );

    // If embedded (e.g., in a bottom sheet), return just the content
    if (widget.isEmbedded) {
      return Container(
        color: cs.surface,
        child: content,
      );
    }

    // Standalone mode - return full Scaffold with CustomAppBar
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const CustomAppBar(title: 'Request Cash'),
      body: SafeArea(child: content),
    );
  }

  Widget _buildMyBalanceCard(AsyncValue<double> myBalanceAsync) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.all(iOSDesignTokens.space16),
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.15),
                  cs.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.money_dollar_circle_fill,
              color: cs.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Cash Balance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                myBalanceAsync.when(
                  data: (balance) => Text(
                    Formatters.currency(balance),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  loading: () =>
                      const CupertinoActivityIndicator(radius: 10),
                  error: (_, __) => Text(
                    '\u20B90.00',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    List<TenantUser> users,
    AsyncValue<List<TeamCashBalance>> teamBalancesAsync,
  ) {
    // Show ALL users except current user
    // Users with 0 balance will be shown but disabled
    final allOtherUsers = users.where((user) {
      // Exclude current user - can't request cash from yourself
      if (_currentUserId != null && user.userId == _currentUserId) {
        return false;
      }
      return true;
    }).toList();

    // Sort: users with balance first, then by name
    allOtherUsers.sort((a, b) {
      if (a.currentBalance > 0 && b.currentBalance <= 0) return -1;
      if (a.currentBalance <= 0 && b.currentBalance > 0) return 1;
      return a.fullName.compareTo(b.fullName);
    });

    // Count users with available cash
    final usersWithCash = allOtherUsers.where((u) => u.currentBalance > 0).length;

    // If no other users at all, show empty state
    if (allOtherUsers.isEmpty) {
      return _buildNoAvailableCashState(0);
    }

    return Form(
      key: _formKey,
      child: CustomScrollView(
        slivers: [
          // Info Section
          SliverToBoxAdapter(child: _buildInfoSection()),

          // Show info about users with no cash
          if (usersWithCash == 0)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No team members have cash available right now',
                        style: TextStyle(color: Colors.orange[800], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Users List (ALL users, disabled if no balance)
          SliverToBoxAdapter(
            child: _buildUsersSection(allOtherUsers),
          ),

          // Amount Section (shown when user is selected)
          if (_selectedUserId != null) ...[
            SliverToBoxAdapter(child: _buildAmountSection()),
            SliverToBoxAdapter(child: _buildReasonSection()),
            SliverToBoxAdapter(child: _buildSubmitButton()),
          ],

          // Bottom Spacing
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.info_circle_fill,
            color: cs.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Request cash from team members. They must approve before transfer.',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredUsersInfo(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.eye_slash_fill,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count team ${count == 1 ? 'member' : 'members'} hidden (no cash available)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.warning.withValues(alpha: 0.9),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAvailableCashState(int totalUsers) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                CupertinoIcons.money_dollar_circle,
                size: 72,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'No Cash Available',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              totalUsers > 0
                  ? 'All $totalUsers team ${totalUsers == 1 ? 'member has' : 'members have'} \u20B90 balance.\nNo one can fulfill your request right now.'
                  : 'There are no team members available to request cash from.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.lightbulb_fill,
                    color: cs.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Try again later or contact your manager',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersSection(List<TenantUser> users) {
    final cs = Theme.of(context).colorScheme;
    // Group users by role
    final Map<String, List<TenantUser>> usersByRole = {};
    for (var user in users) {
      usersByRole.putIfAbsent(user.role, () => []).add(user);
    }

    final roleOrder = [
      'admin',
      'manager',
      'assistant_manager',
      'executive',
      'salesman',
    ];
    final orderedRoles = roleOrder
        .where((role) => usersByRole.containsKey(role))
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Select Team Member',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          ...orderedRoles.map((role) {
            final roleUsers = usersByRole[role]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role Header
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getRoleColor(role).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatRole(role),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _getRoleColor(role),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${roleUsers.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Users - using user.currentBalance directly
                ...roleUsers.map(
                  (user) => _buildUserCard(user, user.currentBalance),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUserCard(TenantUser user, double? availableCash) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = user.userId == _selectedUserId;
    final hasBalance = availableCash != null && availableCash > 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedUserId = user.userId;
          _selectedUserAvailableCash = availableCash;
        });

        // Auto-focus amount field after selection
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _amountFocusNode.requestFocus();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName.substring(0, 1).toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName, // Shows fullName if available, else username
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Balance Display - Show for all users
                    Row(
                      children: [
                        Icon(
                          hasBalance
                              ? CupertinoIcons.money_dollar_circle
                              : CupertinoIcons.info_circle,
                          size: 14,
                          color: hasBalance ? AppColors.success : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasBalance
                              ? 'Available: ${Formatters.currency(availableCash)}'
                              : 'Balance: \u20B90',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hasBalance ? AppColors.success : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Selection Indicator - Show for all users
              AnimatedScale(
                scale: isSelected ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: Icon(
                  isSelected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: isSelected
                      ? cs.primary
                      : Colors.black.withValues(alpha: 0.2),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request Amount',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),

          // Available cash info (informational only - requests allowed regardless)
          if (_selectedUserAvailableCash != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedUserAvailableCash! > 0
                    ? AppColors.success.withValues(alpha: 0.1)
                    : cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selectedUserAvailableCash! > 0
                      ? AppColors.success.withValues(alpha: 0.3)
                      : cs.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedUserAvailableCash! > 0
                        ? CupertinoIcons.checkmark_alt_circle_fill
                        : CupertinoIcons.info_circle_fill,
                    size: 16,
                    color: _selectedUserAvailableCash! > 0
                        ? AppColors.success
                        : cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedUserAvailableCash! > 0
                          ? 'User has ${Formatters.currency(_selectedUserAvailableCash!)} available'
                          : 'User has no cash - they can still approve & fulfill later',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedUserAvailableCash! > 0
                            ? AppColors.success
                            : cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Amount Input
          TextFormField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8, top: 12),
                child: Text(
                  '\u20B9',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              hintText: '0',
              hintStyle: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                borderSide: BorderSide(color: AppColors.error, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter amount';
              }
              final amount = double.tryParse(value);
              if (amount == null || amount <= 0) {
                return 'Please enter a valid amount';
              }
              // No validation against available cash - requests can be sent to any user
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Quick Amount Buttons - always enabled (requests allowed to any user)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [500, 1000, 2000, 5000, 10000].map((amount) {
              return _buildQuickAmountButton(amount, false); // Never disabled
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmountButton(int amount, bool isDisabled) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: isDisabled ? 0.3 : 1.0,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () => _amountController.text = amount.toString(),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isDisabled
                ? cs.surfaceContainerHighest
                : cs.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(
              color: isDisabled
                  ? cs.outlineVariant
                  : cs.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Text(
            '\u20B9${amount ~/ 1000}k',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDisabled ? cs.onSurfaceVariant : cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasonSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Reason',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Optional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonController,
            maxLines: 3,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText:
                  'e.g., "Shop float", "Daily expenses", "Change needed"...',
              hintStyle: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: !_isSubmitting ? _handleSubmit : null,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Ink(
            decoration: BoxDecoration(
              gradient: _isSubmitting
                  ? LinearGradient(
                      colors: [cs.outlineVariant, cs.outline],
                    )
                  : LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                    ),
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: _isSubmitting
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.paperplane_fill,
                          color: Colors.white,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Send Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.person_2,
                size: 64,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Team Members',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There are no other users to request cash from at the moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Users',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUserId == null) {
      SnackbarHelper.showError(context, 'Please select a user');
      return;
    }

    // Get the selected shop ID from the provider (optional)
    final shopProvider = provider_pkg.Provider.of<ShopSelectionProvider>(
      context,
      listen: false,
    );
    final selectedShopId = shopProvider.selectedShopId;

    // No validation for available cash - requests can be sent to any user
    // User can approve and fulfill the request later when they have cash
    final amount = double.parse(_amountController.text.trim());

    setState(() => _isSubmitting = true);

    try {
      final notes = _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim();

      // Cash requests: executiveId required, shopId optional (backend updated)
      final cashNotifier = ref.read(cashNotifierProvider.notifier);
      final request = await cashNotifier.createCashRequest(
        executiveId: _selectedUserId!, // The user to request cash FROM
        shopId: selectedShopId, // Optional - will be included if selected
        amount: amount,
        notes: notes,
      );

      if (request != null) {
        if (mounted) {
          SnackbarHelper.showSuccess(
            context,
            'Request sent for ${Formatters.currency(amount)}',
          );
          // Call onSuccess callback if provided (for embedded mode)
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          } else {
            Navigator.pop(context, true);
          }
        }
      } else {
        throw Exception('Failed to create cash request');
      }
    } catch (e) {
      if (mounted) {
        // Use parsed error for user-friendly display
        SnackbarHelper.showParsedError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Color _getRoleColor(String role) {
    final cs = Theme.of(context).colorScheme;
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFFE91E63);
      case 'manager':
        return const Color(0xFFFF9800);
      case 'assistant_manager':
        return const Color(0xFF2196F3);
      case 'executive':
        return cs.primary;
      case 'salesman':
        return AppColors.success;
      default:
        return AppColors.neutral;
    }
  }

  String _formatRole(String role) {
    return role.replaceAll('_', ' ').toUpperCase();
  }
}
