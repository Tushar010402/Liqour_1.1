import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/plan_model.dart';
import '../controllers/plan_provider.dart';

class PlanFormScreen extends StatefulWidget {
  final String? planId;

  const PlanFormScreen({super.key, this.planId});

  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _displayNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _maxUsersController;
  late TextEditingController _maxLocationsController;
  late TextEditingController _maxProductsController;
  late TextEditingController _trialDaysController;
  late TextEditingController _yearlyDiscountController;

  String _billingCycle = 'monthly';
  String _currency = 'INR';
  bool _isPopular = false;
  bool _isEnterprise = false;
  bool _isActive = true;
  List<String> _selectedFeatures = [];
  List<String> _selectedAiFeatures = [];

  bool _isLoading = false;
  bool _isEditMode = false;
  PlanModel? _editingPlan;

  final List<String> _availableFeatures = [
    'inventory_management',
    'sales_tracking',
    'basic_reports',
    'mobile_app',
    'email_support',
    'everything_in_starter',
    'advanced_analytics',
    'api_access',
    'custom_reports',
    'priority_support',
    'multi_location',
    'everything_in_professional',
    'white_label',
    'dedicated_support',
    'custom_integrations',
    'sla_guarantee',
    'advanced_security',
  ];

  final List<String> _availableAiFeatures = [
    'smart_inventory',
    'inventory_optimization',
    'sales_forecasting',
    'advanced_forecasting',
    'demand_planning',
    'price_optimization',
    'customer_insights',
    'predictive_analytics',
    'market_intelligence',
    'supply_chain_optimization',
    'custom_ai_models',
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _isEditMode = widget.planId != null;
    if (_isEditMode) {
      _loadPlanForEditing();
    }
  }

  void _initializeControllers() {
    _nameController = TextEditingController();
    _displayNameController = TextEditingController();
    _descriptionController = TextEditingController();
    _priceController = TextEditingController();
    _maxUsersController = TextEditingController();
    _maxLocationsController = TextEditingController();
    _maxProductsController = TextEditingController();
    _trialDaysController = TextEditingController();
    _yearlyDiscountController = TextEditingController();
  }

