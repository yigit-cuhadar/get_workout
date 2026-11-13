import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivity()
  }
}

/// The workout in progress on the lock screen and in the Dynamic Island:
/// its name, elapsed time and set to do now, or, while a rest runs, the
/// rest's countdown and the next set. Times are drawn by the system, so
/// they run without the app. A rest's end is the activity's stale date, so
/// one that ends while the app is suspended turns back into the workout by
/// itself. A tap opens the app on the workout.
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      let state = context.state
      let rest = state.runningRest(isStale: context.isStale)
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(rest?.title ?? state.name).font(.headline).lineLimit(1)
          if let line = detail(state, rest) {
            Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        .layoutPriority(1)
        Spacer(minLength: 8)
        WorkoutClock(state: state, rest: rest, width: 120)
          .font(.title.monospacedDigit())
      }
      .padding()
      .widgetURL(WorkoutActivityLink.url)
    } dynamicIsland: { context in
      let state = context.state
      let rest = state.runningRest(isStale: context.isStale)
      let symbol = rest == nil ? "dumbbell" : "timer"
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(rest?.title ?? state.name, systemImage: symbol).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          WorkoutClock(state: state, rest: rest, width: 80).monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let line = detail(state, rest) {
            Text(line).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      } compactLeading: {
        Image(systemName: symbol)
      } compactTrailing: {
        WorkoutClock(state: state, rest: rest, width: 64).monospacedDigit()
      } minimal: {
        Image(systemName: symbol)
      }
      .widgetURL(WorkoutActivityLink.url)
    }
  }

  /// The next set during a rest, else the set to do now.
  private func detail(
    _ state: WorkoutActivityAttributes.ContentState,
    _ rest: WorkoutActivityAttributes.ContentState.Rest?
  ) -> String? {
    rest == nil ? state.current : rest?.detail
  }
}

/// The rest's time left, counted down, or else the workout's elapsed time,
/// counted up; both by the system. A timer text takes all the width it is
/// offered, so it gets a fixed `width`, wide enough for 1:00:00, and scales
/// down beyond.
struct WorkoutClock: View {
  let state: WorkoutActivityAttributes.ContentState
  let rest: WorkoutActivityAttributes.ContentState.Rest?
  let width: CGFloat

  var body: some View {
    time
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(width: width, alignment: .trailing)
  }

  @ViewBuilder private var time: some View {
    if let rest {
      let now = Date()
      // Never an hours part: a rest ends within 30 min. The range never
      // runs backwards, which would crash.
      Text(timerInterval: now...max(now, rest.endsAt), countsDown: true, showsHours: false)
    } else {
      Text(state.startedAt, style: .timer)
    }
  }
}
