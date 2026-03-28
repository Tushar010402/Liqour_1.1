import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/role_permission_model.dart';
import '../providers/permission_provider.dart';
import '../../theme/ios_design_tokens.dart';

/// RoleDropdownWidget - Dropdown that only shows roles current user can assign
///
/// Automatically filters available roles based on the current user's permission level.
///
/// Usage:
/// ```dart
/// RoleDropdownWidget(
///   selectedRole: selectedRoleName,
///   onChanged: (role) => setState(() => selectedRoleName = role),
///   label: 'User Role',
/// )
/// ```
class RoleDropdownWidget extends StatelessWidget {
  /// Currently selected role name (e.g., 'manager', 'salesman')
  final String? selectedRole;

  /// Callback when role selection changes
  final ValueChanged<String?> onChanged;

  /// Label text for the dropdown
  final String? label;

  /// Hint text when no role is selected
  final String? hint;

  /// Whether the dropdown is enabled
  final bool enabled;

  /// Whether to show role descriptions
  final bool showDescriptions;

  /// Optional prefix icon
  final IconData? prefixIcon;

  /// Optional validator for form validation
  final String? Function(String?)? validator;

  /// Whether to use iOS cupertino picker style on iOS
  final bool adaptivePicker;

  const RoleDropdownWidget({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.label,
    this.hint,
    this.enabled = true,
    this.showDescriptions = false,
    this.prefixIcon,
    this.validator,
    this.adaptivePicker = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PermissionProvider>(
      builder: (context, permissionProvider, _) {
        final assignableRoles = permissionProvider.assignableRoles;

        if (assignableRoles.isEmpty) {
          return _buildNoRolesAvailable();
        }

        // Validate current selection
        final validSelection = selectedRole != null &&
            assignableRoles.any((r) => r.name == selectedRole);

        return DropdownButtonFormField<String>(
          initialValue: validSelection ? selectedRole : null,
          decoration: InputDecoration(
            labelText: label ?? 'Role',
            hintText: hint ?? 'Select a role',
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: iOSDesignTokens.neutralGray500)
                : Icon(CupertinoIcons.person_crop_circle_badge_checkmark,
                    color: iOSDesignTokens.neutralGray500),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              borderSide: BorderSide(color: iOSDesignTokens.neutralGray300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              borderSide:
                  BorderSide(color: iOSDesignTokens.primary, width: 2),
            ),
            filled: true,
            fillColor: enabled
                ? iOSDesignTokens.neutralWhite
                : iOSDesignTokens.neutralGray100,
          ),
          items: assignableRoles.map((role) {
            return DropdownMenuItem<String>(
              value: role.name,
              child: _buildRoleItem(role),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
          validator: validator,
          isExpanded: true,
          icon: Icon(
            CupertinoIcons.chevron_down,
            color: enabled
                ? iOSDesignTokens.neutralGray500
                : iOSDesignTokens.neutralGray400,
          ),
          dropdownColor: iOSDesignTokens.neutralWhite,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          selectedItemBuilder: (context) {
            return assignableRoles.map((role) {
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: role.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    role.displayName,
                    style: iOSDesignTokens.bodyLarge.copyWith(
                      color: iOSDesignTokens.neutralGray900,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        );
      },
    );
  }

  Widget _buildRoleItem(AppRole role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Role color indicator
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: role.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              role.icon,
              color: role.color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  role.displayName,
                  style: iOSDesignTokens.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: iOSDesignTokens.neutralGray900,
                  ),
                ),
                if (showDescriptions) ...[
                  const SizedBox(height: 2),
                  Text(
                    role.description,
                    style: iOSDesignTokens.labelSmall.copyWith(
                      color: iOSDesignTokens.neutralGray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Level indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: iOSDesignTokens.neutralGray100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'L${role.level}',
              style: iOSDesignTokens.labelSmall.copyWith(
                color: iOSDesignTokens.neutralGray600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRolesAvailable() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iOSDesignTokens.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: iOSDesignTokens.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: iOSDesignTokens.warning,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No roles available to assign. You can only assign roles below your own level.',
              style: iOSDesignTokens.bodySmall.copyWith(
                color: iOSDesignTokens.neutralGray700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// RoleRadioGroup - Radio button group for role selection
///
/// Alternative to dropdown for when you want all options visible.
class RoleRadioGroup extends StatelessWidget {
  final String? selectedRole;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const RoleRadioGroup({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PermissionProvider>(
      builder: (context, permissionProvider, _) {
        final assignableRoles = permissionProvider.assignableRoles;

        if (assignableRoles.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iOSDesignTokens.neutralGray100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No roles available to assign',
              style: iOSDesignTokens.bodyMedium.copyWith(
                color: iOSDesignTokens.neutralGray600,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: assignableRoles.map((role) {
            final isSelected = selectedRole == role.name;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? () => onChanged(role.name) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? role.backgroundColor
                          : iOSDesignTokens.neutralWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? role.color
                            : iOSDesignTokens.neutralGray200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: role.backgroundColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            role.icon,
                            color: role.color,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role.displayName,
                                style: iOSDesignTokens.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: iOSDesignTokens.neutralGray900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                role.description,
                                style: iOSDesignTokens.labelSmall.copyWith(
                                  color: iOSDesignTokens.neutralGray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: role.color,
                            size: 24,
                          )
                        else
                          Icon(
                            CupertinoIcons.circle,
                            color: iOSDesignTokens.neutralGray400,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
