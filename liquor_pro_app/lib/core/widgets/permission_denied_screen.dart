import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/ios_design_tokens.dart';
import '../permissions/models/role_permission_model.dart';
import 'role_badge.dart';

/// PermissionDeniedScreen - Full-screen 403 error with friendly UI
///
/// Features:
/// - Lock icon animation
/// - Current role badge
/// - Required role indicator
/// - "Go Back" and "Contact Admin" actions
///
/// Usage:
/// ```dart
/// PermissionDeniedScreen(
///   attemptedAction: 'manage users',
///   userRole: 'salesman',
///   requiredRole: 'Admin or Manager',
///   onGoBack: () => Navigator.pop(context),
/// )
/// ```
class PermissionDeniedScreen extends StatefulWidget {
  /// What the user tried to do (e.g., "manage users")
  final String? attemptedAction;

  /// Current user's role name
  final String? userRole;

  /// Required role to perform action
  final String? requiredRole;

  /// Callback when "Go Back" is pressed
  final VoidCallback? onGoBack;

  /// Callback when "Contact Admin" is pressed
  final VoidCallback? onContactAdmin;

  /// Custom title
  final String? title;

  /// Custom message
  final String? message;

  const PermissionDeniedScreen({
    super.key,
    this.attemptedAction,
    this.userRole,
    this.requiredRole,
    this.onGoBack,
    this.onContactAdmin,
    this.title,
    this.message,
  });

  @override
  State<PermissionDeniedScreen> createState() => _PermissionDeniedScreenState();
}

class _PermissionDeniedScreenState extends State<PermissionDeniedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bounceAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _bounceAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = AppRole.fromName(widget.userRole);

    return Scaffold(
      backgroundColor: iOSDesignTokens.neutralGray50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.onGoBack != null
            ? IconButton(
                icon: Icon(
                  CupertinoIcons.back,
                  color: iOSDesignTokens.neutralGray900,
                ),
                onPressed: widget.onGoBack,
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated lock icon
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _bounceAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: iOSDesignTokens.error.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.lock_shield_fill,
                          size: 60,
                          color: iOSDesignTokens.error,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Title
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Text(
                    widget.title ?? 'Access Restricted',
                    style: iOSDesignTokens.displaySmall.copyWith(
                      color: iOSDesignTokens.neutralGray900,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 12),

                // Message
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Text(
                    widget.message ??
                        (widget.attemptedAction != null
                            ? "You don't have permission to ${widget.attemptedAction}."
                            : "You don't have permission to access this feature."),
                    style: iOSDesignTokens.bodyLarge.copyWith(
                      color: iOSDesignTokens.neutralGray600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 32),

                // Role info card
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: iOSDesignTokens.neutralWhite,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: iOSDesignTokens.shadowSmall,
                    ),
                    child: Column(
                      children: [
                        // Your role
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.person_fill,
                              size: 20,
                              color: iOSDesignTokens.neutralGray500,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Your role:',
                              style: iOSDesignTokens.bodyMedium.copyWith(
                                color: iOSDesignTokens.neutralGray600,
                              ),
                            ),
                            const Spacer(),
                            if (role != null)
                              RoleBadge(role: role)
                            else
                              Text(
                                widget.userRole ?? 'Unknown',
                                style: iOSDesignTokens.bodyMedium.copyWith(
                                  color: iOSDesignTokens.neutralGray900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),

                        if (widget.requiredRole != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            height: 1,
                            color: iOSDesignTokens.neutralGray200,
                          ),
                          const SizedBox(height: 16),

                          // Required role
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.shield_fill,
                                size: 20,
                                color: iOSDesignTokens.warning,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Required:',
                                style: iOSDesignTokens.bodyMedium.copyWith(
                                  color: iOSDesignTokens.neutralGray600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                widget.requiredRole!,
                                style: iOSDesignTokens.bodyMedium.copyWith(
                                  color: iOSDesignTokens.neutralGray900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Action buttons
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      // Primary action - Go Back
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onGoBack ?? () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: iOSDesignTokens.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.arrow_left, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Go Back',
                                style: iOSDesignTokens.bodyLarge.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),

                      // Secondary action - Contact Admin
                      if (widget.onContactAdmin != null) ...[
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: widget.onContactAdmin,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.envelope,
                                  size: 18,
                                  color: iOSDesignTokens.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Contact Admin',
                                  style: iOSDesignTokens.bodyLarge.copyWith(
                                    color: iOSDesignTokens.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// PermissionDeniedWidget - Inline version for embedding in screens
///
/// Use when you want to show permission denied within a screen context
/// rather than as a full screen.
class PermissionDeniedWidget extends StatelessWidget {
  final String? message;
  final String? requiredRole;
  final VoidCallback? onRetry;

  const PermissionDeniedWidget({
    super.key,
    this.message,
    this.requiredRole,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: iOSDesignTokens.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.lock_fill,
                size: 40,
                color: iOSDesignTokens.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Access Restricted',
              style: iOSDesignTokens.headlineMedium.copyWith(
                color: iOSDesignTokens.neutralGray900,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? "You don't have permission to access this feature.",
              style: iOSDesignTokens.bodyMedium.copyWith(
                color: iOSDesignTokens.neutralGray600,
              ),
              textAlign: TextAlign.center,
            ),
            if (requiredRole != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: iOSDesignTokens.neutralGray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Required: $requiredRole',
                  style: iOSDesignTokens.labelMedium.copyWith(
                    color: iOSDesignTokens.neutralGray700,
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(CupertinoIcons.refresh, size: 18),
                label: Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
