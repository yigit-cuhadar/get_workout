import ActivityKit
import Foundation

/// The workout in progress as a Live Activity. Compiled into both the
/// Runner, which starts, updates and ends it (AppDelegate.swift), and the
/// RestTimer extension, which draws it; ActivityKit matches the two by this
/// type. Every text comes from the app, in the user's language.
@available(iOS 16.1, *)
struct WorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// Shown where no set is left to do.
    var name: String
    /// The elapsed time counts up from it.
    var startedAt: Date
    /// The set to do now; nil when every set is done.
    var set: SetToDo?
    /// The running rest; shown until its end only, so the workout shows
    /// again by itself when the app cannot update it then.
    var rest: Rest?

    struct SetToDo: Codable, Hashable {
      /// "Bench Press".
      var exercise: String
      /// "Exercise 3 of 6".
      var position: String
      /// "Set 2 of 3 · 80 kg × 8".
      var line: String
      /// One per set of the exercise, true where it is done.
      var done: [Bool]
    }

    struct Rest: Codable, Hashable {
      /// When the whole rest, time added included, began.
      var startsAt: Date
      /// The system counts down to it by itself; also the stale date.
      var endsAt: Date
      var title: String
      /// The next set; nil when none is left.
      var detail: String?
      /// The buttons' labels: −15 s, +15 s, Skip.
      var shorten: String
      var extend: String
      var skip: String
    }

    /// The rest while it runs; nil from its end on, when the activity is
    /// stale.
    func runningRest(isStale: Bool) -> Rest? {
      guard let rest, !isStale, rest.endsAt > Date() else { return nil }
      return rest
    }

    /// The rest moved as [action] does (RestAction), the way the app moves
    /// it (lib/features/workout/domain/rest.dart), so the activity shows it
    /// before the app does: 15 s more, at most 30 min ahead; 15 s less,
    /// ending it when less is left; or ended.
    func moved(_ action: RestAction, now: Date = Date()) -> Self {
      guard var rest = runningRest(isStale: false) else { return self }
      var state = self
      switch action {
      case .shorten:
        rest.endsAt -= 15
      case .extend:
        rest.endsAt = min(rest.endsAt + 15, now + 30 * 60)
      case .skip:
        rest.endsAt = now
      }
      state.rest = rest.endsAt > now ? rest : nil
      return state
    }
  }
}

/// Opens the app on the workout: the activity's widgetURL, handled by the
/// Runner (WorkoutActivityTaps in AppDelegate.swift).
enum WorkoutActivityLink {
  static let url = URL(string: "getworkout://workout")!
}
