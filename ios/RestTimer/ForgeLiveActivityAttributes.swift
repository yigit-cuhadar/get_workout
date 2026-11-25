import ActivityKit
import Foundation

/// forge_live_activity's attributes, declared exactly as the plugin does
/// (ActivityKit matches the two by name; the extension cannot link the
/// plugin). `json` is the content Dart shows: WorkoutActivityContent.
struct ForgeLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var json: String
  }
}

extension ForgeLiveActivityAttributes.ContentState {
  /// The workout to draw; one that cannot be read shows as an empty one.
  var workout: WorkoutActivityContent {
    WorkoutActivityContent(json: json)
      ?? WorkoutActivityContent(name: "", startedAt: Date(), set: nil, rest: nil)
  }
}
