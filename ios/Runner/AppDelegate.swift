import ActivityKit
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Kept here: the registrar does not keep scene delegates alive.
  private var workoutActivityTaps: WorkoutActivityTaps?

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
    registerWorkoutActivity(engineBridge.pluginRegistry)
  }

  /// The workout in progress as a Live Activity
  /// (lib/features/workout/data/ios_workout_lock_screen.dart): "show"
  /// starts or updates it and answers whether it shows (false with Live
  /// Activities off), "end" removes it, "takeTap" answers whether it was
  /// tapped since last asked. Below iOS 16.2 none shows.
  private func registerWorkoutActivity(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "WorkoutActivity") else { return }
    let channel = FlutterMethodChannel(
      name: "getworkout/workout_activity",
      binaryMessenger: registrar.messenger()
    )
    let taps = WorkoutActivityTaps(channel: channel)
    workoutActivityTaps = taps
    registrar.addSceneDelegate(taps)
    channel.setMethodCallHandler { call, result in
      if call.method == "takeTap" {
        result(taps.take())
        return
      }
      guard #available(iOS 16.2, *) else {
        result(nil)
        return
      }
      switch call.method {
      case "show":
        guard let args = call.arguments as? [String: Any],
          let name = args["name"] as? String,
          let startedAt = args["startedAt"] as? NSNumber
        else {
          result(FlutterError(code: "bad-args", message: "show needs name and startedAt", details: nil))
          return
        }
        var rest: WorkoutActivityAttributes.ContentState.Rest?
        if let endsAt = args["restEndsAt"] as? NSNumber, let title = args["restTitle"] as? String {
          rest = .init(endsAt: date(endsAt), title: title, detail: args["restDetail"] as? String)
        }
        let state = WorkoutActivityAttributes.ContentState(
          name: name,
          startedAt: date(startedAt),
          current: args["current"] as? String,
          rest: rest
        )
        Task { @MainActor in
          do {
            result(try await WorkoutActivity.show(state))
          } catch {
            result(FlutterError(code: "show-failed", message: error.localizedDescription, details: nil))
          }
        }
      case "end":
        Task { @MainActor in
          await WorkoutActivity.end()
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

/// Milliseconds since the epoch from Dart.
private func date(_ milliseconds: NSNumber) -> Date {
  Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
}

/// One Live Activity for the workout in progress. During a rest its stale
/// date is the rest's end, so it shows the workout again by itself when the
/// app is suspended then. Without push updates the app updates and ends it
/// only while it runs. iOS ends it after 8 hours; the next show then starts
/// a new one.
@available(iOS 16.2, *)
enum WorkoutActivity {
  /// Whether it shows; false with Live Activities turned off. Throws when
  /// the app may not start one (not in front).
  static func show(_ state: WorkoutActivityAttributes.ContentState) async throws -> Bool {
    let content = ActivityContent(state: state, staleDate: state.rest?.endsAt)
    let running = Activity<WorkoutActivityAttributes>.activities.filter {
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
    _ = try Activity<WorkoutActivityAttributes>.request(
      attributes: WorkoutActivityAttributes(),
      content: content,
      pushType: nil
    )
    return true
  }

  static func end() async {
    for activity in Activity<WorkoutActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}

/// Taps on the activity: its widgetURL opens the app with
/// WorkoutActivityLink.url, here, not through Flutter's deep linking
/// (FlutterDeepLinkingEnabled is off). A tap is kept until Dart takes it,
/// so one that launched the app before Dart listened is not lost; Dart is
/// told to take it now too.
final class WorkoutActivityTaps: NSObject, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel
  private var tapped = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  /// Whether it was tapped since last asked.
  func take() -> Bool {
    defer { tapped = false }
    return tapped
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    // Only noted: the launch is left to the others.
    _ = open(connectionOptions?.urlContexts ?? [])
    return false
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    open(URLContexts)
  }

  private func open(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard contexts.contains(where: { $0.url == WorkoutActivityLink.url }) else { return false }
    tapped = true
    channel.invokeMethod("tapped", arguments: nil)
    return true
  }
}