  void _loadPlanForEditing() {
    final planProvider = context.read<PlanProvider>();
    _editingPlan = planProvider.plans.firstWhere(
      (plan) => plan.id == widget.planId,
      orElse: () => throw Exception('Plan not found'),
    );

    if (_editingPlan != null) {
      _nameController.text = _editingPlan!.name;
      _displayNameController.text = _editingPlan!.displayName;
      _descriptionController.text = _editingPlan!.description;
      _priceController.text = _editingPlan!.price.toString();
      _maxUsersController.text =
          _editingPlan!.maxUsers == -1 ? '' : _editingPlan!.maxUsers.toString();
      _maxLocationsController.text = _editingPlan!.maxLocations == -1
          ? ''
          : _editingPlan!.maxLocations.toString();
      _maxProductsController.text = _editingPlan!.maxProducts == -1
          ? ''
          : _editingPlan!.maxProducts.toString();
      _trialDaysController.text = _editingPlan!.trialDays.toString();
      _yearlyDiscountController.text = _editingPlan!.yearlyDiscount.toString();

      _billingCycle = _editingPlan!.billingCycle;
      _currency = _editingPlan!.currency;
      _isPopular = _editingPlan!.popular;
      _isEnterprise = _editingPlan!.enterprise;
      _isActive = _editingPlan!.active;
      _selectedFeatures = List<String>.from(_editingPlan!.features ?? []);
      _selectedAiFeatures = List<String>.from(_editingPlan!.aiFeatures ?? []);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _maxUsersController.dispose();
    _maxLocationsController.dispose();
    _maxProductsController.dispose();
    _trialDaysController.dispose();
    _yearlyDiscountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(_isEditMode ? 'Edit Plan' : 'Create Plan'),
      actions: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBasicInfoCard(),
            const SizedBox(height: 16),
            _buildPricingCard(),
            const SizedBox(height: 16),
            _buildLimitsCard(),
            const SizedBox(height: 16),
            _buildFeaturesCard(),
            const SizedBox(height: 16),
            _buildAiFeaturesCard(),
            const SizedBox(height: 16),
            _buildSettingsCard(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Plan Name *',
                hintText: 'e.g., starter_plan',
                helperText: 'Internal name (lowercase, underscores only)',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Plan name is required';
                }
                if (!RegExp(r'^[a-z_]+$').hasMatch(value)) {
                  return 'Only lowercase letters and underscores allowed';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name *',
                hintText: 'e.g., Starter Plan',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Display name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'Brief description of the plan',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Description is required';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pricing',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price *',
                      hintText: '999',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Price is required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Invalid price';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                    ),
                    items: ['INR', 'USD', 'EUR'].map((currency) {
                      return DropdownMenuItem(
                        value: currency,
                        child: Text(currency),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _currency = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _billingCycle,
                    decoration: const InputDecoration(
                      labelText: 'Billing Cycle',
                    ),
                    items: ['monthly', 'yearly'].map((cycle) {
                      return DropdownMenuItem(
                        value: cycle,
                        child: Text(cycle.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _billingCycle = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _yearlyDiscountController,
                    decoration: const InputDecoration(
                      labelText: 'Yearly Discount (%)',
                      hintText: '20',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _trialDaysController,
              decoration: const InputDecoration(
                labelText: 'Trial Days',
                hintText: '30',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage Limits',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave empty for unlimited',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mediumGray,
                  ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _maxUsersController,
              decoration: const InputDecoration(
                labelText: 'Max Users',
                hintText: 'Leave empty for unlimited',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxLocationsController,
              decoration: const InputDecoration(
                labelText: 'Max Locations',
                hintText: 'Leave empty for unlimited',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxProductsController,
              decoration: const InputDecoration(
                labelText: 'Max Products',
                hintText: 'Leave empty for unlimited',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Features',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableFeatures.map((feature) {
                final isSelected = _selectedFeatures.contains(feature);
                return FilterChip(
                  selected: isSelected,
                  label: Text(_formatFeatureName(feature)),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedFeatures.add(feature);
                      } else {
                        _selectedFeatures.remove(feature);
                      }
                    });
                  },
                  backgroundColor: AppColors.white,
                  selectedColor: AppColors.lightRed,
                  checkmarkColor: AppColors.primaryRed,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiFeaturesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Features',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableAiFeatures.map((feature) {
                final isSelected = _selectedAiFeatures.contains(feature);
                return FilterChip(
                  selected: isSelected,
                  label: Text(_formatFeatureName(feature)),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedAiFeatures.add(feature);
                      } else {
                        _selectedAiFeatures.remove(feature);
                      }
                    });
                  },
                  backgroundColor: AppColors.white,
                  selectedColor: AppColors.lightRed,
                  checkmarkColor: AppColors.primaryRed,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Popular Plan'),
              subtitle: const Text('Mark this plan as popular'),
              value: _isPopular,
              onChanged: (value) {
                setState(() {
                  _isPopular = value;
                });
              },
              activeThumbColor: AppColors.primaryRed,
            ),
            SwitchListTile(
              title: const Text('Enterprise Plan'),
              subtitle: const Text('Mark this plan as enterprise'),
              value: _isEnterprise,
              onChanged: (value) {
                setState(() {
                  _isEnterprise = value;
                });
              },
              activeThumbColor: AppColors.primaryRed,
            ),
            SwitchListTile(
              title: const Text('Active'),
              subtitle: const Text('Enable this plan for new subscriptions'),
              value: _isActive,
              onChanged: (value) {
                setState(() {
                  _isActive = value;
                });
              },
              activeThumbColor: AppColors.primaryRed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => context.pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _savePlan,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Text(_isEditMode ? 'Update Plan' : 'Create Plan'),
          ),
        ),
      ],
    );
  }

  String _formatFeatureName(String feature) {
    return feature.replaceAll('_', ' ').split(' ').map((word) {
      return word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final planData = {
        'name': _nameController.text.trim(),
        'display_name': _displayNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': int.parse(_priceController.text.trim()),
        'currency': _currency,
        'billing_cycle': _billingCycle,
        'max_users': _maxUsersController.text.isEmpty
            ? -1
            : int.parse(_maxUsersController.text),
        'max_locations': _maxLocationsController.text.isEmpty
            ? -1
            : int.parse(_maxLocationsController.text),
        'max_products': _maxProductsController.text.isEmpty
            ? -1
            : int.parse(_maxProductsController.text),
        'trial_days': _trialDaysController.text.isEmpty
            ? 0
            : int.parse(_trialDaysController.text),
        'yearly_discount': _yearlyDiscountController.text.isEmpty
            ? 0
            : int.parse(_yearlyDiscountController.text),
        'popular': _isPopular,
        'enterprise': _isEnterprise,
        'active': _isActive,
        'features': _selectedFeatures,
        'ai_features': _selectedAiFeatures,
      };

      final planProvider = context.read<PlanProvider>();
      bool success;

      if (_isEditMode) {
        success = await planProvider.updatePlan(widget.planId!, planData);
      } else {
        success = await planProvider.createPlan(planData);
      }

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Plan updated successfully'
                : 'Plan created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(planProvider.errorMessage ?? 'Failed to save plan'),
            backgroundColor: AppColors.error,
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
