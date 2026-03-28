/// Expense Header Model for Daily Sales
/// Represents expense categories with predefined defaults and custom headers
library;

class ExpenseHeader {
  final String id;
  final String name;
  final bool isDefault;
  bool isActive;

  ExpenseHeader({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_default': isDefault,
        'is_active': isActive,
      };

  factory ExpenseHeader.fromJson(Map<String, dynamic> json) => ExpenseHeader(
        id: json['id'] as String,
        name: json['name'] as String,
        isDefault: json['is_default'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );

  ExpenseHeader copyWith({
    String? id,
    String? name,
    bool? isDefault,
    bool? isActive,
  }) {
    return ExpenseHeader(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Default expense headers for UP liquor shops
  static List<ExpenseHeader> get defaultHeaders => [
        ExpenseHeader(id: 'godam_charges', name: 'Godam Charges', isDefault: true, isActive: true),
        ExpenseHeader(id: 'transport', name: 'Transport', isDefault: true, isActive: true),
        ExpenseHeader(id: 'license_fee', name: 'License Fee', isDefault: true, isActive: true),
        ExpenseHeader(id: 'staff_salary', name: 'Staff Salary', isDefault: true, isActive: true),
        ExpenseHeader(id: 'shop_rent', name: 'Shop Rent', isDefault: true, isActive: true),
        ExpenseHeader(id: 'utilities', name: 'Utilities', isDefault: true, isActive: true),
        ExpenseHeader(id: 'breakage', name: 'Breakage/Leakage', isDefault: true, isActive: true),
        ExpenseHeader(id: 'cooler_rent', name: 'Cooler Rent', isDefault: true, isActive: true),
        ExpenseHeader(id: 'loading_unloading', name: 'Loading/Unloading', isDefault: true, isActive: true),
        ExpenseHeader(id: 'muneem', name: 'Muneem/Accountant', isDefault: true, isActive: true),
        ExpenseHeader(id: 'electricity', name: 'Electricity', isDefault: true, isActive: true),
        ExpenseHeader(id: 'cleaning', name: 'Cleaning/Safai', isDefault: true, isActive: true),
        ExpenseHeader(id: 'police_local', name: 'Local/Police', isDefault: true, isActive: true),
        ExpenseHeader(id: 'misc', name: 'Miscellaneous', isDefault: true, isActive: true),
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseHeader &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Expense Entry for a specific header
class ExpenseEntry {
  final String headerId;
  final String headerName;
  final double amount;

  ExpenseEntry({
    required this.headerId,
    required this.headerName,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'header_id': headerId,
        'header_name': headerName,
        'amount': amount,
      };

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) => ExpenseEntry(
        headerId: json['header_id'] as String,
        headerName: json['header_name'] as String,
        amount: (json['amount'] as num).toDouble(),
      );
}
