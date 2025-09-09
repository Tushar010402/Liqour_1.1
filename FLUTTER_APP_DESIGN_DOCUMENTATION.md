# 📱 LiquorPro Flutter Mobile Application - Complete Design Documentation

## 🎨 Executive Summary

**App Name:** LiquorPro  
**Platform:** Flutter (iOS & Android)  
**Design Philosophy:** Premium Dark Theme with Zomato-inspired UX  
**Target Users:** Liquor store managers, sales staff, and business owners  

---

## 🎯 Design System & Brand Guidelines

### **Color Palette**

```dart
// Primary Colors
const Color primaryBlack = Color(0xFF000000);      // Pure Black
const Color premiumBlack = Color(0xFF0A0A0A);      // Premium Black Background
const Color darkGrey = Color(0xFF1A1A1A);          // Card Background
const Color mediumGrey = Color(0xFF2A2A2A);        // Secondary Background

// Text Colors
const Color primaryWhite = Color(0xFFFFFFFF);      // Primary Text
const Color secondaryWhite = Color(0xFFE0E0E0);    // Secondary Text
const Color mutedWhite = Color(0xFF999999);        // Muted Text
const Color hintWhite = Color(0xFF666666);         // Hint Text

// Accent Colors
const Color premiumGold = Color(0xFFD4AF37);       // Premium Actions
const Color successGreen = Color(0xFF00C853);      // Success States
const Color errorRed = Color(0xFFFF5252);          // Error States
const Color warningAmber = Color(0xFFFFC107);      // Warning States

// Gradient Colors
const LinearGradient premiumGradient = LinearGradient(
  colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
```

### **Typography System**

```dart
// Font Family: Inter (Primary), SF Pro Display (iOS), Roboto (Android)

class AppTypography {
  // Display Styles
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: primaryWhite,
    letterSpacing: -0.5,
  );
  
  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: primaryWhite,
    letterSpacing: -0.3,
  );
  
  // Heading Styles
  static const TextStyle headingLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: primaryWhite,
  );
  
  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: primaryWhite,
  );
  
  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: primaryWhite,
  );
  
  // Body Styles
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: secondaryWhite,
    height: 1.5,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: secondaryWhite,
    height: 1.5,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: mutedWhite,
    height: 1.4,
  );
  
  // Label Styles
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: primaryWhite,
    letterSpacing: 0.1,
  );
  
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: mutedWhite,
    letterSpacing: 0.5,
    textTransform: TextTransform.uppercase,
  );
}
```

### **Spacing & Layout System**

```dart
class AppSpacing {
  // Base unit: 4px
  static const double xs = 4.0;   // Extra small
  static const double sm = 8.0;   // Small
  static const double md = 16.0;  // Medium
  static const double lg = 24.0;  // Large
  static const double xl = 32.0;  // Extra large
  static const double xxl = 48.0; // Double extra large
  
  // Screen Padding
  static const EdgeInsets screenPadding = EdgeInsets.all(16.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
}

class AppRadius {
  static const double xs = 4.0;   // Buttons, chips
  static const double sm = 8.0;   // Cards, inputs
  static const double md = 12.0;  // Modals
  static const double lg = 16.0;  // Bottom sheets
  static const double xl = 24.0;  // Special cards
  static const double round = 999.0; // Pills, avatars
}
```

---

## 🏗️ App Architecture & Structure

### **Project Structure**

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── api/
│   │   ├── api_client.dart
│   │   ├── api_endpoints.dart
│   │   ├── api_interceptors.dart
│   │   └── api_exceptions.dart
│   ├── constants/
│   │   ├── app_colors.dart
│   │   ├── app_typography.dart
│   │   ├── app_spacing.dart
│   │   └── app_strings.dart
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_guards.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── storage_service.dart
│   │   ├── notification_service.dart
│   │   └── analytics_service.dart
│   └── utils/
│       ├── validators.dart
│       ├── formatters.dart
│       └── extensions.dart
├── data/
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── product_model.dart
│   │   ├── order_model.dart
│   │   └── tenant_model.dart
│   ├── repositories/
│   │   ├── auth_repository.dart
│   │   ├── product_repository.dart
│   │   ├── order_repository.dart
│   │   └── finance_repository.dart
│   └── providers/
│       ├── auth_provider.dart
│       ├── cart_provider.dart
│       └── app_state_provider.dart
├── presentation/
│   ├── screens/
│   │   ├── splash/
│   │   ├── onboarding/
│   │   ├── auth/
│   │   ├── home/
│   │   ├── products/
│   │   ├── cart/
│   │   ├── orders/
│   │   ├── profile/
│   │   └── settings/
│   ├── widgets/
│   │   ├── common/
│   │   ├── buttons/
│   │   ├── cards/
│   │   ├── inputs/
│   │   └── dialogs/
│   └── themes/
│       ├── app_theme.dart
│       └── dark_theme.dart
└── features/
    ├── inventory/
    ├── sales/
    ├── finance/
    └── analytics/
