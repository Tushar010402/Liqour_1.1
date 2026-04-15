import Flutter
import UIKit
import FirebaseCore
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase NATIVELY before Flutter plugins
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // Set phone auth test mode ONLY on simulator (not real devices)
    // Real devices use APNs silent push for verification
    #if DEBUG && targetEnvironment(simulator)
    Auth.auth().settings?.isAppVerificationDisabledForTesting = true
    print("✅ [Native] Firebase Phone Auth: test mode enabled (simulator)")
    #endif

    // Register Flutter plugins (will reuse existing Firebase instance)
    GeneratedPluginRegistrant.register(with: self)

    // Setup push notifications delegate
    UNUserNotificationCenter.current().delegate = self

    // Request notification permissions
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { _, _ in }
    )
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Forward APNs device token to Firebase Auth (required for phone auth)
  override func application(_ application: UIApplication,
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Pass to Firebase Auth for silent push verification
    Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    // Also pass to parent for FCM
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Forward push notifications to Firebase Auth (handles silent verification)
  override func application(_ application: UIApplication,
                          didReceiveRemoteNotification notification: [AnyHashable: Any],
                          fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Let Firebase Auth handle its verification notifications
    if Auth.auth().canHandleNotification(notification) {
      completionHandler(.noData)
      return
    }
    // Pass to parent for other notifications
    super.application(application, didReceiveRemoteNotification: notification, fetchCompletionHandler: completionHandler)
  }

  // Handle URL redirects (reCAPTCHA verification callback)
  override func application(_ app: UIApplication, open url: URL,
                          options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if Auth.auth().canHandle(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
