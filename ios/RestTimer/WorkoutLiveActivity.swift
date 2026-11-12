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
        Spacer()
        WorkoutClock(state: state, rest: rest)
          .font(.title.monospacedDigit())
          .multilineTextAlignment(.trailing)
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
          WorkoutClock(state: state, rest: rest)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let line = detail(state, rest) {
            Text(line).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      } compactLeading: {
        Image(systemName: symbol)
      } compactTrailing: {
        // Wide enough for 30:00 and 1:00:00; scales down beyond.
        WorkoutClock(state: state, rest: rest)
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(width: 56)
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
/// counted up; both by the system.
struct WorkoutClock: View {
  let state: WorkoutActivityAttributes.ContentState
  let rest: WorkoutActivityAttributes.ContentState.Rest?

  var body: some View {
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
