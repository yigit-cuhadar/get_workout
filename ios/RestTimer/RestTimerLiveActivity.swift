import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerBundle: WidgetBundle {
  var body: some Widget {
    RestTimerLiveActivity()
  }
}

/// The running rest on the lock screen and in the Dynamic Island. The
/// countdown is drawn by the system, so it ticks without the app running;
/// the activity's stale date is the rest's end, so a rest that ends while
/// the app is suspended shows its "over" text instead of 0:00.
struct RestTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(context.state.title).font(.headline)
          if let detail = context.state.detail {
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        Spacer()
        RestCountdown(state: context.state, isStale: context.isStale)
          .font(.title.monospacedDigit())
          .multilineTextAlignment(.trailing)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.state.title, systemImage: "timer")
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestCountdown(state: context.state, isStale: context.isStale)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let detail = context.state.detail {
            Text(detail).foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "timer")
      } compactTrailing: {
        // Wide enough for 30:00 (rests stay under 31 min); scales down
        // rather than truncating a longer "over" text.
        RestCountdown(state: context.state, isStale: context.isStale)
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(width: 56)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }
}

/// The time left, counted down by the system, or the "over" text once the
/// rest has ended.
struct RestCountdown: View {
  let state: RestActivityAttributes.ContentState
  let isStale: Bool

  var body: some View {
    let now = Date()
    if isStale || state.endsAt <= now {
      Text(state.over)
    } else {
      // Never an hours part: a rest ends within 30 min.
      Text(timerInterval: now...state.endsAt, countsDown: true, showsHours: false)
    }
  }
}
