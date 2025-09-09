const { remote } = require('webdriverio');

/**
 * Appium Configuration for LiquorPro Flutter App Testing
 * Supports Android and iOS device testing with real devices and emulators
 */

const appiumConfig = {
  // Appium Server Configuration
  server: {
    host: process.env.APPIUM_HOST || 'localhost',
    port: process.env.APPIUM_PORT || 4723,
    path: '/',
  },

  // Android Configuration
  android: {
    capabilities: {
      platformName: 'Android',
      platformVersion: process.env.ANDROID_VERSION || '13',
      deviceName: process.env.ANDROID_DEVICE_NAME || 'Android Emulator',
      app: process.env.ANDROID_APP_PATH || './build/app/outputs/apk/debug/app-debug.apk',
      appPackage: 'com.liquorpro.mobile',
      appActivity: 'com.liquorpro.mobile.MainActivity',
      automationName: 'Flutter',
      autoGrantPermissions: true,
      noReset: false,
      fullReset: false,
      newCommandTimeout: 300,
      androidInstallTimeout: 90000,
      autoAcceptAlerts: true,
      autoDismissAlerts: false,
      // Flutter-specific settings
      showChromedriverLog: true,
      enableMultiWindows: true,
      // Performance settings
      skipDeviceInitialization: false,
      skipServerInstallation: false,
      ignoreHiddenApiPolicyError: true,
      // Network settings
      networkSpeed: 'full',
      gpsEnabled: true,
      isHeadless: process.env.HEADLESS === 'true',
      // Screenshot settings
      screenshotQuality: 100,
      takeScreenshotOnFailure: true,
    },
    
    // Real device configuration
    realDevice: {
      udid: process.env.ANDROID_UDID,
      systemPort: 8201,
      chromeDriverPort: 8202,
    },

    // Emulator configuration
    emulator: {
      avd: process.env.ANDROID_AVD || 'liquorpro_test_emulator',
      avdLaunchTimeout: 120000,
      avdReadyTimeout: 120000,
    }
  },

  // iOS Configuration
  ios: {
    capabilities: {
      platformName: 'iOS',
      platformVersion: process.env.IOS_VERSION || '17.0',
      deviceName: process.env.IOS_DEVICE_NAME || 'iPhone 15',
      app: process.env.IOS_APP_PATH || './build/ios/ipa/Runner.app',
      bundleId: 'com.liquorpro.mobile',
      automationName: 'Flutter',
      noReset: false,
      fullReset: false,
      newCommandTimeout: 300,
      iosInstallPause: 8000,
      autoAcceptAlerts: true,
      autoDismissAlerts: false,
      // iOS-specific settings
      useNewWDA: true,
      wdaStartupRetries: 4,
      wdaStartupRetryInterval: 20000,
      iosInstallPause: 8000,
      showXcodeLog: true,
      // Flutter-specific
      showIOSLog: true,
      // Performance settings
      screenshotQuality: 2,
      takeScreenshotOnFailure: true,
      // Simulator settings
      isHeadless: process.env.HEADLESS === 'true',
      connectHardwareKeyboard: false,
    },

    // Real device configuration  
    realDevice: {
      udid: process.env.IOS_UDID,
      xcodeOrgId: process.env.XCODE_ORG_ID,
      xcodeSigningId: process.env.XCODE_SIGNING_ID,
      useNewWDA: true,
      wdaBaseUrl: 'http://localhost',
      wdaLocalPort: 8100,
    },

    // Simulator configuration
    simulator: {
      simulatorStartupTimeout: 120000,
      deviceReadyTimeout: 120000,
    }
  },

  // Test Configuration
  test: {
    timeout: 60000,
    retries: 2,
    screenshotPath: './test_automation/screenshots/',
    reportPath: './test_automation/reports/',
    
    // Test data
    testUsers: {
      valid: {
        email: 'test@liquorpro.com',
        password: 'TestPassword123!',
        name: 'Test User'
      },
      invalid: {
        email: 'invalid@test.com',
        password: 'wrongpassword'
      }
    },

    // Test scenarios
    scenarios: {
      smoke: [
        'app_launch',
        'login',
        'navigation'
      ],
      regression: [
        'onboarding_flow',
        'authentication',
        'product_browsing',
        'cart_management',
        'checkout_process',
        'profile_management',
        'settings'
      ],
      performance: [
        'app_startup_time',
        'memory_usage',
        'network_performance',
        'ui_responsiveness'
      ]
    }
  }
};

/**
 * Create driver instance based on platform
 */
async function createDriver(platform = 'android', deviceType = 'emulator') {
  const config = appiumConfig[platform];
  let capabilities = { ...config.capabilities };

  // Merge device-specific configuration
  if (deviceType === 'real') {
    capabilities = { ...capabilities, ...config.realDevice };
  } else {
    capabilities = { 
      ...capabilities, 
      ...(platform === 'android' ? config.emulator : config.simulator)
    };
  }

  const driver = await remote({
    ...appiumConfig.server,
    capabilities,
    logLevel: process.env.LOG_LEVEL || 'info',
    waitforTimeout: appiumConfig.test.timeout,
    connectionRetryCount: 3,
    connectionRetryTimeout: 120000,
  });

  // Configure implicit wait
  await driver.setImplicitTimeout(10000);
  
  return driver;
}

