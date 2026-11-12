import ActivityKit
import Foundation

/// The workout in progress as a Live Activity. Compiled into both the
/// Runner, which starts, updates and ends it (AppDelegate.swift), and the
/// RestTimer extension, which draws it; ActivityKit matches the two by this
/// type. Every text comes from the app, in the user's language.
@available(iOS 16.1, *)
struct WorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var name: String
    /// The elapsed time counts up from it.
    var startedAt: Date
    /// The set to do now; nil when every set is done.
    var current: String?
    /// The running rest; shown until its end only, so the workout shows
    /// again by itself when the app cannot update it then.
    var rest: Rest?

    struct Rest: Codable, Hashable {
      /// The system counts down to it by itself; also the stale date.
      var endsAt: Date
      var title: String
      /// The next set; nil when none is left.
      var detail: String?
    }

    /// The rest while it runs; nil from its end on, when the activity is
    /// stale.
    func runningRest(isStale: Bool) -> Rest? {
      guard let rest, !isStale, rest.endsAt > Date() else { return nil }
      return rest
    }
  }
}

/// Opens the app on the workout: the activity's widgetURL, handled by the
/// Runner (WorkoutActivityTaps in AppDelegate.swift).
enum WorkoutActivityLink {
  static let url = URL(string: "getworkout://workout")!
}
