import AppIntents
import Foundation

/// What a rest button on the Live Activity does; the names are Dart's
/// (LockScreenRestAction).
enum RestAction: String {
  case shorten, extend, skip
}

/// Where the rest buttons' intents go. Compiled into both targets: the
/// extension draws the buttons, and as Live Activity intents they run in
/// the app's process, where the Runner sets [handler] at launch
/// (AppDelegate.swift); the extension never sets it.
enum RestActions {
  @MainActor static var handler: ((RestAction) async -> Void)?

  @MainActor static func perform(_ action: RestAction) async {
    await handler?(action)
  }
}

@available(iOS 17.0, *)
struct ShortenRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Shorten rest"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActions.perform(.shorten)
    return .result()
  }
}

@available(iOS 17.0, *)
struct ExtendRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Extend rest"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActions.perform(.extend)
    return .result()
  }
}

@available(iOS 17.0, *)
struct SkipRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Skip rest"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActions.perform(.skip)
    return .result()
  }
}