/**
 * Device management utilities
 */
const deviceUtils = {
  // Android device utilities
  android: {
    async listDevices() {
      const { exec } = require('child_process');
      return new Promise((resolve, reject) => {
        exec('adb devices', (error, stdout) => {
          if (error) reject(error);
          const devices = stdout.split('\n')
            .filter(line => line.includes('device') && !line.includes('List'))
            .map(line => line.split('\t')[0]);
          resolve(devices);
        });
      });
    },

    async installApp(deviceId, apkPath) {
      const { exec } = require('child_process');
      return new Promise((resolve, reject) => {
        exec(`adb -s ${deviceId} install -r ${apkPath}`, (error, stdout) => {
          if (error) reject(error);
          resolve(stdout);
        });
      });
    },

    async clearAppData(deviceId, packageName) {
      const { exec } = require('child_process');
      return new Promise((resolve, reject) => {
        exec(`adb -s ${deviceId} shell pm clear ${packageName}`, (error, stdout) => {
          if (error) reject(error);
          resolve(stdout);
        });
      });
    },

    async takeScreenshot(driver, filename) {
      const screenshot = await driver.saveScreenshot(
        `${appiumConfig.test.screenshotPath}android/${filename}.png`
      );
      return screenshot;
    }
  },

  // iOS device utilities
  ios: {
    async listDevices() {
      const { exec } = require('child_process');
      return new Promise((resolve, reject) => {
        exec('xcrun xctrace list devices', (error, stdout) => {
          if (error) reject(error);
          const devices = stdout.split('\n')
            .filter(line => line.includes('iPhone') || line.includes('iPad'))
            .map(line => {
              const match = line.match(/(.+) \((.+)\)/);
              return match ? { name: match[1].trim(), udid: match[2] } : null;
            })
            .filter(device => device);
          resolve(devices);
        });
      });
    },

    async installApp(deviceId, appPath) {
      const { exec } = require('child_process');
      return new Promise((resolve, reject) => {
        exec(`xcrun devicectl device install app --device ${deviceId} ${appPath}`, 
          (error, stdout) => {
            if (error) reject(error);
            resolve(stdout);
          }
        );
      });
    },

    async takeScreenshot(driver, filename) {
      const screenshot = await driver.saveScreenshot(
        `${appiumConfig.test.screenshotPath}ios/${filename}.png`
      );
      return screenshot;
    }
  }
};

/**
 * Test reporting utilities
 */
const reportUtils = {
  async generateReport(testResults) {
    const fs = require('fs');
    const path = require('path');
    
    const reportData = {
      timestamp: new Date().toISOString(),
      totalTests: testResults.length,
      passed: testResults.filter(t => t.status === 'passed').length,
      failed: testResults.filter(t => t.status === 'failed').length,
      skipped: testResults.filter(t => t.status === 'skipped').length,
      results: testResults
    };

    const reportPath = path.join(appiumConfig.test.reportPath, 'test-report.json');
    fs.writeFileSync(reportPath, JSON.stringify(reportData, null, 2));
    
    return reportData;
  },

  async generateHTMLReport(testResults) {
    const fs = require('fs');
    const path = require('path');
    
    const html = `
    <!DOCTYPE html>
    <html>
    <head>
        <title>LiquorPro Mobile Test Report</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
            .stats { display: flex; gap: 20px; margin: 20px 0; }
            .stat { background: #e9e9e9; padding: 15px; border-radius: 5px; text-align: center; }
            .passed { background: #d4edda; color: #155724; }
            .failed { background: #f8d7da; color: #721c24; }
            .test-result { margin: 10px 0; padding: 10px; border-left: 4px solid #ccc; }
            .test-passed { border-color: #28a745; }
            .test-failed { border-color: #dc3545; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>LiquorPro Mobile App Test Report</h1>
            <p>Generated: ${new Date().toLocaleString()}</p>
        </div>
        
        <div class="stats">
            <div class="stat">
                <h3>Total Tests</h3>
                <p>${testResults.length}</p>
            </div>
            <div class="stat passed">
                <h3>Passed</h3>
                <p>${testResults.filter(t => t.status === 'passed').length}</p>
            </div>
            <div class="stat failed">
                <h3>Failed</h3>
                <p>${testResults.filter(t => t.status === 'failed').length}</p>
            </div>
        </div>
        
        <div class="results">
            ${testResults.map(test => `
                <div class="test-result test-${test.status}">
                    <h4>${test.name}</h4>
                    <p><strong>Status:</strong> ${test.status}</p>
                    <p><strong>Duration:</strong> ${test.duration}ms</p>
                    ${test.error ? `<p><strong>Error:</strong> ${test.error}</p>` : ''}
                </div>
            `).join('')}
        </div>
    </body>
    </html>
    `;

    const reportPath = path.join(appiumConfig.test.reportPath, 'test-report.html');
    fs.writeFileSync(reportPath, html);
  }
};

module.exports = {
  appiumConfig,
  createDriver,
  deviceUtils,
  reportUtils
};