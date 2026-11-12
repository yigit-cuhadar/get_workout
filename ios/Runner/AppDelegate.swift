import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: deliver and report taps of local
    // notifications.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupExclusion(engineBridge.pluginRegistry)
  }

  /// Progress photos live only in the app and in its own backup, so their
  /// folder is kept out of iCloud and device backups
  /// (lib/features/body/data/backup_exclusion.dart).
  private func registerBackupExclusion(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "BackupExclusion") else { return }
    let channel = FlutterMethodChannel(
      name: "getworkout/backup_exclusion",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "exclude", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "exclude-failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
