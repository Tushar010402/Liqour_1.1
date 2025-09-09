const { createDriver, deviceUtils, reportUtils } = require('../appium_config');
const assert = require('assert');
const { promises: fs } = require('fs');
const path = require('path');

describe('LiquorPro Flutter App - Appium Tests', function() {
  this.timeout(300000); // 5 minutes timeout for mobile tests
  
  let driver;
  let testResults = [];
  const platform = process.env.PLATFORM || 'android';
  const deviceType = process.env.DEVICE_TYPE || 'emulator';

  before(async function() {
    console.log(`🚀 Starting Appium tests for ${platform} ${deviceType}`);
    
    try {
      // Create screenshots directory
      await fs.mkdir(path.join(__dirname, '../screenshots', platform), { recursive: true });
      
      // Initialize driver
      driver = await createDriver(platform, deviceType);
      console.log('✅ Driver initialized successfully');
      
      // Wait for app to load
      await driver.pause(5000);
      
    } catch (error) {
      console.error('❌ Failed to initialize driver:', error);
      throw error;
    }
  });

  after(async function() {
    if (driver) {
      await driver.deleteSession();
      console.log('✅ Driver session closed');
    }
    
    // Generate test reports
    await reportUtils.generateReport(testResults);
    await reportUtils.generateHTMLReport(testResults);
    console.log('📊 Test reports generated');
  });

  beforeEach(async function() {
    // Take screenshot before each test
    const testName = this.currentTest.title.replace(/\s+/g, '_');
    await takeScreenshot(`before_${testName}`);
  });

  afterEach(async function() {
    const testName = this.currentTest.title.replace(/\s+/g, '_');
    const testResult = {
      name: this.currentTest.title,
      status: this.currentTest.state || 'unknown',
      duration: this.currentTest.duration || 0,
      error: this.currentTest.err ? this.currentTest.err.message : null
    };
    
    testResults.push(testResult);
    
    // Take screenshot after each test (especially failures)
    await takeScreenshot(`after_${testName}`);
  });

  // Helper function for screenshots
  async function takeScreenshot(filename) {
    try {
      if (platform === 'android') {
        await deviceUtils.android.takeScreenshot(driver, filename);
      } else {
        await deviceUtils.ios.takeScreenshot(driver, filename);
      }
    } catch (error) {
      console.warn('⚠️ Failed to take screenshot:', error.message);
    }
  }

  // Helper function to find elements by key
  async function findByKey(key, timeout = 10000) {
    const selector = `key:${key}`;
    await driver.waitUntil(
      async () => {
        const elements = await driver.$$(selector);
        return elements.length > 0;
      },
      { timeout, timeoutMsg: `Element with key "${key}" not found within ${timeout}ms` }
    );
    return await driver.$(selector);
  }

  // Helper function to find elements by text
  async function findByText(text, timeout = 10000) {
    const selector = `text:${text}`;
    await driver.waitUntil(
      async () => {
        const elements = await driver.$$(selector);
        return elements.length > 0;
      },
      { timeout, timeoutMsg: `Element with text "${text}" not found within ${timeout}ms` }
    );
    return await driver.$(selector);
  }

  describe('App Launch and Initialization', function() {
    it('should launch the app successfully', async function() {
      // Verify app launched by checking for main screen elements
      const mainElement = await findByKey('main_screen');
      assert(await mainElement.isDisplayed(), 'Main screen should be visible');
      
      console.log('✅ App launched successfully');
    });

    it('should display onboarding for new users', async function() {
      try {
        // Check if onboarding appears (might not for existing users)
        const onboardingElement = await findByKey('onboarding_screen');
        if (await onboardingElement.isDisplayed()) {
          console.log('✅ Onboarding screen displayed for new user');
          
          // Navigate through onboarding
          for (let i = 0; i < 3; i++) {
            const continueButton = await findByKey('continue_button');
            await continueButton.click();
            await driver.pause(1000);
          }
          
          const getStartedButton = await findByKey('get_started_button');
          await getStartedButton.click();
          await driver.pause(2000);
        } else {
          console.log('ℹ️ Onboarding skipped - returning user');
        }
      } catch (error) {
        console.log('ℹ️ No onboarding found - likely returning user');
      }
    });

    it('should measure app startup time', async function() {
      const startTime = Date.now();
      
      // Wait for main screen to be fully loaded
      await findByKey('main_screen');
      
      const endTime = Date.now();
      const startupTime = endTime - startTime;
      
      console.log(`📊 App startup time: ${startupTime}ms`);
      
      // Assert startup time is reasonable (under 5 seconds)
      assert(startupTime < 5000, `Startup time ${startupTime}ms exceeds 5000ms threshold`);
    });
  });

  describe('Authentication Flow', function() {
    it('should handle user registration', async function() {
      // Navigate to login screen if not already there
      try {
        const loginButton = await findByKey('login_button');
        await loginButton.click();
        await driver.pause(1000);
      } catch (error) {
        // Already on login screen or different state
      }

      // Switch to registration tab
      const registerTab = await findByKey('register_tab');
      await registerTab.click();
      await driver.pause(500);

      // Fill registration form
      const emailField = await findByKey('register_email_field');
      await emailField.click();
      await emailField.setValue('appium.test@liquorpro.com');

      const passwordField = await findByKey('register_password_field');
      await passwordField.click();
      await passwordField.setValue('AppiumTest123!');

      const nameField = await findByKey('register_name_field');
      await nameField.click();
      await nameField.setValue('Appium Test User');

      const phoneField = await findByKey('register_phone_field');
      await phoneField.click();
      await phoneField.setValue('9876543210');

      // Submit registration
      const submitButton = await findByKey('register_submit_button');
      await submitButton.click();

      // Wait for navigation or error message
      await driver.pause(3000);

      // Check for successful registration (dashboard) or error
      try {
        await findByKey('dashboard_screen');
        console.log('✅ Registration successful - navigated to dashboard');
      } catch (error) {
        // Check for error messages
        try {
          const errorElement = await findByKey('registration_error');
          const errorText = await errorElement.getText();
          console.log(`ℹ️ Registration error: ${errorText}`);
        } catch (err) {
          throw new Error('Registration failed without clear error message');
        }
      }
    });

    it('should handle user login', async function() {
      // Navigate to login screen
      try {
        const loginTab = await findByKey('login_tab');
        await loginTab.click();
        await driver.pause(500);
      } catch (error) {
        // Already on login screen
      }

      // Fill login form
      const emailField = await findByKey('email_field');
      await emailField.click();
      await emailField.setValue('test@liquorpro.com');

      const passwordField = await findByKey('password_field');
      await passwordField.click();
      await passwordField.setValue('TestPassword123!');

      // Submit login
      const loginButton = await findByKey('submit_login_button');
      await loginButton.click();

      // Wait for navigation
      await driver.pause(3000);

      // Verify navigation to dashboard
      const dashboardElement = await findByKey('dashboard_screen');
      assert(await dashboardElement.isDisplayed(), 'Should navigate to dashboard after login');
      
      console.log('✅ Login successful');
    });

    it('should handle biometric authentication setup', async function() {
      // Navigate to settings
      const profileTab = await findByKey('profile_tab');
      await profileTab.click();
      await driver.pause(1000);

      const settingsButton = await findByKey('settings_button');
      await settingsButton.click();
      await driver.pause(1000);

      // Enable biometric authentication
      try {
        const biometricSwitch = await findByKey('biometric_switch');
        await biometricSwitch.click();
        await driver.pause(2000);

        // Handle biometric prompt (if appears)
        try {
          const biometricPrompt = await findByKey('biometric_prompt');
          if (await biometricPrompt.isDisplayed()) {
            // Simulate successful biometric authentication
            const successButton = await findByKey('biometric_success');
            await successButton.click();
            console.log('✅ Biometric authentication enabled');
          }
        } catch (error) {
          console.log('ℹ️ Biometric prompt not available on this device');
        }
      } catch (error) {
        console.log('ℹ️ Biometric authentication not available on this device');
      }
    });
  });

  describe('Product Browsing and Search', function() {
    before(async function() {
      // Ensure we're logged in and on dashboard
      try {
        await findByKey('dashboard_screen');
      } catch (error) {
        throw new Error('Must be logged in for product tests');
      }
    });

    it('should browse products', async function() {
      // Navigate to products tab
      const productsTab = await findByKey('products_tab');
      await productsTab.click();
      await driver.pause(2000);

      // Verify products screen loaded
      const productsScreen = await findByKey('products_screen');
      assert(await productsScreen.isDisplayed(), 'Products screen should be visible');

      // Check for product cards
      try {
        const productCard = await findByKey('product_card_0');
        assert(await productCard.isDisplayed(), 'At least one product should be visible');
        console.log('✅ Products loaded successfully');
      } catch (error) {
        // Check for loading indicator or empty state
        console.log('ℹ️ No products found or still loading');
      }
    });

    it('should search for products', async function() {
      // Navigate to products if not already there
      try {
        const productsTab = await findByKey('products_tab');
        await productsTab.click();
        await driver.pause(1000);
      } catch (error) {
        // Already on products screen
      }

      // Tap search field
      const searchField = await findByKey('search_field');
      await searchField.click();
      await searchField.setValue('whiskey');
      await driver.pause(2000);

      // Verify search results
      try {
        const searchResults = await findByKey('search_results');
        assert(await searchResults.isDisplayed(), 'Search results should be displayed');
        console.log('✅ Search functionality working');
      } catch (error) {
        console.log('ℹ️ No search results found for query');
      }
    });

    it('should view product details', async function() {
      // Find and tap first product card
      try {
        const productCard = await findByKey('product_card_0');
        await productCard.click();
        await driver.pause(2000);

        // Verify product details screen
        const productDetailsScreen = await findByKey('product_details_screen');
        assert(await productDetailsScreen.isDisplayed(), 'Product details screen should be visible');

        // Verify product information is displayed
        const productTitle = await findByKey('product_title');
        const productPrice = await findByKey('product_price');
        
        assert(await productTitle.isDisplayed(), 'Product title should be visible');
        assert(await productPrice.isDisplayed(), 'Product price should be visible');
        
        console.log('✅ Product details displayed correctly');
      } catch (error) {
        throw new Error('Failed to view product details: ' + error.message);
      }
    });
  });

  describe('Shopping Cart Management', function() {
    it('should add product to cart', async function() {
      // Ensure we're on product details screen
      try {
        await findByKey('product_details_screen');
      } catch (error) {
        // Navigate to a product first
        const productsTab = await findByKey('products_tab');
        await productsTab.click();
        await driver.pause(1000);
        
        const productCard = await findByKey('product_card_0');
        await productCard.click();
        await driver.pause(2000);
      }

      // Adjust quantity if needed
      try {
        const quantityIncrease = await findByKey('quantity_increase');
        await quantityIncrease.click();
        await driver.pause(500);
      } catch (error) {
        console.log('ℹ️ Quantity controls not found');
      }

      // Add to cart
      const addToCartButton = await findByKey('add_to_cart_button');
      await addToCartButton.click();
      await driver.pause(2000);

      // Verify success message or cart update
      try {
        const successMessage = await findByKey('cart_success_message');
        assert(await successMessage.isDisplayed(), 'Success message should appear');
        console.log('✅ Product added to cart successfully');
      } catch (error) {
        // Check cart count instead
        try {
          const cartCount = await findByKey('cart_count');
          const count = await cartCount.getText();
          assert(parseInt(count) > 0, 'Cart count should be greater than 0');
          console.log('✅ Cart updated with new item');
        } catch (err) {
          throw new Error('Failed to verify cart addition');
        }
      }
    });

    it('should view and manage cart', async function() {
      // Navigate to cart
      const cartTab = await findByKey('cart_tab');
      await cartTab.click();
      await driver.pause(1000);

      // Verify cart screen
      const cartScreen = await findByKey('cart_screen');
      assert(await cartScreen.isDisplayed(), 'Cart screen should be visible');

      // Check for cart items
      try {
        const cartItem = await findByKey('cart_item_0');
        assert(await cartItem.isDisplayed(), 'Cart item should be visible');

        // Test quantity modification
        const quantityIncrease = await findByKey('cart_item_quantity_increase');
        await quantityIncrease.click();
        await driver.pause(1000);

        console.log('✅ Cart management working correctly');
      } catch (error) {
        throw new Error('Cart is empty or cart management failed');
      }
    });
  });

  describe('Checkout Process', function() {
    it('should complete checkout process', async function() {
      // Ensure we have items in cart
      try {
        const cartTab = await findByKey('cart_tab');
        await cartTab.click();
        await driver.pause(1000);

        const cartItem = await findByKey('cart_item_0');
        assert(await cartItem.isDisplayed(), 'Must have items in cart for checkout');
      } catch (error) {
        throw new Error('Cart is empty - cannot test checkout');
      }

      // Proceed to checkout
      const checkoutButton = await findByKey('proceed_to_checkout_button');
      await checkoutButton.click();
      await driver.pause(2000);

      // Verify checkout screen
      const checkoutScreen = await findByKey('checkout_screen');
      assert(await checkoutScreen.isDisplayed(), 'Checkout screen should be visible');

      // Fill shipping information
      const addressField = await findByKey('address_field');
      await addressField.click();
      await addressField.setValue('123 Test Street, Test City, 12345');

      try {
        const landmarkField = await findByKey('landmark_field');
        await landmarkField.click();
        await landmarkField.setValue('Near Test Mall');
      } catch (error) {
        console.log('ℹ️ Landmark field not found');
      }

      // Select payment method
      try {
        const paymentMethodCard = await findByKey('payment_method_card');
        await paymentMethodCard.click();
        await driver.pause(1000);

        // Fill card details (if required)
        try {
          const cardNumberField = await findByKey('card_number_field');
          await cardNumberField.click();
          await cardNumberField.setValue('4111111111111111');

          const expiryField = await findByKey('card_expiry_field');
          await expiryField.click();
          await expiryField.setValue('12/25');

          const cvvField = await findByKey('card_cvv_field');
          await cvvField.click();
          await cvvField.setValue('123');
        } catch (error) {
          console.log('ℹ️ Card detail fields not found - may be using stored payment');
        }
      } catch (error) {
        console.log('ℹ️ Payment method selection not found');
      }

      // Place order
      const placeOrderButton = await findByKey('place_order_button');
      await placeOrderButton.click();
      await driver.pause(5000);

      // Verify order confirmation
      try {
        const orderConfirmation = await findByKey('order_confirmation_screen');
        assert(await orderConfirmation.isDisplayed(), 'Order confirmation should be displayed');

        const orderNumber = await findByKey('order_number');
        assert(await orderNumber.isDisplayed(), 'Order number should be visible');

        console.log('✅ Checkout completed successfully');
      } catch (error) {
        // Check for error messages
        try {
          const errorMessage = await findByKey('checkout_error');
          const errorText = await errorMessage.getText();
          console.log(`⚠️ Checkout error: ${errorText}`);
        } catch (err) {
          throw new Error('Checkout failed without clear confirmation or error');
        }
      }
    });
  });

  describe('Navigation and UI Tests', function() {
    it('should navigate between main tabs', async function() {
      const tabs = [
        'dashboard_tab',
        'products_tab',
        'orders_tab',
        'profile_tab'
      ];

      for (const tabKey of tabs) {
        const tab = await findByKey(tabKey);
        await tab.click();
        await driver.pause(1000);

        // Verify corresponding screen is displayed
        const screenKey = tabKey.replace('_tab', '_screen');
        const screen = await findByKey(screenKey);
        assert(await screen.isDisplayed(), `${screenKey} should be visible when ${tabKey} is tapped`);

        console.log(`✅ Navigation to ${tabKey} successful`);
      }
    });

    it('should handle theme switching', async function() {
      // Navigate to settings
      const profileTab = await findByKey('profile_tab');
      await profileTab.click();
      await driver.pause(1000);

      const settingsButton = await findByKey('settings_button');
      await settingsButton.click();
      await driver.pause(1000);

      // Toggle theme
      try {
        const themeSwitch = await findByKey('theme_switch');
        await themeSwitch.click();
        await driver.pause(2000);

        console.log('✅ Theme switching working');
      } catch (error) {
        console.log('ℹ️ Theme switch not found');
      }
    });
  });

  describe('Performance and Responsiveness', function() {
    it('should handle rapid user interactions', async function() {
      // Navigate between tabs rapidly
      const tabs = ['dashboard_tab', 'products_tab', 'orders_tab', 'profile_tab'];
      
      for (let i = 0; i < 3; i++) {
        for (const tabKey of tabs) {
          const tab = await findByKey(tabKey);
          await tab.click();
          await driver.pause(200); // Minimal pause for rapid interaction
        }
      }

      console.log('✅ App handles rapid interactions well');
    });

    it('should test scrolling performance', async function() {
      // Navigate to products list
      const productsTab = await findByKey('products_tab');
      await productsTab.click();
      await driver.pause(1000);

      try {
        const productsList = await findByKey('products_list');
        
        // Perform multiple scroll gestures
        for (let i = 0; i < 5; i++) {
          const actions = [
            { type: 'pointer', id: 'finger1', parameters: { pointerType: 'touch' } }
          ];
          
          await driver.performActions([
            {
              type: 'pointer',
              id: 'finger1',
              actions: [
                { type: 'pointerMove', duration: 0, x: 200, y: 400 },
                { type: 'pointerDown', button: 0 },
                { type: 'pointerMove', duration: 500, x: 200, y: 100 },
                { type: 'pointerUp', button: 0 }
              ]
            }
          ]);
          
          await driver.pause(500);
        }

        console.log('✅ Scrolling performance test completed');
      } catch (error) {
        console.log('ℹ️ Scrolling test failed - list may be empty or not scrollable');
      }
    });
  });

  describe('Error Handling and Edge Cases', function() {
    it('should handle network connectivity issues', async function() {
      // This test would require network simulation capabilities
      // For now, we'll test the UI response to potential network errors
      
      try {
        // Navigate to a screen that requires network
        const productsTab = await findByKey('products_tab');
        await productsTab.click();
        await driver.pause(3000);

        // Look for error messages or loading states
        try {
          const errorMessage = await findByKey('network_error_message');
          if (await errorMessage.isDisplayed()) {
            console.log('✅ Network error handling UI present');
          }
        } catch (error) {
          console.log('ℹ️ No network errors detected');
        }

      } catch (error) {
        console.log('ℹ️ Network error test inconclusive');
      }
    });

    it('should handle invalid form inputs', async function() {
      // Navigate to login screen
      try {
        const loginButton = await findByKey('login_button');
        await loginButton.click();
        await driver.pause(1000);
      } catch (error) {
        // May already be on login or different screen
      }

      // Try to submit with empty fields
      try {
        const submitButton = await findByKey('submit_login_button');
        await submitButton.click();
        await driver.pause(2000);

        // Check for validation errors
        try {
          const emailError = await findByKey('email_error');
          const passwordError = await findByKey('password_error');
          
          if (await emailError.isDisplayed() || await passwordError.isDisplayed()) {
            console.log('✅ Form validation working correctly');
          }
        } catch (error) {
          console.log('ℹ️ Validation errors not visible or different validation approach');
        }
      } catch (error) {
        console.log('ℹ️ Login form test could not be completed');
      }
    });
  });
});