import ActivityKit
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
    registerRestActivity(engineBridge.pluginRegistry)
  }

  /// The running rest as a Live Activity
  /// (lib/features/workout/data/ios_rest_lock_screen.dart): "show" starts
  /// or updates it and answers whether it shows (false with Live
  /// Activities off), "end" removes it. Below iOS 16.2 both do nothing.
  private func registerRestActivity(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "RestActivity") else { return }
    let channel = FlutterMethodChannel(
      name: "getworkout/rest_activity",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(nil)
        return
      }
      switch call.method {
      case "show":
        guard let args = call.arguments as? [String: Any],
          let endsAt = args["endsAt"] as? NSNumber,
          let title = args["title"] as? String,
          let over = args["over"] as? String
        else {
          result(FlutterError(code: "bad-args", message: "show needs endsAt, title and over", details: nil))
          return
        }
        let state = RestActivityAttributes.ContentState(
          endsAt: Date(timeIntervalSince1970: endsAt.doubleValue / 1000),
          title: title,
          detail: args["detail"] as? String,
          over: over
        )
        Task { @MainActor in
          do {
            result(try await RestActivity.show(state))
          } catch {
            result(FlutterError(code: "show-failed", message: error.localizedDescription, details: nil))
          }
        }
      case "end":
        Task { @MainActor in
          await RestActivity.end()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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

/// One Live Activity for the running rest. Its stale date is the rest's
/// end, so it shows the rest as over by itself when the app is suspended
/// then; without push updates the app ends it only when it runs again.
@available(iOS 16.2, *)
enum RestActivity {
  /// Whether it shows; false with Live Activities turned off. Throws when
  /// the app may not start one (not in front).
  static func show(_ state: RestActivityAttributes.ContentState) async throws -> Bool {
    let content = ActivityContent(state: state, staleDate: state.endsAt)
    let running = Activity<RestActivityAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
    if let current = running.first {
      await current.update(content)
      for extra in running.dropFirst() {
        await extra.end(nil, dismissalPolicy: .immediate)
      }
      return true
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
    _ = try Activity<RestActivityAttributes>.request(
      attributes: RestActivityAttributes(),
      content: content,
      pushType: nil
    )
    return true
  }

  static func end() async {
    for activity in Activity<RestActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
