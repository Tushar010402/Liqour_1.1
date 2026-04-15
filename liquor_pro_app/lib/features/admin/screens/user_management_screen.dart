import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/widgets/smart_phone_input.dart';
import '../../../core/widgets/smart_email_input.dart';
import '../../../core/utils/image_picker_helper.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../providers/user_management_provider.dart';
import '../models/user_management_models.dart';
import '../services/user_management_service.dart';
import '../services/shop_service.dart';
import '../../finance/services/cash_service.dart';
import '../widgets/set_balance_sheet.dart';
// Permission system imports (keeping the permission logic)
import '../../../core/permissions/providers/permission_provider.dart';
import '../../../core/permissions/models/role_permission_model.dart';
import '../../../core/permissions/widgets/role_dropdown_widget.dart';

/// User Management Screen - For admins to manage users
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  UserManagementProvider? _userProvider;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Add listener for debounced search
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prevent multiple initializations
    if (!_isInitialized) {
      _isInitialized = true;
      _userProvider = Provider.of<UserManagementProvider>(context, listen: false);

      // Load data after build is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialData();
      });
    }
  }

  /// Debounced search handler - waits 500ms after user stops typing
  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _userProvider?.setSearchQuery(_searchController.text);
      }
    });
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      // Load users with timeout protection
      await _userProvider?.loadUsers().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Request timed out. Please check your connection.'),
                backgroundColor: AppColors.error,
                duration: Duration(seconds: 5),
              ),
            );
          }
          throw TimeoutException('Load users timed out');
        },
      );

      // Load stats with timeout protection
      await _userProvider?.loadStats().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('⚠️ [UserManagement] Stats load timed out');
        },
      );
    } on TimeoutException catch (e) {
      debugPrint('❌ [UserManagement] Timeout error: $e');
      // Timeout already handled above
    } catch (e, stackTrace) {
      debugPrint('❌ [UserManagement] Error loading data: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load users: ${e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadInitialData,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Clean up resources to prevent memory leaks
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    debugPrint('🧹 [UserManagement] Screen disposed - resources cleaned up');
    super.dispose();
  }

  void _showAddUserDialog() {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final salaryController = TextEditingController();
    String selectedRole = UserRole.manager;
    bool isActive = true;
    bool isCreating = false;
    String fullPhoneNumber = ''; // Store full phone number with country code
    String? selectedShopId; // Shop selection for salesman
    String? certificateImagePath; // Certificate image for salesman
    List<dynamic> shops = []; // Available shops
    bool isLoadingShops = true;

    // ✅ GlobalKey to preserve SmartPhoneInput state across dialog rebuilds
    final phoneInputKey = GlobalKey<State<SmartPhoneInput>>();
    final emailInputKey = GlobalKey<State<SmartEmailInput>>();

    // Real-time validation state
    String? emailError;
    String? firstNameError;
    String? lastNameError;
    bool emailValid = false;
    bool firstNameValid = false;
    bool lastNameValid = false;

    // Real-time validation methods
    void validateEmail(String value, Function setState) {
      setState(() {
        if (value.isEmpty) {
          emailError = null;
          emailValid = false;
        } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          emailError = '✗ Invalid email format';
          emailValid = false;
        } else {
          emailError = null;
          emailValid = true;
        }
      });
    }

    void validateFirstName(String value, Function setState) {
      setState(() {
        if (value.isEmpty) {
          firstNameError = null;
          firstNameValid = false;
        } else if (value.length < 2) {
          firstNameError = '✗ At least 2 characters required';
          firstNameValid = false;
        } else {
          firstNameError = null;
          firstNameValid = true;
        }
      });
    }

    void validateLastName(String value, Function setState) {
      setState(() {
        if (value.isEmpty) {
          lastNameError = null;
          lastNameValid = false;
        } else if (value.length < 2) {
          lastNameError = '✗ At least 2 characters required';
          lastNameValid = false;
        } else {
          lastNameError = null;
          lastNameValid = true;
        }
      });
    }

    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add User',
                        style: AppTextStyles.h4.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: isCreating ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: cs.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Users will login with Phone + OTP',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      SmartPhoneInput(
                        key: phoneInputKey, // ✅ Preserve state across rebuilds
                        controller: phoneController,
                        label: 'Phone Number (Required)',
                        hint: 'Enter phone number',
                        defaultCountryCode: '+91',
                        onChanged: (value) {
                          // Store full phone number with country code (NO setState needed)
                          fullPhoneNumber = value;

                          // Auto-generate username and password from phone
                          // Append short timestamp to avoid collision with soft-deleted users
                          final phone = PhoneValidator.clean(value).replaceAll('+', '');
                          if (phone.length >= 10) {
                            final ts = DateTime.now().millisecondsSinceEpoch % 100000;
                            usernameController.text = 'user${phone}_$ts';
                            passwordController.text = 'Pass@${phone.substring(phone.length - 8)}';
                          }
                        },
                        // Real-time validation
                        onValidate: (phoneNumber) async {
                          try {
                            debugPrint('🔍 [UserManagement] Starting validation for: $phoneNumber');

                            // Create service instance
                            final apiService = Provider.of<DioApiService>(context, listen: false);
                            final userService = UserManagementService(apiService);

                            // Call validation API
                            debugPrint('🔍 [UserManagement] Calling API service...');
                            final validationResponse = await userService.validatePhoneAvailability(phoneNumber);

                            debugPrint('🔍 [UserManagement] API response: available=${validationResponse.available}, message=${validationResponse.message}');

                            // Convert to ValidationResult for SmartPhoneInput
                            return ValidationResult(
                              isAvailable: validationResponse.available,
                              message: validationResponse.message,
                              needsTransfer: validationResponse.needsTransfer,
                              existingName: validationResponse.existingName,
                              existingRole: validationResponse.existingRole,
                              existingTenant: validationResponse.existingTenant,
                            );
                          } catch (e) {
                            debugPrint('❌ [UserManagement] Validation error: $e');
                            return ValidationResult(
                              isAvailable: false,
                              message: 'Error checking availability',
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Personal Information',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomTextField(
                                  label: 'First Name (Required)',
                                  controller: firstNameController,
                                  prefixIcon: const Icon(Icons.person),
                                  suffixIcon: firstNameValid
                                      ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                                      : null,
                                  onChanged: (value) => validateFirstName(value, dialogSetState),
                                ),
                                if (firstNameError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, left: 12),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            firstNameError!,
                                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomTextField(
                                  label: 'Last Name (Required)',
                                  controller: lastNameController,
                                  prefixIcon: const Icon(Icons.person_outline),
                                  suffixIcon: lastNameValid
                                      ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                                      : null,
                                  onChanged: (value) => validateLastName(value, dialogSetState),
                                ),
                                if (lastNameError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, left: 12),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            lastNameError!,
                                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SmartEmailInput(
                        key: emailInputKey, // ✅ Preserve state across rebuilds
                        controller: emailController,
                        label: 'Email (Optional)',  // ✅ NOW OPTIONAL
                        hint: 'Enter email address (optional)',
                        // Real-time validation - only validate if not empty
                        onValidate: (email) async {
                          // Skip validation if empty (optional field)
                          if (email.trim().isEmpty) {
                            return EmailValidationResult(
                              isValid: true,
                              isAvailable: true,
                              message: 'Email is optional',
                            );
                          }

                          // Create service instance
                          final apiService = Provider.of<DioApiService>(context, listen: false);
                          final userService = UserManagementService(apiService);

                          // Call validation API
                          final validationResponse = await userService.validateEmailAvailability(email);

                          // Convert to EmailValidationResult for SmartEmailInput
                          return EmailValidationResult(
                            isValid: EmailValidator.isValidFormat(email),
                            isAvailable: validationResponse.available,
                            message: validationResponse.message,
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Role & Status',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Auto-filtered role dropdown based on current user's permission level
                      Consumer<PermissionProvider>(
                        builder: (context, permissions, _) {
                          return RoleDropdownWidget(
                            selectedRole: selectedRole,
                            onChanged: (String? roleName) {
                              if (roleName != null) {
                                dialogSetState(() {
                                  selectedRole = roleName;
                                  // Load shops when salesman role is selected
                                  if (roleName == UserRole.salesman && shops.isEmpty) {
                                    _loadShopsForDialog(dialogSetState, (loadedShops) {
                                      shops = loadedShops;
                                      isLoadingShops = false;
                                    });
                                  }
                                });
                              }
                            },
                            label: 'Role',
                            hint: 'Select user role',
                            showDescriptions: true,
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Conditional fields for Salesman role
                      if (selectedRole == UserRole.salesman) ...[
                        Text(
                          'Salesman Details',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Shop Selector
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: isLoadingShops
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 12),
                                      Text('Loading shops...'),
                                    ],
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue: selectedShopId,
                                  decoration: const InputDecoration(
                                    labelText: 'Shop (Required)',
                                    prefixIcon: Icon(Icons.store),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  hint: const Text('Select a shop'),
                                  items: shops.map((shop) {
                                    return DropdownMenuItem<String>(
                                      value: shop['id'],
                                      child: Text(shop['name'] ?? 'Unknown Shop'),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    dialogSetState(() => selectedShopId = value);
                                  },
                                ),
                        ),
                        const SizedBox(height: 16),

                        // Certificate Upload (Optional)
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: ListTile(
                            leading: Icon(Icons.file_upload, color: cs.primary),
                            title: Text(
                              certificateImagePath != null ? 'Certificate Selected' : 'Upload Certificate (Optional)',
                              style: AppTextStyles.bodyMedium,
                            ),
                            subtitle: certificateImagePath != null
                                ? Text(
                                    certificateImagePath!.split('/').last,
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                                  )
                                : const Text('Attach salesman certificate or ID'),
                            trailing: certificateImagePath != null
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      dialogSetState(() => certificateImagePath = null);
                                    },
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () async {
                              // Pick document (PDF or image)
                              final file = await ImagePickerHelper.pickDocument(context);

                              if (file != null) {
                                // Validate file size (max 5MB)
                                final fileSizeInBytes = await file.length();
                                final maxSizeBytes = 5 * 1024 * 1024; // 5MB

                                if (fileSizeInBytes > maxSizeBytes) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'File size exceeds 5MB limit. Selected file: ${(fileSizeInBytes / (1024 * 1024)).toStringAsFixed(2)}MB',
                                        ),
                                        backgroundColor: AppColors.error,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                // Update state with file path
                                dialogSetState(() {
                                  certificateImagePath = file.path;
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Certificate selected (${await ImagePickerHelper.getFileSizeFormatted(file)})',
                                      ),
                                      backgroundColor: AppColors.success,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Salary field for all roles
                      Text(
                        'Compensation (Optional)',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Monthly Salary',
                        controller: salaryController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        prefixIcon: const Icon(Icons.attach_money),
                        hint: 'Enter monthly salary (optional)',
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Account Status',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SwitchListTile(
                          title: const Text('Active'),
                          subtitle: const Text('User can login and access the system'),
                          value: isActive,
                          onChanged: (value) {
                            dialogSetState(() => isActive = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),

              // Bottom Action Bar
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                ),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isCreating ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: isCreating ? null : () async {
                          // Validate phone number first (required for phone+OTP login)
                          if (fullPhoneNumber.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Phone number is required for user login'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          // Validate phone format using PhoneValidator
                          if (!PhoneValidator.isValid(fullPhoneNumber)) {
                            final errorMsg = PhoneValidator.getErrorMessage(fullPhoneNumber);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMsg ?? 'Invalid phone number'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          // Ensure username and password were auto-generated
                          if (usernameController.text.trim().isEmpty || passwordController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Username and password should be auto-generated from phone number'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          // Validate other required fields (email is now optional)
                          if (firstNameController.text.trim().isEmpty ||
                              lastNameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please fill all required fields (First Name, Last Name)'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          // Validate email format ONLY if provided
                          if (emailController.text.trim().isNotEmpty &&
                              !EmailValidator.isValidFormat(emailController.text.trim())) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid email address or leave it empty'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          // Validate shop selection for salesman role
                          if (selectedRole == UserRole.salesman && selectedShopId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select a shop for the salesman'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          dialogSetState(() => isCreating = true);

                          // Parse salary if provided
                          double? salaryValue;
                          if (salaryController.text.trim().isNotEmpty) {
                            salaryValue = double.tryParse(salaryController.text.trim());
                            if (salaryValue == null) {
                              dialogSetState(() => isCreating = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid salary amount'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }
                          }

                          final request = CreateUserRequest(
                            username: usernameController.text.trim(),
                            email: emailController.text.trim().isEmpty ? "" : emailController.text.trim(),  // ✅ Send empty string if empty (backend workaround)
                            password: passwordController.text,
                            firstName: firstNameController.text.trim(),
                            lastName: lastNameController.text.trim(),
                            phone: fullPhoneNumber.trim().isEmpty ? null : fullPhoneNumber.trim(),
                            role: selectedRole,
                            isActive: isActive,
                            salary: salaryValue,
                            shopId: selectedShopId,
                            certificateImage: certificateImagePath,
                          );

                          try {
                            final success = await _userProvider!.createUser(request);

                            dialogSetState(() => isCreating = false);

                            if (success) {
                              Navigator.pop(context);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('User created successfully'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } else {
                              if (mounted) {
                                final messenger = ScaffoldMessenger.of(context);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(_userProvider?.errorMessage ?? 'Failed to create user'),
                                    backgroundColor: AppColors.error,
                                    duration: const Duration(seconds: 5),
                                    behavior: SnackBarBehavior.floating,
                                    action: SnackBarAction(
                                      label: 'OK',
                                      textColor: Colors.white,
                                      onPressed: () => messenger.hideCurrentSnackBar(),
                                    ),
                                  ),
                                );
                              }
                            }
                          } on PhoneConflictException catch (conflict) {
                            dialogSetState(() => isCreating = false);
                            if (!context.mounted) return;
                            // Show OTP transfer dialog
                            _showPhoneTransferDialog(context, request, conflict);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Add User'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: 'User Management',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _userProvider?.refreshUsers(),
          ),
        ],
      ),
      body: Consumer2<UserManagementProvider, PermissionProvider>(
        builder: (context, provider, permissions, child) {
          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    provider.setSearchQuery(value);
                  },
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', provider),
                      const SizedBox(width: 8),
                      _buildFilterChip('Admins', UserRole.admin, provider),
                      const SizedBox(width: 8),
                      _buildFilterChip('Managers', UserRole.manager, provider),
                      const SizedBox(width: 8),
                      _buildFilterChip('Executives', UserRole.executive, provider),
                      const SizedBox(width: 8),
                      _buildFilterChip('Salesman', UserRole.salesman, provider),
                      const SizedBox(width: 8),
                      _buildFilterChip('Asst. Managers', UserRole.assistantManager, provider),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Users Summary Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSummaryCard(provider),
              ),
              const SizedBox(height: 16),

              // Users List
              Expanded(
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.filteredUsers.isEmpty
                        ? EmptyStateWidget(
                            icon: Icons.people_outline,
                            title: 'No Users Found',
                            message: 'Add your first user to get started',
                          )
                        : RefreshIndicator(
                            onRefresh: () => provider.refreshUsers(),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: provider.filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = provider.filteredUsers[index];
                                return _buildUserCard(user, permissions);
                              },
                            ),
                          ),
              ),
            ],
          );
        },
      ),
      // Permission-gated FAB
      floatingActionButton: Consumer<PermissionProvider>(
        builder: (context, permissions, _) {
          if (!permissions.canManageUsers) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            onPressed: _showAddUserDialog,
            backgroundColor: cs.primary,
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text(
              'Add User',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }

  /// Build filter chip widget
  Widget _buildFilterChip(String label, String value, UserManagementProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = provider.roleFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => provider.setRoleFilter(value),
      selectedColor: cs.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : cs.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
        ),
      ),
    );
  }

  /// Build summary card widget
  Widget _buildSummaryCard(UserManagementProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryItem(
              'Total',
              '${provider.stats['total'] ?? 0}',
              Icons.people,
              cs.primary,
            ),
            _buildSummaryItem(
              'Active',
              '${provider.stats['active'] ?? 0}',
              Icons.check_circle,
              AppColors.success,
            ),
            _buildSummaryItem(
              'Inactive',
              '${provider.stats['inactive'] ?? 0}',
              Icons.cancel,
              AppColors.error,
            ),
          ],
        ),
      ),
    );
  }

  /// Build summary item widget
  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.h4.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Build user card widget
  Widget _buildUserCard(UserItem user, PermissionProvider permissions) {
    final cs = Theme.of(context).colorScheme;
    final role = AppRole.fromName(user.role);
    final canManage = permissions.canManageUser(role);
    final canDelete = permissions.canDeleteUser(role);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => _showUserDetailSheet(user),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: _getRoleColor(user.role).withValues(alpha: 0.2),
                child: Text(
                  user.initials,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: _getRoleColor(user.role),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.displayName,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: user.isActive
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            user.isActive ? 'Active' : 'Inactive',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: user.isActive ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getRoleColor(user.role).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatRoleName(user.role),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: _getRoleColor(user.role),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Show shop name for salesman
                        if (user.role == UserRole.salesman && user.shopName != null && user.shopName!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.store, size: 12, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              user.shopName!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showEditUserDialog(user);
                        break;
                      case 'toggle':
                        _toggleUserStatus(user);
                        break;
                      case 'delete':
                        if (canDelete) _showDeleteUserConfirmation(user);
                        break;
                      case 'set_balance':
                        _showSetBalanceSheet(user);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            user.isActive ? Icons.block : Icons.check_circle,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(user.isActive ? 'Deactivate' : 'Activate'),
                        ],
                      ),
                    ),
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    // Admin-only: Set Cash Balance
                    if (permissions.isAdmin)
                      const PopupMenuItem(
                        value: 'set_balance',
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.deepPurple),
                            SizedBox(width: 8),
                            Text('Set Cash Balance', style: TextStyle(color: Colors.deepPurple)),
                          ],
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

  /// Get color for role
  Color _getRoleColor(String role) {
    switch (role) {
      case UserRole.admin:
        return Colors.purple;
      case UserRole.manager:
        return Colors.blue;
      case UserRole.assistantManager:
        return Colors.teal;
      case UserRole.executive:
        return Colors.orange;
      case UserRole.salesman:
        return Colors.green;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  /// Format role name for display
  String _formatRoleName(String role) {
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  /// Show user detail bottom sheet
  void _showUserDetailSheet(UserItem user) {
    final role = AppRole.fromName(user.role);
    final permissions = context.read<PermissionProvider>();
    final canManage = permissions.canManageUser(role);
    final canDelete = permissions.canDeleteUser(role);

    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with avatar and name
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: _getRoleColor(user.role).withValues(alpha: 0.2),
                    child: Text(
                      user.initials,
                      style: AppTextStyles.h4.copyWith(
                        color: _getRoleColor(user.role),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.displayName,
                                style: AppTextStyles.h4.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: user.isActive
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                user.isActive ? 'Active' : 'Inactive',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: user.isActive ? AppColors.success : AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getRoleColor(user.role).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatRoleName(user.role),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: _getRoleColor(user.role),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // User details
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildDetailRow(Icons.email_outlined, 'Email', user.email),
                    if (user.phone != null)
                      _buildDetailRow(Icons.phone_outlined, 'Phone', user.phone!),
                    // Show shop for salesman
                    if (user.role == UserRole.salesman && user.shopName != null && user.shopName!.isNotEmpty)
                      _buildDetailRow(Icons.store_outlined, 'Shop', user.shopName!),
                    _buildDetailRow(Icons.person_outline, 'Username', user.username),
                    _buildDetailRow(
                      Icons.calendar_today_outlined,
                      'Created',
                      user.createdAt != null
                          ? _formatDate(user.createdAt!)
                          : 'Unknown',
                    ),
                  ],
                ),
              ),
            ),
            // Action buttons
            if (canManage)
              Container(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditUserDialog(user);
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (canDelete) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteUserConfirmation(user);
                          },
                          icon: const Icon(Icons.delete, size: 18),
                          label: const Text('Delete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
    );
  }

  /// Build detail row for user detail sheet
  Widget _buildDetailRow(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showEditUserDialog(UserItem user) {
    final cs = Theme.of(context).colorScheme;
    debugPrint('📝 [EditUserDialog] Opening for user: ${user.firstName} ${user.lastName}');
    debugPrint('   User ID: ${user.id}');
    debugPrint('   User Phone (raw): "${user.phone}"');
    debugPrint('   User ShopId: "${user.shopId}"');
    debugPrint('   User ShopName: "${user.shopName}"');

    // Parse existing phone number to extract country code and local number
    String detectedCountryCode = '+91'; // Default
    String localPhoneNumber = '';

    if (user.phone != null && user.phone!.isNotEmpty) {
      final phone = user.phone!.trim(); // Trim any whitespace
      debugPrint('   Parsing phone: "$phone" (length: ${phone.length})');

      // Check for known country codes - handle with/without spaces
      final cleanPhone = phone.replaceAll(' ', ''); // Remove spaces for checking
      debugPrint('   Clean phone (no spaces): "$cleanPhone" (length: ${cleanPhone.length})');

      if (cleanPhone.startsWith('+91') && cleanPhone.length >= 13) {
        detectedCountryCode = '+91';
        localPhoneNumber = cleanPhone.substring(3); // Remove +91
        debugPrint('   Detected +91 (India): localPhone = "$localPhoneNumber"');
      } else if (cleanPhone.startsWith('+1') && cleanPhone.length >= 12) {
        detectedCountryCode = '+1';
        localPhoneNumber = cleanPhone.substring(2); // Remove +1
        debugPrint('   Detected +1 (USA/Canada): localPhone = "$localPhoneNumber"');
      } else if (cleanPhone.startsWith('+44') && cleanPhone.length >= 13) {
        detectedCountryCode = '+44';
        localPhoneNumber = cleanPhone.substring(3); // Remove +44
        debugPrint('   Detected +44 (UK): localPhone = "$localPhoneNumber"');
      } else if (cleanPhone.startsWith('+86') && cleanPhone.length >= 14) {
        detectedCountryCode = '+86';
        localPhoneNumber = cleanPhone.substring(3); // Remove +86
        debugPrint('   Detected +86 (China): localPhone = "$localPhoneNumber"');
      } else if (cleanPhone.startsWith('+')) {
        // Unknown country code, try to extract last 10 digits
        final digitsOnly = cleanPhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly.length >= 10) {
          localPhoneNumber = digitsOnly.substring(digitsOnly.length - 10);
        }
        debugPrint('   Unknown country code - extracted last 10 digits: "$localPhoneNumber"');
      } else {
        // No country code prefix, use as is (just digits)
        localPhoneNumber = cleanPhone.replaceAll(RegExp(r'[^0-9]'), '');
        debugPrint('   No country code prefix - using digits: "$localPhoneNumber"');
      }
    } else {
      debugPrint('   ⚠️ user.phone is null or empty!');
    }

    debugPrint('   FINAL: detectedCountryCode = "$detectedCountryCode"');
    debugPrint('   FINAL: localPhoneNumber = "$localPhoneNumber"');

    // Controllers - Use localPhoneNumber (without country code) for SmartPhoneInput
    final firstNameController = TextEditingController(text: user.firstName);
    final lastNameController = TextEditingController(text: user.lastName);
    final emailController = TextEditingController(text: user.email);
    final phoneController = TextEditingController(text: localPhoneNumber);
    final salaryController = TextEditingController(text: user.salary?.toString() ?? '');

    // State variables
    bool isUpdating = false;
    bool isActive = user.isActive;
    String selectedRole = user.role;
    String? profileImagePath;
    String? certificateImagePath;
    String fullPhoneNumber = user.phone ?? '';
    String? selectedShopId = user.shopId;
    List<dynamic> shops = [];
    bool isLoadingShops = false;
    bool shopsLoadedOnce = false; // Track if we've tried to load shops

    // GlobalKeys to preserve state across rebuilds
    final phoneInputKey = GlobalKey<State<SmartPhoneInput>>();
    final emailInputKey = GlobalKey<State<SmartEmailInput>>();

    // Real-time validation state
    String? firstNameError;
    String? lastNameError;
    bool firstNameValid = user.firstName.length >= 2;
    bool lastNameValid = user.lastName.length >= 2;

    // Real-time validation methods
    void validateFirstName(String value, Function setState) {
      setState(() {
        if (value.isEmpty) {
          firstNameError = null;
          firstNameValid = false;
        } else if (value.length < 2) {
          firstNameError = '✗ At least 2 characters required';
          firstNameValid = false;
        } else {
          firstNameError = null;
          firstNameValid = true;
        }
      });
    }

    void validateLastName(String value, Function setState) {
      setState(() {
        if (value.isEmpty) {
          lastNameError = null;
          lastNameValid = false;
        } else if (value.length < 2) {
          lastNameError = '✗ At least 2 characters required';
          lastNameValid = false;
        } else {
          lastNameError = null;
          lastNameValid = true;
        }
      });
    }

    // Helper to dismiss keyboard
    void dismissKeyboard(BuildContext ctx) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    // Load shops for salesman role
    Future<void> loadShops(StateSetter dialogSetState) async {
      if (shops.isNotEmpty) return;

      dialogSetState(() => isLoadingShops = true);

      try {
        final shopService = ShopService(Provider.of<DioApiService>(context, listen: false));
        final response = await shopService.getShops();

        if (response.isSuccess && response.data != null) {
          final List<dynamic> shopsData = response.data!.map((shop) {
            return {'id': shop.id, 'name': shop.name};
          }).toList();

          // Debug: Log shop matching
          debugPrint('🏪 SHOP MATCHING DEBUG:');
          debugPrint('   User selectedShopId: "$selectedShopId"');
          debugPrint('   Available shops: ${shopsData.map((s) => '${s['id']} (${s['name']})').join(', ')}');

          // Check if selectedShopId exists in shops list
          final matchingShop = shopsData.where((s) => s['id'] == selectedShopId).toList();
          debugPrint('   Match found: ${matchingShop.isNotEmpty ? matchingShop.first['name'] : 'NO MATCH'}');

          // CRITICAL: After setting shops, the dropdown will be rebuilt with the new key
          // The value will be: shops.any() ? selectedShopId : null
          final willHaveValue = shopsData.any((s) => s['id'] == selectedShopId);
          debugPrint('   ✅ Dropdown value will be: ${willHaveValue ? selectedShopId : 'null'}');
          debugPrint('   ✅ Dropdown key will be: shop_dropdown_${shopsData.length}_$selectedShopId');

          dialogSetState(() {
            shops = shopsData;
            isLoadingShops = false;
          });

          debugPrint('   ✅ dialogSetState called - dropdown should rebuild now');
        } else {
          dialogSetState(() => isLoadingShops = false);
        }
      } catch (e) {
        debugPrint('❌ Error loading shops: $e');
        dialogSetState(() => isLoadingShops = false);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

          // Load shops immediately if user has shopId OR when salesman role is selected
          // This ensures the shop dropdown shows existing value correctly
          if (!shopsLoadedOnce && !isLoadingShops &&
              (selectedRole == UserRole.salesman || user.shopId != null)) {
            shopsLoadedOnce = true;
            loadShops(dialogSetState);
          }

          return GestureDetector(
            onTap: () => dismissKeyboard(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header with Avatar
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        // User Avatar with edit capability
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: _getRoleColor(selectedRole).withValues(alpha: 0.2),
                              backgroundImage: profileImagePath != null
                                  ? FileImage(File(profileImagePath!))
                                  : null,
                              child: profileImagePath == null
                                  ? Text(
                                      user.initials,
                                      style: AppTextStyles.h4.copyWith(
                                        color: _getRoleColor(selectedRole),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  dismissKeyboard(context);
                                  final file = await ImagePickerHelper.pickProfilePicture(context);
                                  if (file != null) {
                                    dialogSetState(() => profileImagePath = file.path);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit User',
                                style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              // Live display of full name
                              Text(
                                '${firstNameController.text} ${lastNameController.text}'.trim().isEmpty
                                    ? 'Enter name below'
                                    : '${firstNameController.text} ${lastNameController.text}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: isUpdating ? null : () {
                            dismissKeyboard(context);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Form Content
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification) {
                          dismissKeyboard(context);
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info banner
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: cs.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Users login with Phone + OTP. Username cannot be changed.',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Phone Number Section
                            SmartPhoneInput(
                              key: phoneInputKey,
                              controller: phoneController,
                              label: 'Phone Number (Required)',
                              hint: 'Enter phone number',
                              defaultCountryCode: detectedCountryCode, // Use detected country code from user's existing phone
                              onChanged: (value) {
                                fullPhoneNumber = value;
                              },
                              onValidate: (phoneNumber) async {
                                // Skip validation if same as current
                                if (phoneNumber == user.phone) {
                                  return const ValidationResult(
                                    isAvailable: true,
                                    message: 'Current phone number',
                                  );
                                }

                                try {
                                  final apiService = Provider.of<DioApiService>(context, listen: false);
                                  final userService = UserManagementService(apiService);
                                  final validationResponse = await userService.validatePhoneAvailability(phoneNumber);

                                  return ValidationResult(
                                    isAvailable: validationResponse.available,
                                    message: validationResponse.message,
                                    needsTransfer: validationResponse.needsTransfer,
                                    existingName: validationResponse.existingName,
                                    existingRole: validationResponse.existingRole,
                                    existingTenant: validationResponse.existingTenant,
                                  );
                                } catch (e) {
                                  return ValidationResult(
                                    isAvailable: false,
                                    message: 'Error checking availability',
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 24),

                            // Personal Information Section
                            Text(
                              'Personal Information',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // First Name & Last Name Row
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CustomTextField(
                                        label: 'First Name (Required)',
                                        controller: firstNameController,
                                        prefixIcon: const Icon(Icons.person),
                                        suffixIcon: firstNameValid
                                            ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                                            : null,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (value) => validateFirstName(value, dialogSetState),
                                      ),
                                      if (firstNameError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4, left: 12),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  firstNameError!,
                                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CustomTextField(
                                        label: 'Last Name (Required)',
                                        controller: lastNameController,
                                        prefixIcon: const Icon(Icons.person_outline),
                                        suffixIcon: lastNameValid
                                            ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                                            : null,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (value) => validateLastName(value, dialogSetState),
                                      ),
                                      if (lastNameError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4, left: 12),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  lastNameError!,
                                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Email (Editable)
                            SmartEmailInput(
                              key: emailInputKey,
                              controller: emailController,
                              label: 'Email (Optional)',
                              hint: 'Enter email address (optional)',
                              onValidate: (email) async {
                                // Skip validation if empty (optional) or same as current
                                if (email.trim().isEmpty) {
                                  return EmailValidationResult(
                                    isValid: true,
                                    isAvailable: true,
                                    message: 'Email is optional',
                                  );
                                }

                                if (email == user.email) {
                                  return EmailValidationResult(
                                    isValid: true,
                                    isAvailable: true,
                                    message: 'Current email',
                                  );
                                }

                                try {
                                  final apiService = Provider.of<DioApiService>(context, listen: false);
                                  final userService = UserManagementService(apiService);
                                  final validationResponse = await userService.validateEmailAvailability(email);

                                  return EmailValidationResult(
                                    isValid: EmailValidator.isValidFormat(email),
                                    isAvailable: validationResponse.available,
                                    message: validationResponse.message,
                                  );
                                } catch (e) {
                                  return EmailValidationResult(
                                    isValid: false,
                                    isAvailable: false,
                                    message: 'Error checking availability',
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 24),

                            // Role & Status Section
                            Text(
                              'Role & Status',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Role Dropdown
                            Consumer<PermissionProvider>(
                              builder: (context, permissions, _) {
                                return RoleDropdownWidget(
                                  selectedRole: selectedRole,
                                  onChanged: (String? roleName) {
                                    if (roleName != null) {
                                      dismissKeyboard(context);
                                      dialogSetState(() {
                                        selectedRole = roleName;
                                        // Load shops when salesman role is selected
                                        if (roleName == UserRole.salesman && shops.isEmpty) {
                                          loadShops(dialogSetState);
                                        }
                                      });
                                    }
                                  },
                                  label: 'Role',
                                  hint: 'Select user role',
                                  showDescriptions: true,
                                );
                              },
                            ),
                            const SizedBox(height: 20),

                            // Salesman-specific fields
                            if (selectedRole == UserRole.salesman) ...[
                              Text(
                                'Salesman Details',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Shop Selector
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: cs.outlineVariant),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: isLoadingShops
                                    ? const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                            SizedBox(width: 12),
                                            Text('Loading shops...'),
                                          ],
                                        ),
                                      )
                                    : DropdownButtonFormField<String>(
                                        // CRITICAL FIX: Add key to force rebuild when shops load
                                        // This ensures the dropdown updates when shops become available
                                        key: ValueKey('shop_dropdown_${shops.length}_$selectedShopId'),
                                        // Only set value if it exists in items list
                                        // Flutter requires value to be in items, otherwise it shows hint
                                        initialValue: shops.any((s) => s['id'] == selectedShopId) ? selectedShopId : null,
                                        decoration: const InputDecoration(
                                          labelText: 'Shop (Required)',
                                          prefixIcon: Icon(Icons.store),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        ),
                                        hint: Text(
                                          selectedShopId != null && shops.isEmpty
                                              ? 'Loading...'
                                              : 'Select a shop',
                                        ),
                                        items: shops.map((shop) {
                                          return DropdownMenuItem<String>(
                                            value: shop['id'],
                                            child: Text(shop['name'] ?? 'Unknown Shop'),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          dismissKeyboard(context);
                                          dialogSetState(() => selectedShopId = value);
                                        },
                                      ),
                              ),
                              const SizedBox(height: 16),

                              // Certificate Upload
                              Container(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: ListTile(
                                  leading: Icon(Icons.file_upload, color: cs.primary),
                                  title: Text(
                                    certificateImagePath != null ? 'Certificate Selected' : 'Upload Certificate (Optional)',
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                  subtitle: certificateImagePath != null
                                      ? Text(
                                          certificateImagePath!.split('/').last,
                                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                                        )
                                      : const Text('Attach salesman certificate or ID'),
                                  trailing: certificateImagePath != null
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 20),
                                          onPressed: () => dialogSetState(() => certificateImagePath = null),
                                        )
                                      : const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    dismissKeyboard(context);
                                    final file = await ImagePickerHelper.pickDocument(context);
                                    if (file != null) {
                                      final fileSizeInBytes = await file.length();
                                      final maxSizeBytes = 5 * 1024 * 1024; // 5MB

                                      if (fileSizeInBytes > maxSizeBytes) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'File size exceeds 5MB limit. Selected: ${(fileSizeInBytes / (1024 * 1024)).toStringAsFixed(2)}MB',
                                              ),
                                              backgroundColor: AppColors.error,
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      dialogSetState(() => certificateImagePath = file.path);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Compensation Section
                            Text(
                              'Compensation (Optional)',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              label: 'Monthly Salary',
                              controller: salaryController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              prefixIcon: const Icon(Icons.attach_money),
                              hint: 'Enter monthly salary (optional)',
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => dismissKeyboard(context),
                            ),
                            const SizedBox(height: 24),

                            // Account Status Section
                            Text(
                              'Account Status',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.success.withValues(alpha: 0.05)
                                    : AppColors.error.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.success.withValues(alpha: 0.3)
                                      : AppColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: SwitchListTile(
                                title: Text(
                                  isActive ? 'Active' : 'Inactive',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isActive ? AppColors.success : AppColors.error,
                                  ),
                                ),
                                subtitle: Text(
                                  isActive
                                      ? 'User can login and access the system'
                                      : 'User cannot login to the system',
                                  style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
                                ),
                                value: isActive,
                                activeThumbColor: AppColors.success,
                                onChanged: (value) {
                                  dismissKeyboard(context);
                                  dialogSetState(() => isActive = value);
                                },
                                secondary: Icon(
                                  isActive ? Icons.check_circle : Icons.cancel,
                                  color: isActive ? AppColors.success : AppColors.error,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Read-only Account Information
                            Text(
                              'Account Information (Read-only)',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _buildReadOnlyField('Username', user.username, Icons.account_circle_outlined),
                                  const SizedBox(height: 12),
                                  _buildReadOnlyField('User ID', '${user.id.substring(0, 8)}...', Icons.tag_outlined),
                                  if (user.createdAt != null) ...[
                                    const SizedBox(height: 12),
                                    _buildReadOnlyField('Created', _formatDate(user.createdAt!), Icons.calendar_today_outlined),
                                  ],
                                ],
                              ),
                            ),

                            // Keyboard dismiss hint
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Tap outside or scroll to dismiss keyboard',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Extra space for bottom bar
                            SizedBox(height: keyboardHeight > 0 ? keyboardHeight + 20 : 100),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom Action Bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                    ),
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: keyboardHeight > 0 ? 16 : MediaQuery.of(context).padding.bottom + 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isUpdating ? null : () {
                              dismissKeyboard(context);
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: isUpdating ? null : () async {
                              dismissKeyboard(context);

                              // Validate required fields
                              if (firstNameController.text.trim().isEmpty ||
                                  lastNameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please fill First Name and Last Name'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }

                              // Validate phone if changed
                              if (fullPhoneNumber.isNotEmpty && !PhoneValidator.isValid(fullPhoneNumber)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(PhoneValidator.getErrorMessage(fullPhoneNumber) ?? 'Invalid phone'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }

                              // Validate email format if provided
                              if (emailController.text.trim().isNotEmpty &&
                                  !EmailValidator.isValidFormat(emailController.text.trim())) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a valid email or leave it empty'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }

                              // Validate shop for salesman
                              if (selectedRole == UserRole.salesman && selectedShopId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please select a shop for the salesman'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                                return;
                              }

                              dialogSetState(() => isUpdating = true);

                              // Parse salary
                              double? salaryValue;
                              if (salaryController.text.trim().isNotEmpty) {
                                salaryValue = double.tryParse(salaryController.text.trim());
                                if (salaryValue == null) {
                                  dialogSetState(() => isUpdating = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter a valid salary amount'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }
                              }

                              final request = UpdateUserRequest(
                                firstName: firstNameController.text.trim(),
                                lastName: lastNameController.text.trim(),
                                email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                                phone: fullPhoneNumber.trim().isEmpty ? null : fullPhoneNumber.trim(),
                                role: selectedRole,
                                isActive: isActive,
                                salary: salaryValue,
                                shopId: selectedShopId,
                                profileImage: profileImagePath,
                                certificateImage: certificateImagePath,
                              );

                              final success = await _userProvider!.updateUser(user.id, request);

                              dialogSetState(() => isUpdating = false);

                              if (success) {
                                Navigator.pop(context);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('User updated successfully'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_userProvider?.errorMessage ?? 'Failed to update user'),
                                      backgroundColor: AppColors.error,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isUpdating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text('Update User'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleUserStatus(UserItem user) async {
    final success = await _userProvider!.toggleUserStatus(user.id, user.isActive);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${user.isActive ? 'deactivated' : 'activated'} successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_userProvider?.errorMessage ?? 'Failed to update user status'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showDeleteUserConfirmation(UserItem user) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Delete User',
                    style: AppTextStyles.h4.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Are you sure you want to delete ${user.firstName} ${user.lastName}?',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);

                        final success = await _userProvider!.deleteUser(user.id);

                        if (success) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('User deleted successfully'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_userProvider?.errorMessage ?? 'Failed to delete user'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Delete User'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
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

  /// Show Set Balance bottom sheet (Admin only)
  void _showSetBalanceSheet(UserItem user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SetBalanceSheet(
        userId: user.id,
        userName: user.displayName,
        onConfirm: (newBalance, reason, notes) async {
          Navigator.pop(context);

          try {
            final cashService = CashService(Provider.of<DioApiService>(context, listen: false));
            final result = await cashService.adminSetBalance(
              userId: user.id,
              newBalance: newBalance,
              reason: reason,
              notes: notes,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.success
                    ? 'Balance updated: ₹${result.previousBalance.toStringAsFixed(0)} → ₹${result.newBalance.toStringAsFixed(0)}'
                    : result.message),
                  backgroundColor: result.success ? AppColors.success : AppColors.error,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${e.toString()}'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        },
      ),
    );
  }

  /// Helper method to load shops for dialog
  Future<void> _loadShopsForDialog(
    StateSetter dialogSetState,
    Function(List<dynamic>) onLoaded,
  ) async {
    try {
      // Use the shop service to fetch shops
      final shopService = ShopService(Provider.of<DioApiService>(context, listen: false));
      final response = await shopService.getShops();

      if (response.isSuccess && response.data != null) {
        final List<dynamic> shopsData = response.data!.map((shop) {
          return {
            'id': shop.id,
            'name': shop.name,
          };
        }).toList();

        dialogSetState(() {
          onLoaded(shopsData);
        });
      } else {
        dialogSetState(() {
          onLoaded([]);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Failed to load shops'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading shops: $e');
      dialogSetState(() {
        onLoaded([]);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading shops: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Shows OTP dialog for phone transfer when creating a user with an existing phone
  void _showPhoneTransferDialog(
    BuildContext parentContext,
    CreateUserRequest originalRequest,
    PhoneConflictException conflict,
  ) {
    final otpController = TextEditingController();
    String? sessionId;
    bool isSending = false;
    bool isVerifying = false;
    bool otpSent = false;
    String? errorText;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Phone Already Registered', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing user info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This phone is registered to:', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                        const SizedBox(height: 6),
                        if (conflict.existingUserName != null)
                          Text(conflict.existingUserName!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        if (conflict.existingUserRole != null)
                          Text('Role: ${conflict.existingUserRole}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (conflict.existingTenant != null)
                          Text('Tenant: ${conflict.existingTenant}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    otpSent
                      ? 'Enter the OTP sent to ${conflict.phone} to transfer this number to the new user.'
                      : 'Send an OTP to verify and transfer this phone number to your new user. The existing user will be deactivated.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  if (otpSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Enter 6-digit OTP',
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                if (!otpSent)
                  ElevatedButton.icon(
                    onPressed: isSending ? null : () async {
                      setState(() { isSending = true; errorText = null; });
                      try {
                        sessionId = await _userProvider!.sendPhoneTransferOTP(conflict.phone);
                        setState(() { otpSent = true; isSending = false; });
                      } catch (e) {
                        setState(() { isSending = false; errorText = e.toString(); });
                      }
                    },
                    icon: isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sms_outlined, size: 18),
                    label: Text(isSending ? 'Sending...' : 'Send OTP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                if (otpSent)
                  ElevatedButton.icon(
                    onPressed: isVerifying ? null : () async {
                      final otp = otpController.text.trim();
                      if (otp.length != 6) {
                        setState(() => errorText = 'Enter 6-digit OTP');
                        return;
                      }
                      setState(() { isVerifying = true; errorText = null; });
                      try {
                        final requestWithOtp = originalRequest.copyWithTransfer(
                          otp: otp,
                          sessionId: sessionId ?? '',
                        );
                        final success = await _userProvider!.createUser(requestWithOtp);
                        if (success && ctx.mounted) {
                          Navigator.pop(ctx); // close OTP dialog
                          Navigator.pop(parentContext); // close create user dialog
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('User created successfully (phone transferred)'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } else {
                          setState(() {
                            isVerifying = false;
                            errorText = _userProvider?.errorMessage ?? 'Failed to create user';
                          });
                        }
                      } on PhoneConflictException {
                        setState(() { isVerifying = false; errorText = 'Transfer failed. Try again.'; });
                      } catch (e) {
                        setState(() { isVerifying = false; errorText = e.toString(); });
                      }
                    },
                    icon: isVerifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(isVerifying ? 'Verifying...' : 'Verify & Transfer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
