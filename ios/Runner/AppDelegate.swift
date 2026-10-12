import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Why this app has to ask for the APNs device token itself.
    //
    // FlutterFire normally does it. FLTFirebaseMessagingPlugin registers for
    // remote notifications from its UIApplicationDidFinishLaunchingNotification
    // observer, but behind a guard:
    //
    //     if ([FIRMessaging messaging].isAutoInitEnabled) {
    //       [self registerForRemoteNotifications];
    //     }
    //
    // That guard needs a configured default FirebaseApp. On iOS, firebase_core
    // configures one natively only when [FIROptions defaultOptions] finds a
    // GoogleService-Info.plist *in the app bundle*. This app deliberately has
    // none: the Firebase configuration arrives through --dart-define and is
    // applied by Firebase.initializeApp() from Dart (see
    // ios/Firebase/<env>/GoogleService-Info.plist, gitignored and never added
    // to the Runner target, and codemagic.yaml's --dart-define block).
    //
    // So at launch there is no default app yet, [FIRMessaging messaging]
    // returns nil, `nil.isAutoInitEnabled` is NO, and the registration is
    // skipped. It is never retried: setupNotificationHandling runs once, and
    // the plugin's didReinitializeFirebaseCore does nothing. Without that one
    // call iOS never contacts Apple, the device token never exists,
    // getAPNSToken() answers nil forever, getToken() throws
    // `apns-token-not-set` forever, and not one iPhone can register for
    // notifications — which is exactly what adfoot-production showed: no iOS
    // device had ever stored an FCM token, while Android worked throughout.
    //
    // Calling it here costs nothing and prompts nobody: registerForRemoteNotifications
    // is the APNs round trip, not the permission dialog — that one belongs to
    // UNUserNotificationCenter, and NotificationService.askPermissionAndUpdateToken
    // still owns it. A token obtained before the user accepts is simply held;
    // the plugin stashes it in `_apnsToken` and installs it on FIRMessaging via
    // ensureAPNSTokenSetting, which runs ahead of every method call Dart makes.
    //
    // Deferred by one main-queue turn on purpose. The plugin installs itself as
    // the APNs delegate interceptor from the DidFinishLaunching *notification*,
    // which UIKit posts only after this method returns. Registering inline would
    // start the round trip before the interceptor exists; one turn later the
    // ordering is a guarantee rather than a bet on APNs being slower than a run
    // loop.
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
