import ActivityKit
import Foundation

/// The running rest's Live Activity. Compiled into both the Runner, which
/// starts, updates and ends it (AppDelegate.swift), and the RestTimer
/// extension, which draws it; ActivityKit matches the two by this type.
/// Every text comes from the app, in the user's language.
@available(iOS 16.1, *)
struct RestActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// The system counts down to it by itself.
    var endsAt: Date
    var title: String
    /// The next set; nil when none is left.
    var detail: String?
    /// Shown from endsAt on, when the app could not end the activity.
    var over: String
  }
}
