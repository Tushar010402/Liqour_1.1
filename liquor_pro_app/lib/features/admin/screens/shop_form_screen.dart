import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/shop_model.dart';
import '../providers/shop_provider.dart';

/// Shop Form Screen - Create or Edit Shop
class ShopFormScreen extends StatefulWidget {
  final Shop? shop; // null for create, Shop object for edit

  const ShopFormScreen({
    super.key,
    this.shop,
  });

  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _isActive = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill form if editing
    if (widget.shop != null) {
      _nameController.text = widget.shop!.name;
      _addressController.text = widget.shop!.address;
      _phoneController.text = widget.shop!.phone;
      _licenseNumberController.text = widget.shop!.licenseNumber;
      _latitudeController.text = widget.shop!.latitude.toString();
      _longitudeController.text = widget.shop!.longitude.toString();
      _isActive = widget.shop!.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _licenseNumberController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  bool get isEditMode => widget.shop != null;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final shopProvider = context.read<ShopProvider>();

      // Parse latitude and longitude
      final latitude = double.tryParse(_latitudeController.text) ?? 0.0;
      final longitude = double.tryParse(_longitudeController.text) ?? 0.0;

      bool success;
      if (isEditMode) {
        // Update existing shop
        success = await shopProvider.updateShop(
          shopId: widget.shop!.id,
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          phone: _phoneController.text.trim(),
          licenseNumber: _licenseNumberController.text.trim(),
          latitude: latitude,
          longitude: longitude,
          isActive: _isActive,
        );
      } else {
        // Create new shop
        success = await shopProvider.createShop(
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          phone: _phoneController.text.trim(),
          licenseNumber: _licenseNumberController.text.trim(),
          latitude: latitude,
          longitude: longitude,
        );
      }

      if (success && mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditMode
                  ? 'Shop updated successfully'
                  : 'Shop created successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );

        // Go back to shops list and return true to trigger refresh
        Navigator.pop(context, true);
      } else if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shopProvider.errorMessage ?? 'Failed to save shop',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: isEditMode ? 'Edit Shop' : 'Add New Shop',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Shop Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Shop Name *',
                hintText: 'Enter shop name',
                prefixIcon: const Icon(Icons.store),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Shop name is required';
                }
                return null;
              },
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Address
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Address *',
                hintText: 'Enter shop address',
                prefixIcon: const Icon(Icons.location_on),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Address is required';
                }
                return null;
              },
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Phone Number
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: 'Enter phone number',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  // Basic phone validation
                  if (value.length < 10) {
                    return 'Phone number must be at least 10 digits';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // License Number
            TextFormField(
              controller: _licenseNumberController,
              decoration: InputDecoration(
                labelText: 'License Number',
                hintText: 'Enter license number',
                prefixIcon: const Icon(Icons.badge),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Location Section
            Text(
              'Location (Optional)',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitudeController,
                    decoration: InputDecoration(
                      labelText: 'Latitude',
                      hintText: '0.0',
                      prefixIcon: const Icon(Icons.location_searching),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final lat = double.tryParse(value);
                        if (lat == null) {
                          return 'Invalid latitude';
                        }
                        if (lat < -90 || lat > 90) {
                          return 'Lat: -90 to 90';
                        }
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _longitudeController,
                    decoration: InputDecoration(
                      labelText: 'Longitude',
                      hintText: '0.0',
                      prefixIcon: const Icon(Icons.location_searching),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final lng = double.tryParse(value);
                        if (lng == null) {
                          return 'Invalid longitude';
                        }
                        if (lng < -180 || lng > 180) {
                          return 'Lng: -180 to 180';
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Active Status (only for edit mode)
            if (isEditMode) ...[
              SwitchListTile(
                title: const Text('Active Status'),
                subtitle: Text(
                  _isActive ? 'Shop is active' : 'Shop is inactive',
                  style: AppTextStyles.bodySmall,
                ),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
                activeColor: AppColors.success,
              ),
              const SizedBox(height: 20),
            ],

            // Submit Button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        isEditMode ? 'Update Shop' : 'Create Shop',
                        style: AppTextStyles.button.copyWith(
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
