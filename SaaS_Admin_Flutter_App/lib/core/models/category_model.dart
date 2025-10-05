class Category {
  final String id;
  final String name;
  final String description;
  final String? picture;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Subcategory> subcategories;

  Category({
    required this.id,
    required this.name,
    required this.description,
    this.picture,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.subcategories = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      picture: json['picture'],
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      subcategories: (json['subcategories'] as List<dynamic>?)
              ?.map((subcategory) => Subcategory.fromJson(subcategory))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'picture': picture,
      'is_active': isActive,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'subcategories':
          subcategories.map((subcategory) => subcategory.toJson()).toList(),
    };
  }

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? picture,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Subcategory>? subcategories,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      picture: picture ?? this.picture,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      subcategories: subcategories ?? this.subcategories,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Category{id: $id, name: $name, isActive: $isActive, subcategories: ${subcategories.length}}';
  }
}

class Subcategory {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String? picture;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Subcategory({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    this.picture,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Subcategory.fromJson(Map<String, dynamic> json) {
    return Subcategory(
      id: json['id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      picture: json['picture'],
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'picture': picture,
      'is_active': isActive,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Subcategory copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    String? picture,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Subcategory(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      picture: picture ?? this.picture,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Subcategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Subcategory{id: $id, name: $name, categoryId: $categoryId, isActive: $isActive}';
  }
}

class CreateCategoryRequest {
  final String name;
  final String description;
  final String? picture;
  final bool isActive;
  final int sortOrder;

  CreateCategoryRequest({
    required this.name,
    required this.description,
    this.picture,
    this.isActive = true,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'picture': picture,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }
}

class CreateSubcategoryRequest {
  final String categoryId;
  final String name;
  final String description;
  final String? picture;
  final bool isActive;
  final int sortOrder;

  CreateSubcategoryRequest({
    required this.categoryId,
    required this.name,
    required this.description,
    this.picture,
    this.isActive = true,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'name': name,
      'description': description,
      'picture': picture,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }
}

class CategoryFilter {
  final String? searchTerm;
  final bool? isActive;
  final String sortBy;
  final bool sortAscending;

  CategoryFilter({
    this.searchTerm,
    this.isActive,
    this.sortBy = 'name',
    this.sortAscending = true,
  });

  CategoryFilter copyWith({
    String? searchTerm,
    bool? isActive,
    String? sortBy,
    bool? sortAscending,
  }) {
    return CategoryFilter(
      searchTerm: searchTerm ?? this.searchTerm,
      isActive: isActive ?? this.isActive,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
