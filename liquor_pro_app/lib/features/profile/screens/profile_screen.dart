import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'delete_account_screen.dart';

/// Profile Screen — pixel-matched to JSX Screen_Profile.
/// JSX: "View Profile" centered title, white card with gradient header + avatar,
/// name/role/shop, "Edit" button, Personal Details card with engagement score.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final user = context.read<AuthProvider>().currentUser;
    _firstNameController.text = user?.firstName ?? '';
    _lastNameController.text = user?.lastName ?? '';
    _emailController.text = user?.email ?? '';
    _phoneController.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isEditing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildProfileCard(),
            _buildPersonalDetailsCard(),
            _buildDangerZone(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// JSX: back button circle #0D47A1, centered "View Profile" title
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: Colors.white,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0D47A1),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            Expanded(
              child: Text(
                'View Profile',
                textAlign: TextAlign.center,
                style: AppTextStyles.h5.copyWith(
                  fontWeight: FontWeight.w900, fontSize: 19, color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
            const SizedBox(width: 38), // Balance back button
          ],
        ),
      ),
    );
  }

  /// JSX: white card radius 18, gradient header 135deg #1565C0 → #0D47A1 100px,
  /// avatar 90px grey #D5D5D5 overlapping, name #0D47A1 fontWeight 900,
  /// "Sales Man" subtitle, shop name, Edit button
  Widget _buildProfileCard() {
    return Consumer2<AuthProvider, ShopSelectionProvider>(
      builder: (context, auth, shop, _) {
        final user = auth.currentUser;
        final firstName = user?.firstName ?? '';
        final lastName = user?.lastName ?? '';
        final role = user?.role ?? 'User';
        final shopName = shop.selectedShopName ?? '';

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Gradient header with overlapping avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                        begin: Alignment(-1, -1),
                        end: Alignment(1, 1),
                      ),
                    ),
                  ),
                  // Avatar centered, overlapping bottom
                  Positioned(
                    bottom: -40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFD5D5D5),
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: const Icon(Icons.person, color: Color(0xFF999999), size: 48),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50), // Space for overlapping avatar

              // Name (JSX: fontSize 20, fontWeight 900, #0D47A1)
              Text(
                'Mr $firstName $lastName',
                style: AppTextStyles.h5.copyWith(
                  fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 4),
              // Role (JSX: fontSize 15, fontWeight 600, #555)
              Text(
                _formatRole(role),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 15, color: const Color(0xFF555555),
                ),
              ),
              // Shop (JSX: fontSize 13, fontWeight 500, #888)
              if (shopName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  shopName,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w500, fontSize: 13, color: const Color(0xFF888888),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Edit button (JSX: #0D47A1, radius 8, fontSize 15, fontWeight 800)
              _isEditing
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 60),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () { _loadUserData(); setState(() => _isEditing = false); },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _handleSave,
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () => setState(() => _isEditing = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 9),
                        elevation: 0,
                      ),
                      child: Text(
                        'Edit',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white,
                        ),
                      ),
                    ),
              const SizedBox(height: 22),
            ],
          ),
        );
      },
    );
  }

  /// JSX: white card radius 18, group icon #0D47A1 + "Personal Details" fontWeight 900,
  /// engagement score green pill #E8F5E9, info rows with bold label + value
  Widget _buildPersonalDetailsCard() {
    return Consumer2<AuthProvider, ShopSelectionProvider>(
      builder: (context, auth, shop, _) {
        final user = auth.currentUser;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.people_outlined, color: Color(0xFF0D47A1), size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Personal Details',
                      style: AppTextStyles.h5.copyWith(
                        fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Engagement Score (JSX: #E8F5E9 bg, radius 22, green text)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF2E7D32),
                      ),
                      children: [
                        const TextSpan(text: 'Engagement Score : '),
                        TextSpan(text: '5/10', style: TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Info rows or edit fields
                if (_isEditing) ...[
                  _buildEditField('First Name', _firstNameController),
                  const SizedBox(height: 12),
                  _buildEditField('Last Name', _lastNameController),
                  const SizedBox(height: 12),
                  _buildEditField('Email', _emailController, enabled: false),
                  const SizedBox(height: 12),
                  _buildEditField('Phone', _phoneController),
                ] else ...[
                  // JSX: each row has bold label fontSize 15 fontWeight 900, value #555 fontSize 14
                  _buildInfoRow('Email', user?.email ?? '-'),
                  _buildInfoRow('Mobile', user?.phone ?? '-'),
                  _buildInfoRow('Shop Name', shop.selectedShopName ?? '-'),
                  _buildInfoRow('Tag Line', 'Om Namah Shivaya'),
                  _buildInfoRow('Address', '-'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w500, fontSize: 14, color: const Color(0xFF555555),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFECEEF3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            hintText: 'Enter',
            hintStyle: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFFAAAAAA), fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildDangerZone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Danger Zone', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
          const SizedBox(height: 8),
          Text(
            'Once you delete your account, there is no going back.',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.red.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Delete Account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'salesman': return 'Sales Man';
      case 'assistant_manager': return 'Assistant Manager';
      default: return role[0].toUpperCase() + role.substring(1);
    }
  }
}
