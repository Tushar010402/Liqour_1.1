/// Shop Model
class Shop {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String? email;
  final String licenseNumber;
  final String? licenseFile;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    this.email,
    required this.licenseNumber,
    this.licenseFile,
    this.latitude,
    this.longitude,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      licenseNumber: json['license_number'] ?? '',
      licenseFile: json['license_file'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'license_number': licenseNumber,
      'license_file': licenseFile,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
    };
  }
}
