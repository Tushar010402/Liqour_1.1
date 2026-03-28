import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../core/permissions/models/role_permission_model.dart';
import '../../../core/permissions/providers/permission_provider.dart';
import '../models/user_management_models.dart';

/// AdaptiveUserCard - Responsive user card that adapts to screen size
///
/// Features:
/// - Phone (<600px): Compact 72pt height
/// - Tablet (600-1200px): Extended 96pt with more details
/// - Permission-aware action buttons
/// - Glass card styling
/// - Swipe actions for edit/delete (optional)
///
/// Usage:
/// ```dart
/// AdaptiveUserCard(
///   user: user,
///   onTap: () => showUserDetail(user),
///   onEdit: () => showEditDialog(user),
///   onDelete: () => confirmDelete(user),
///   onToggleStatus: () => toggleStatus(user),
/// )
/// ```
class AdaptiveUserCard extends StatelessWidget {
  /// User data to display
  final UserItem user;

  /// Tap callback for card
  final VoidCallback? onTap;

  /// Edit callback (shown based on permissions)
  final VoidCallback? onEdit;

  /// Delete callback (shown based on permissions)
  final VoidCallback? onDelete;

  /// Toggle status callback
  final VoidCallback? onToggleStatus;

  /// Whether the card is selected
  final bool isSelected;

  /// Whether to enable swipe actions (phone only)
  final bool enableSwipe;

  const AdaptiveUserCard({
    super.key,
    required this.user,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleStatus,
    this.isSelected = false,
    this.enableSwipe = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = ResponsiveUtils.isPhone(context);

    if (enableSwipe && isPhone) {
      return _buildSwipeableCard(context, isPhone);
    }

    return _buildCard(context, isPhone);
  }

  Widget _buildSwipeableCard(BuildContext context, bool isPhone) {
    return Consumer<PermissionProvider>(
      builder: (context, permissions, _) {
        final targetRole = AppRole.fromName(user.role);
        final canEdit = permissions.canManageUser(targetRole);
        final canDelete = permissions.canDeleteUser(targetRole);

        return Dismissible(
          key: Key(user.id),
          direction: DismissDirection.horizontal,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart && canDelete) {
              onDelete?.call();
              return false; // Don't actually dismiss
            } else if (direction == DismissDirection.startToEnd && canEdit) {
              onEdit?.call();
              return false;
            }
            return false;
          },
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: iOSDesignTokens.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerLeft,
            child: const Icon(
              CupertinoIcons.pencil,
              color: Colors.white,
            ),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: iOSDesignTokens.error,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            child: const Icon(
              CupertinoIcons.trash,
              color: Colors.white,
            ),
          ),
          child: _buildCard(context, isPhone),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, bool isPhone) {
    return Consumer<PermissionProvider>(
      builder: (context, permissions, _) {
        final targetRole = AppRole.fromName(user.role);
        final canManage = permissions.canManageUser(targetRole);
        final canDelete = permissions.canDeleteUser(targetRole);

        return GlassCard.light(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.all(isPhone ? 12 : 16),
          onTap: onTap,
          child: Row(
            children: [
              // Avatar
              _buildAvatar(isPhone),
              SizedBox(width: isPhone ? 12 : 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.displayName,
                            style: (isPhone
                                    ? iOSDesignTokens.bodyLarge
                                    : iOSDesignTokens.headlineSmall)
                                .copyWith(
                              fontWeight: FontWeight.w600,
                              color: iOSDesignTokens.neutralGray900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(isActive: user.isActive, compact: isPhone),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Email/Username
                    Text(
                      user.email.isNotEmpty ? user.email : '@${user.username}',
                      style: iOSDesignTokens.bodySmall.copyWith(
                        color: iOSDesignTokens.neutralGray600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Phone (tablet only)
                    if (!isPhone && user.phone != null && user.phone!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.phone,
                            size: 12,
                            color: iOSDesignTokens.neutralGray500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user.phone!,
                            style: iOSDesignTokens.labelSmall.copyWith(
                              color: iOSDesignTokens.neutralGray500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Role badge + actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoleBadge.fromName(user.role, compact: isPhone),
                  if (!isPhone && canManage) ...[
                    const SizedBox(height: 8),
                    _buildActionButtons(canDelete),
                  ],
                ],
              ),

              // Popup menu (phone only)
              if (isPhone && canManage) ...[
                const SizedBox(width: 4),
                _buildPopupMenu(canDelete),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(bool isPhone) {
    final size = isPhone ? 44.0 : 56.0;
    final role = AppRole.fromName(user.role);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: role?.backgroundColor ?? iOSDesignTokens.neutralGray200,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(
          color: role?.borderColor ?? iOSDesignTokens.neutralGray300,
          width: 2,
        ),
      ),
      child: user.profileImage != null && user.profileImage!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: Image.network(
                user.profileImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitials(isPhone),
              ),
            )
          : _buildInitials(isPhone),
    );
  }

  Widget _buildInitials(bool isPhone) {
    final role = AppRole.fromName(user.role);
    return Center(
      child: Text(
        user.initials,
        style: TextStyle(
          fontSize: isPhone ? 16 : 20,
          fontWeight: FontWeight.w700,
          color: role?.color ?? iOSDesignTokens.neutralGray600,
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool canDelete) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIconButton(
          icon: CupertinoIcons.pencil,
          color: iOSDesignTokens.primary,
          onTap: onEdit,
          tooltip: 'Edit',
        ),
        const SizedBox(width: 4),
        _ActionIconButton(
          icon: user.isActive
              ? CupertinoIcons.pause_circle
              : CupertinoIcons.play_circle,
          color: iOSDesignTokens.warning,
          onTap: onToggleStatus,
          tooltip: user.isActive ? 'Deactivate' : 'Activate',
        ),
        if (canDelete) ...[
          const SizedBox(width: 4),
          _ActionIconButton(
            icon: CupertinoIcons.trash,
            color: iOSDesignTokens.error,
            onTap: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ],
    );
  }

  Widget _buildPopupMenu(bool canDelete) {
    return PopupMenuButton<String>(
      icon: Icon(
        CupertinoIcons.ellipsis_vertical,
        color: iOSDesignTokens.neutralGray500,
        size: 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      offset: const Offset(0, 40),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'toggle':
            onToggleStatus?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(CupertinoIcons.pencil,
                  size: 18, color: iOSDesignTokens.primary),
              const SizedBox(width: 12),
              const Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                user.isActive
                    ? CupertinoIcons.pause_circle
                    : CupertinoIcons.play_circle,
                size: 18,
                color: iOSDesignTokens.warning,
              ),
              const SizedBox(width: 12),
              Text(user.isActive ? 'Deactivate' : 'Activate'),
            ],
          ),
        ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(CupertinoIcons.trash,
                    size: 18, color: iOSDesignTokens.error),
                const SizedBox(width: 12),
                Text('Delete',
                    style: TextStyle(color: iOSDesignTokens.error)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      ),
    );
  }
}