```

---

## 📱 Screen Designs & Layouts

### **1. Splash Screen**

```dart
class SplashScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBlack,
      body: Container(
        decoration: BoxDecoration(gradient: premiumGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              AnimatedContainer(
                duration: Duration(seconds: 1),
                child: Image.asset(
                  'assets/images/logo_white.png',
                  width: 120,
                  height: 120,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'LiquorPro',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: primaryWhite,
                  letterSpacing: -1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Premium Liquor Management',
                style: TextStyle(
                  fontSize: 14,
                  color: mutedWhite,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 48),
              // Loading Indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(premiumGold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### **2. Login Screen**

```dart
class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 48),
              // Welcome Text
              Text(
                'Welcome Back',
                style: AppTypography.displayLarge,
              ),
              SizedBox(height: 8),
              Text(
                'Sign in to continue',
                style: AppTypography.bodyLarge.copyWith(
                  color: mutedWhite,
                ),
              ),
              SizedBox(height: 48),
              
              // Email Input
              PremiumTextField(
                label: 'Email',
                hint: 'Enter your email',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 20),
              
              // Password Input
              PremiumTextField(
                label: 'Password',
                hint: 'Enter your password',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
                suffixIcon: Icons.visibility_outlined,
              ),
              SizedBox(height: 12),
              
              // Forgot Password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: premiumGold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32),
              
              // Login Button
              PremiumButton(
                text: 'Sign In',
                onPressed: () {},
                isFullWidth: true,
              ),
              SizedBox(height: 24),
              
              // Or Divider
              Row(
                children: [
                  Expanded(child: Divider(color: mediumGrey)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(color: mutedWhite, fontSize: 12),
                    ),
                  ),
                  Expanded(child: Divider(color: mediumGrey)),
                ],
              ),
              SizedBox(height: 24),
              
              // Social Login
              Row(
                children: [
                  Expanded(
                    child: SocialLoginButton(
                      icon: 'assets/icons/google.svg',
                      text: 'Google',
                      onPressed: () {},
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: SocialLoginButton(
                      icon: 'assets/icons/apple.svg',
                      text: 'Apple',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
              SizedBox(height: 48),
              
              // Sign Up Link
              Center(
                child: RichText(
                  text: TextSpan(
                    text: "Don't have an account? ",
                    style: TextStyle(color: mutedWhite),
                    children: [
                      TextSpan(
                        text: 'Sign Up',
                        style: TextStyle(
                          color: premiumGold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### **3. Home Dashboard (Zomato-like)**

```dart
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBlack,
      body: CustomScrollView(
        slivers: [
          // Custom App Bar with Search
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: premiumBlack,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(gradient: premiumGradient),
                padding: EdgeInsets.fromLTRB(16, 48, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good Morning',
                              style: TextStyle(
                                color: mutedWhite,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'John Doe',
                              style: TextStyle(
                                color: primaryWhite,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.notifications_outlined),
                              color: primaryWhite,
                              onPressed: () {},
                            ),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: darkGrey,
                              child: Icon(
                                Icons.person_outline,
                                color: primaryWhite,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(60),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SearchBar(
                  hint: 'Search products, brands...',
                  onTap: () {},
                ),
              ),
            ),
          ),
          
          // Quick Stats Cards (Horizontal Scroll)
          SliverToBoxAdapter(
            child: Container(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16),
                children: [
                  QuickStatCard(
                    title: 'Today\'s Sales',
                    value: '₹45,230',
                    change: '+12%',
                    icon: Icons.trending_up,
                    color: successGreen,
                  ),
                  QuickStatCard(
                    title: 'Pending Orders',
                    value: '23',
                    change: '5 urgent',
                    icon: Icons.pending_actions,
                    color: warningAmber,
                  ),
                  QuickStatCard(
                    title: 'Low Stock',
                    value: '8 items',
                    change: 'Order now',
                    icon: Icons.inventory_2_outlined,
                    color: errorRed,
                  ),
                ],
              ),
            ),
          ),
          
          // Quick Actions Grid
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: AppTypography.headingMedium,
                  ),
                  SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    children: [
                      QuickActionButton(
                        icon: Icons.add_shopping_cart,
                        label: 'New Sale',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.inventory,
                        label: 'Inventory',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.receipt_long,
                        label: 'Orders',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.analytics,
                        label: 'Reports',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.people,
                        label: 'Customers',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.local_offer,
                        label: 'Offers',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.qr_code_scanner,
                        label: 'Scan',
                        onTap: () {},
                      ),
                      QuickActionButton(
                        icon: Icons.more_horiz,
                        label: 'More',
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Recent Orders Section
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Orders',
                        style: AppTypography.headingMedium,
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'View All',
                          style: TextStyle(color: premiumGold),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  ...List.generate(3, (index) => OrderCard(
                    orderNumber: '#ORD00${234 + index}',
                    customerName: 'Customer ${index + 1}',
                    amount: '₹${1250 + (index * 500)}',
                    status: index == 0 ? 'Pending' : 'Completed',
                    time: '${index + 1}h ago',
                  )),
                ],
              ),
            ),
          ),
          
          // Top Products Section
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Selling Products',
                    style: AppTypography.headingMedium,
                  ),
                  SizedBox(height: 16),
                  Container(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 5,
                      itemBuilder: (context, index) => ProductCard(
                        image: 'assets/products/product_$index.jpg',
                        name: 'Premium Whiskey',
                        brand: 'Royal Challenge',
                        price: '₹2,450',
                        stock: '23 units',
                        onTap: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: PremiumBottomNavBar(),
    );
  }
}
```

### **4. Product Listing Screen (Zomato-style)**

```dart
class ProductListingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBlack,
      body: CustomScrollView(
        slivers: [
          // Collapsible App Bar with Filters
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: premiumBlack,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: primaryWhite),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.search, color: primaryWhite),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.filter_list, color: primaryWhite),
                onPressed: () => _showFilterBottomSheet(context),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text('Products'),
              background: Container(
                decoration: BoxDecoration(gradient: premiumGradient),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Category Chips
                    Container(
                      height: 40,
                      margin: EdgeInsets.only(bottom: 60),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          CategoryChip(
                            label: 'All',
                            isSelected: true,
                            onTap: () {},
                          ),
                          CategoryChip(
                            label: 'Whiskey',
                            onTap: () {},
                          ),
                          CategoryChip(
                            label: 'Wine',
                            onTap: () {},
                          ),
                          CategoryChip(
                            label: 'Beer',
                            onTap: () {},
                          ),
                          CategoryChip(
                            label: 'Vodka',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Sort Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: SortBarDelegate(
              child: Container(
                color: premiumBlack,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '234 Products',
                      style: TextStyle(color: mutedWhite, fontSize: 14),
                    ),
                    Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.sort, size: 18, color: premiumGold),
                      label: Text(
                        'Sort by: Popularity',
                        style: TextStyle(color: premiumGold, fontSize: 14),
                      ),
                      onPressed: () => _showSortBottomSheet(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Product Grid
          SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => ProductGridCard(
                  image: 'assets/products/product_$index.jpg',
                  name: 'Premium Whiskey ${index + 1}',
                  brand: 'Brand Name',
                  price: '₹${2000 + (index * 100)}',
                  originalPrice: '₹${2500 + (index * 100)}',
                  discount: '20% OFF',
                  rating: 4.5,
                  stock: index % 3 == 0 ? 'Low Stock' : 'In Stock',
                  onTap: () => _navigateToProductDetail(context),
                  onAddToCart: () => _showAddToCartAnimation(context),
                ),
                childCount: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### **5. Product Detail Screen**

```dart
class ProductDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBlack,
      body: CustomScrollView(
        slivers: [
          // Product Image Carousel
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: darkGrey,
            leading: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: premiumBlack.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios, color: primaryWhite, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: premiumBlack.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.favorite_border, color: primaryWhite),
                  onPressed: () {},
                ),
              ),
              Container(
                margin: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: premiumBlack.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.share, color: primaryWhite),
                  onPressed: () {},
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  PageView.builder(
                    itemCount: 3,
                    itemBuilder: (context, index) => Image.asset(
                      'assets/products/detail_$index.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == 0 ? premiumGold : mutedWhite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Product Information
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand and Category
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: darkGrey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ROYAL CHALLENGE',
                          style: TextStyle(
                            color: premiumGold,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: darkGrey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'WHISKEY',
                          style: TextStyle(
                            color: mutedWhite,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  
                  // Product Name
                  Text(
                    'Royal Challenge Premium Whiskey',
                    style: AppTypography.headingLarge,
                  ),
                  SizedBox(height: 8),
                  
                  // Rating and Reviews
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: successGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.star, color: successGreen, size: 16),
                            SizedBox(width: 4),
                            Text(
                              '4.5',
                              style: TextStyle(
                                color: successGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '234 Reviews',
                        style: TextStyle(color: mutedWhite, fontSize: 14),
                      ),
                      Spacer(),
                      Text(
                        'In Stock',
                        style: TextStyle(
                          color: successGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  
                  // Price Section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹2,450',
                        style: TextStyle(
                          color: primaryWhite,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '₹3,200',
                        style: TextStyle(
                          color: mutedWhite,
                          fontSize: 18,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: errorRed.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '23% OFF',
                          style: TextStyle(
                            color: errorRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  
                  // Size Options
                  Text(
                    'Size',
                    style: AppTypography.labelLarge,
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      SizeOption(label: '180ml', price: '₹450', onTap: () {}),
                      SizeOption(label: '375ml', price: '₹950', onTap: () {}),
                      SizeOption(
                        label: '750ml',
                        price: '₹2,450',
                        isSelected: true,
                        onTap: () {},
                      ),
                      SizeOption(label: '1L', price: '₹3,200', onTap: () {}),
                    ],
                  ),
                  SizedBox(height: 24),
                  
                  // Description
                  Text(
                    'Description',
                    style: AppTypography.labelLarge,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Royal Challenge Premium Whiskey is a blend of the finest Indian grain spirits and imported Scotch malts. Aged to perfection, it delivers a smooth and rich taste that defines premium quality.',
                    style: AppTypography.bodyMedium.copyWith(height: 1.6),
                  ),
                  SizedBox(height: 24),
                  
                  // Product Details
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: darkGrey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        DetailRow(label: 'Brand', value: 'Royal Challenge'),
                        DetailRow(label: 'Category', value: 'Whiskey'),
                        DetailRow(label: 'Alcohol Content', value: '42.8%'),
                        DetailRow(label: 'Volume', value: '750ml'),
                        DetailRow(label: 'Country', value: 'India'),
                        DetailRow(label: 'SKU', value: 'RC-PREM-750'),
                      ],
                    ),
                  ),
                  SizedBox(height: 100), // Space for bottom bar
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: darkGrey,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Quantity Selector
              Container(
                decoration: BoxDecoration(
                  color: mediumGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.remove, color: primaryWhite),
                      onPressed: () {},
                    ),
                    Text(
                      '1',
                      style: TextStyle(
                        color: primaryWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add, color: primaryWhite),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              // Add to Cart Button
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: premiumGold,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Add to Cart • ₹2,450',
                    style: TextStyle(
                      color: premiumBlack,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 🎨 Reusable Components Library

### **1. Premium Button Component**

```dart
class PremiumButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isFullWidth;
  final bool isOutlined;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  
  const PremiumButton({
    required this.text,
    required this.onPressed,
    this.isFullWidth = false,
    this.isOutlined = false,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });
  
  @override
  Widget build(BuildContext context) {
    final buttonColor = backgroundColor ?? premiumGold;
    final labelColor = textColor ?? (isOutlined ? premiumGold : premiumBlack);
    
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.transparent : buttonColor,
          elevation: isOutlined ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isOutlined
                ? BorderSide(color: buttonColor, width: 1.5)
                : BorderSide.none,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(labelColor),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: labelColor, size: 20),
                    SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
```

### **2. Premium Text Field Component**

```dart
class PremiumTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? Function(String?)? validator;
  final VoidCallback? onSuffixIconTap;
  
  const PremiumTextField({
    required this.label,
    required this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onSuffixIconTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: secondaryWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(color: primaryWhite, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: hintWhite),
            filled: true,
            fillColor: darkGrey,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: mutedWhite, size: 20)
                : null,
            suffixIcon: suffixIcon != null
                ? IconButton(
                    icon: Icon(suffixIcon, color: mutedWhite, size: 20),
                    onPressed: onSuffixIconTap,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: mediumGrey, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: premiumGold, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: errorRed, width: 1),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}
```

### **3. Product Card Component**

```dart
class ProductCard extends StatelessWidget {
  final String image;
  final String name;
  final String brand;
  final String price;
  final String? originalPrice;
  final String? discount;
  final double? rating;
  final String stock;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: darkGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.asset(
                    image,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (discount != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: errorRed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        discount,
                        style: TextStyle(
                          color: primaryWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: premiumBlack.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.favorite_border, size: 18),
                      color: primaryWhite,
                      onPressed: () {},
                    ),
                  ),
                ),
              ],
            ),
            
            // Product Info
            Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brand.toUpperCase(),
                    style: TextStyle(
                      color: premiumGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    name,
                    style: TextStyle(
                      color: primaryWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          color: primaryWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (originalPrice != null) ...[
                        SizedBox(width: 4),
                        Text(
                          originalPrice,
                          style: TextStyle(
                            color: mutedWhite,
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (rating != null)
                        Row(
                          children: [
                            Icon(Icons.star, color: premiumGold, size: 14),
                            SizedBox(width: 2),
                            Text(
                              rating.toString(),
                              style: TextStyle(
                                color: secondaryWhite,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      Text(
                        stock,
                        style: TextStyle(
                          color: stock.contains('Low') ? errorRed : successGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### **4. Bottom Navigation Bar**

```dart
class PremiumBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: darkGrey,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavBarItem(
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: 'Products',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavBarItem(
                icon: Icons.shopping_cart_outlined,
                activeIcon: Icons.shopping_cart,
                label: 'Cart',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
                badge: '3',
              ),
              _NavBarItem(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'Orders',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavBarItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                isActive: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? badge;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? premiumGold : mutedWhite,
                  size: 24,
                ),
                if (badge != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: errorRed,
                        shape: BoxShape.circle,
                      ),
                      constraints: BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          color: primaryWhite,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? premiumGold : mutedWhite,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 🔌 API Integration

### **API Client Setup**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const String baseUrl = 'http://localhost:8090/api';
  static const Duration timeout = Duration(seconds: 30);
  
  late Dio _dio;
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Request Interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Add auth token
        final token = await _storage.read(key: 'auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        // Add API version
        options.headers['X-API-Version'] = 'v1.0.0';
        
        print('REQUEST[${options.method}] => PATH: ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('RESPONSE[${response.statusCode}] => DATA: ${response.data}');
        return handler.next(response);
      },
      onError: (error, handler) async {
        print('ERROR[${error.response?.statusCode}] => MESSAGE: ${error.message}');
        
        // Handle token refresh
        if (error.response?.statusCode == 401) {
          await _refreshToken();
          return handler.resolve(await _retry(error.requestOptions));
        }
        
        return handler.next(error);
      },
    ));
  }
  
  // Auth Endpoints
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    
    // Save token
    await _storage.write(key: 'auth_token', value: response.data['token']);
    await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
    
    return response.data;
  }
  
  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    final response = await _dio.post('/auth/register', data: userData);
    
    // Save token
    await _storage.write(key: 'auth_token', value: response.data['token']);
    await _storage.write(key: 'refresh_token', value: response.data['refresh_token']);
    
    return response.data;
  }
  
  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/auth/profile');
    return response.data;
  }
  
  // Product Endpoints
  Future<List<dynamic>> getProducts({
    int page = 1,
    int limit = 20,
    String? category,
    String? search,
    String? sort,
  }) async {
    final response = await _dio.get('/inventory/products', queryParameters: {
      'page': page,
      'limit': limit,
      if (category != null) 'category': category,
      if (search != null) 'search': search,
      if (sort != null) 'sort': sort,
    });
    return response.data['products'];
  }
  
  Future<Map<String, dynamic>> getProductDetail(String productId) async {
    final response = await _dio.get('/inventory/products/$productId');
    return response.data;
  }
  
  // Order Endpoints
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    final response = await _dio.post('/sales/orders', data: orderData);
    return response.data;
  }
  
  Future<List<dynamic>> getOrders({int page = 1, int limit = 20}) async {
    final response = await _dio.get('/sales/orders', queryParameters: {
      'page': page,
      'limit': limit,
    });
    return response.data['orders'];
  }
  
  // Helper Methods
  Future<void> _refreshToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) throw Exception('No refresh token');
    
    final response = await _dio.post('/auth/refresh', data: {
      'refresh_token': refreshToken,
    });
    
    await _storage.write(key: 'auth_token', value: response.data['token']);
  }
  
  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final token = await _storage.read(key: 'auth_token');
    requestOptions.headers['Authorization'] = 'Bearer $token';
    
    return _dio.request(
      requestOptions.path,
      options: Options(
        method: requestOptions.method,
        headers: requestOptions.headers,
      ),
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
    );
  }
}
```

### **Repository Pattern**

```dart
// Product Repository
class ProductRepository {
  final ApiClient _apiClient;
  
  ProductRepository(this._apiClient);
  
  Future<List<Product>> getProducts({
    int page = 1,
    String? category,
    String? search,
  }) async {
    try {
      final data = await _apiClient.getProducts(
        page: page,
        category: category,
        search: search,
      );
      
      return data.map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load products: $e');
    }
  }
  
  Future<Product> getProductDetail(String productId) async {
    try {
      final data = await _apiClient.getProductDetail(productId);
      return Product.fromJson(data);
    } catch (e) {
      throw Exception('Failed to load product detail: $e');
    }
  }
  
  Future<List<Category>> getCategories() async {
    try {
      final response = await _apiClient._dio.get('/inventory/categories');
      final data = response.data['categories'] as List;
      return data.map((json) => Category.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load categories: $e');
    }
  }
  
  Future<List<Brand>> getBrands() async {
    try {
      final response = await _apiClient._dio.get('/inventory/brands');
      final data = response.data['brands'] as List;
      return data.map((json) => Brand.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load brands: $e');
    }
  }
}
```

---

## 📊 State Management (Provider + Riverpod)

### **Auth Provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Auth State
class AuthState {
  final bool isAuthenticated;
  final User? user;
  final String? token;
  final bool isLoading;
  final String? error;
  
  AuthState({
    this.isAuthenticated = false,
    this.user,
    this.token,
    this.isLoading = false,
    this.error,
  });
  
  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    String? token,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      token: token ?? this.token,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

// Auth Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;
  
  AuthNotifier(this._apiClient, this._storage) : super(AuthState()) {
    _checkAuthStatus();
  }
  
  Future<void> _checkAuthStatus() async {
    final token = await _storage.read(key: 'auth_token');
    if (token != null) {
      try {
        final profile = await _apiClient.getProfile();
        state = state.copyWith(
          isAuthenticated: true,
          user: User.fromJson(profile),
          token: token,
        );
      } catch (e) {
        await logout();
      }
    }
  }
  
  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final response = await _apiClient.login(username, password);
      
      state = state.copyWith(
        isAuthenticated: true,
        user: User.fromJson(response['user']),
        token: response['token'],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
  
  Future<void> logout() async {
    await _storage.deleteAll();
    state = AuthState();
  }
}

// Providers
final apiClientProvider = Provider((ref) => ApiClient());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(apiClientProvider),
    FlutterSecureStorage(),
  );
});
```

### **Cart Provider**

```dart
// Cart State
class CartState {
  final List<CartItem> items;
  final double totalAmount;
  final int totalItems;
  final bool isLoading;
  
  CartState({
    this.items = const [],
    this.totalAmount = 0,
    this.totalItems = 0,
    this.isLoading = false,
  });
  
  CartState copyWith({
    List<CartItem>? items,
    double? totalAmount,
    int? totalItems,
    bool? isLoading,
  }) {
    return CartState(
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      totalItems: totalItems ?? this.totalItems,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Cart Notifier
class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState());
  
  void addToCart(Product product, int quantity) {
    final existingIndex = state.items.indexWhere(
      (item) => item.product.id == product.id,
    );
    
    List<CartItem> updatedItems;
    
    if (existingIndex >= 0) {
      updatedItems = [...state.items];
      updatedItems[existingIndex] = CartItem(
        product: product,
        quantity: state.items[existingIndex].quantity + quantity,
      );
    } else {
      updatedItems = [
        ...state.items,
        CartItem(product: product, quantity: quantity),
      ];
    }
    
    _updateState(updatedItems);
  }
  
  void removeFromCart(String productId) {
    final updatedItems = state.items.where(
      (item) => item.product.id != productId,
    ).toList();
    
    _updateState(updatedItems);
  }
  
  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    
    final updatedItems = state.items.map((item) {
      if (item.product.id == productId) {
        return CartItem(product: item.product, quantity: quantity);
      }
      return item;
    }).toList();
    
    _updateState(updatedItems);
  }
  
  void clearCart() {
    state = CartState();
  }
  
  void _updateState(List<CartItem> items) {
    final totalAmount = items.fold<double>(
      0,
      (sum, item) => sum + (item.product.price * item.quantity),
    );
    
    final totalItems = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    
    state = state.copyWith(
      items: items,
      totalAmount: totalAmount,
      totalItems: totalItems,
    );
  }
}

// Cart Provider
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
```

---

## 🚀 App Performance & Optimization

### **Performance Best Practices**

```dart
// 1. Image Caching
import 'package:cached_network_image/cached_network_image.dart';

class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  
  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => Container(
        color: darkGrey,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(premiumGold),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: darkGrey,
        child: Icon(Icons.error, color: mutedWhite),
      ),
      fadeInDuration: Duration(milliseconds: 300),
      memCacheWidth: (width ?? 200).toInt(),
      memCacheHeight: (height ?? 200).toInt(),
    );
  }
}

// 2. Lazy Loading List
class LazyLoadingList<T> extends StatefulWidget {
  final Future<List<T>> Function(int page) fetchData;
  final Widget Function(T item) itemBuilder;
  final Widget? emptyWidget;
  
  @override
  _LazyLoadingListState<T> createState() => _LazyLoadingListState<T>();
}

class _LazyLoadingListState<T> extends State<LazyLoadingList<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<T> _items = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  
  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }
  
  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);
    
    try {
      final newItems = await widget.fetchData(_currentPage);
      
      setState(() {
        _items.addAll(newItems);
        _currentPage++;
        _hasMore = newItems.isNotEmpty;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && !_isLoading) {
      return widget.emptyWidget ?? Center(child: Text('No items'));
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: _items.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _items.length) {
          return widget.itemBuilder(_items[index]);
        } else {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(premiumGold),
              ),
            ),
          );
        }
      },
    );
  }
}

// 3. Debounced Search
class DebouncedSearch extends StatefulWidget {
  final Function(String) onSearch;
  final Duration delay;
  
  DebouncedSearch({
    required this.onSearch,
    this.delay = const Duration(milliseconds: 500),
  });
  
  @override
  _DebouncedSearchState createState() => _DebouncedSearchState();
}

class _DebouncedSearchState extends State<DebouncedSearch> {
  Timer? _debounce;
  final TextEditingController _controller = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
  }
  
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(widget.delay, () {
      widget.onSearch(_controller.text);
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return PremiumTextField(
      controller: _controller,
      label: 'Search',
      hint: 'Search products...',
      prefixIcon: Icons.search,
      suffixIcon: _controller.text.isNotEmpty ? Icons.clear : null,
      onSuffixIconTap: () {
        _controller.clear();
        widget.onSearch('');
      },
    );
  }
}
```

---

## 📱 App Features & Business Logic

### **Feature List**

1. **Authentication & Multi-tenancy**
   - Login/Register with JWT
   - Multi-tenant support
   - Role-based access (Admin, Manager, Staff)
   - Biometric authentication

2. **Product Management**
   - Browse products with filters
   - Search with auto-suggestions
   - Barcode scanning
   - Product details with images
   - Stock tracking
   - Price management

3. **Sales & Orders**
   - Quick sale creation
   - Cart management
   - Order history
   - Invoice generation
   - Payment tracking
   - Daily sales reports

4. **Inventory Management**
   - Stock alerts
   - Reorder management
   - Category management
   - Brand management
   - Batch tracking

5. **Finance & Reports**
   - Sales analytics
   - Revenue tracking
   - Collection management
   - Expense tracking
   - Profit/Loss reports
   - Tax calculations

6. **Customer Management**
   - Customer profiles
   - Purchase history
   - Loyalty programs
   - Credit management

7. **Notifications**
   - Push notifications
   - In-app notifications
   - Low stock alerts
   - Order updates
   - Payment reminders

8. **Settings & Profile**
   - User profile management
   - App settings
   - Notification preferences
   - Language selection
   - Theme customization
   - Data sync settings

---

## 🔒 Security Implementation

```dart
// Biometric Authentication
import 'package:local_auth/local_auth.dart';

class BiometricAuth {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  
  static Future<bool> authenticateWithBiometrics() async {
    try {
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) return false;
      
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access LiquorPro',
        options: AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      return didAuthenticate;
    } catch (e) {
      print('Biometric authentication error: $e');
      return false;
    }
  }
}

// Secure Storage
class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  
  static Future<void> saveSecureData(String key, String value) async {
    await _storage.write(key: key, value: value);
  }
  
  static Future<String?> getSecureData(String key) async {
    return await _storage.read(key: key);
  }
  
  static Future<void> deleteSecureData(String key) async {
    await _storage.delete(key: key);
  }
  
  static Future<void> clearAllSecureData() async {
    await _storage.deleteAll();
  }
}
```

---

## 📦 Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Core
  dio: ^5.3.2
  flutter_riverpod: ^2.4.0
  go_router: ^11.1.2
  
  # UI/UX
  flutter_animate: ^4.2.0+1
  shimmer: ^3.0.0
  lottie: ^2.6.0
  flutter_svg: ^2.0.7
  
  # Storage
  flutter_secure_storage: ^9.0.0
  shared_preferences: ^2.2.1
  sqflite: ^2.3.0
  
  # Image & Media
  cached_network_image: ^3.3.0
  image_picker: ^1.0.4
  flutter_image_compress: ^2.0.4
  
  # Utilities
  intl: ^0.18.1
  uuid: ^4.1.0
  path_provider: ^2.1.1
  url_launcher: ^6.1.14
  
  # Authentication
  local_auth: ^2.1.6
  google_sign_in: ^6.1.5
  sign_in_with_apple: ^5.0.0
  
  # Notifications
  firebase_messaging: ^14.7.3
  flutter_local_notifications: ^16.1.0
  
  # Analytics
  firebase_analytics: ^10.6.3
  firebase_crashlytics: ^3.4.3
  
  # Scanning
  mobile_scanner: ^3.4.1
  
  # Charts & Visualization
  fl_chart: ^0.64.0
  syncfusion_flutter_charts: ^23.1.44

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  build_runner: ^2.4.6
  flutter_launcher_icons: ^0.13.1
```

---

## 🎯 Conclusion

This Flutter application design for LiquorPro provides:

1. **Premium Dark Theme** - Modern, elegant design with black/white color scheme
2. **Zomato-like UX** - Intuitive navigation and familiar patterns
3. **Comprehensive Features** - All business operations covered
4. **Industrial-grade Backend Integration** - Complete API integration with the Go backend
5. **Performance Optimized** - Lazy loading, caching, and efficient state management
6. **Security First** - Biometric auth, secure storage, JWT tokens
7. **Scalable Architecture** - Clean code structure with separation of concerns

The app is designed to be:
- **User-friendly** with intuitive navigation
- **Professional** with premium aesthetics
- **Efficient** with optimized performance
- **Secure** with enterprise-grade security
- **Maintainable** with clean architecture

This design ensures a seamless experience for liquor store management while maintaining the premium feel and professional functionality required for business operations.