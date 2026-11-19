import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RestTimerBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivity()
  }
}

/// The workout in progress on the lock screen and in the Dynamic Island:
/// the set to do now (its exercise, place, values and the exercise's sets
/// done) with the elapsed time, or, while a rest runs, the rest's
/// countdown, a bar emptying over it and the next set, with −15 s, +15 s
/// and Skip on the lock screen (iOS 17+; they work without opening the
/// app, see WorkoutActivityIntents.swift). Times and bars are drawn by the
/// system, so they run without the app. A rest's end is the activity's
/// stale date, so one that ends while the app is suspended turns back
/// into the workout by itself. A tap elsewhere opens the app on the
/// workout.
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      let state = context.state
      Group {
        if let rest = state.runningRest(isStale: context.isStale) {
          RestCard(rest: rest)
        } else {
          SetCard(state: state)
        }
      }
      .padding(16)
      // Drawn on a dark card in every appearance.
      .environment(\.colorScheme, .dark)
      .activityBackgroundTint(ActivityColors.card)
      .activitySystemActionForegroundColor(.white)
      .widgetURL(WorkoutActivityLink.url)
    } dynamicIsland: { context in
      let state = context.state
      let rest = state.runningRest(isStale: context.isStale)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if let rest {
            Label(rest.title, systemImage: "timer").lineLimit(1)
          } else {
            Label(state.set?.exercise ?? state.name, systemImage: "dumbbell").lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          WorkoutClock(state: state, rest: rest, width: 96)
            .font(rest == nil ? .body.monospacedDigit() : .title2.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let rest {
            VStack(alignment: .leading, spacing: 8) {
              RestBar(rest: rest)
              if let detail = rest.detail {
                SetLine(line: detail).foregroundStyle(.secondary)
              }
            }
          } else if let set = state.set {
            HStack(spacing: 12) {
              Text(set.line).monospacedDigit().lineLimit(1).foregroundStyle(.secondary)
              Spacer(minLength: 0)
              SetDots(done: set.done)
            }
          }
        }
      } compactLeading: {
        IslandMark(rest: rest)
      } compactTrailing: {
        WorkoutClock(state: state, rest: rest, width: 64).monospacedDigit()
      } minimal: {
        IslandMark(rest: rest)
      }
      .widgetURL(WorkoutActivityLink.url)
    }
  }
}

/// The few colours of the activity: its dark card, the muted green of the
/// app's mark and, lighter, of what runs (ring, bar), and the buttons.
enum ActivityColors {
  static let card = Color(red: 30 / 255, green: 34 / 255, blue: 40 / 255).opacity(0.92)
  static let mark = Color(red: 63 / 255, green: 125 / 255, blue: 98 / 255)
  static let running = Color(red: 121 / 255, green: 181 / 255, blue: 151 / 255)
  static let button = Color(red: 58 / 255, green: 65 / 255, blue: 76 / 255)
  static let undone = Color(red: 74 / 255, green: 81 / 255, blue: 92 / 255)
}

/// While a set is due: the app's mark, the exercise's place and the
/// elapsed time on top, the exercise large across the card, the set with
/// its values and, at its end, one dot per set of the exercise. With every
/// set done, the app sends
/// "All sets done" and "Finish in the app" in their place, without dots
/// (LA5 A); the workout's name shows only for content without a set.
struct SetCard: View {
  let state: WorkoutActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        AppMark()
        Text(state.set?.position ?? "").lineLimit(1).foregroundStyle(.secondary)
        Spacer(minLength: 8)
        WorkoutClock(state: state, rest: nil, width: 72)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
      // The name takes the whole width; the dots sit at the end of the set
      // line, which is cut before them.
      VStack(alignment: .leading, spacing: 4) {
        Text(state.set?.exercise ?? state.name).font(.title3.weight(.semibold)).lineLimit(1)
        if let set = state.set {
          HStack(spacing: 12) {
            Text(set.line).font(.subheadline).monospacedDigit().lineLimit(1)
              .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SetDots(done: set.done).fixedSize()
          }
        }
      }
    }
  }
}

/// During a rest: "Rest" and the next set beside the countdown, the bar
/// emptying over the rest, and −15 s, +15 s and Skip (iOS 17+).
struct RestCard: View {
  let rest: WorkoutActivityAttributes.ContentState.Rest

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(rest.title).font(.headline).lineLimit(1)
          if let detail = rest.detail {
            SetLine(line: detail).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        .layoutPriority(1)
        Spacer(minLength: 8)
        RestClock(rest: rest).font(.system(size: 30).monospacedDigit()).frame(width: 96, alignment: .trailing)
      }
      RestBar(rest: rest)
      if #available(iOS 17.0, *) {
        RestButtons(rest: rest)
      }
    }
  }
}

@available(iOS 17.0, *)
struct RestButtons: View {
  let rest: WorkoutActivityAttributes.ContentState.Rest

  var body: some View {
    HStack(spacing: 8) {
      Button(intent: ShortenRestIntent()) { label(rest.shorten, main: false) }
      Button(intent: ExtendRestIntent()) { label(rest.extend, main: false) }
      Button(intent: SkipRestIntent()) { label(rest.skip, main: true) }
    }
    .buttonStyle(.plain)
  }

  private func label(_ text: String, main: Bool) -> some View {
    Text(text)
      .font(.subheadline.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .foregroundStyle(main ? Color.black : Color.white)
      .frame(maxWidth: .infinity, minHeight: 40)
      .background(Capsule().fill(main ? Color.white : ActivityColors.button))
  }
}

/// The app's mark: a dumbbell on its muted green.
struct AppMark: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 7)
      .fill(ActivityColors.mark)
      .frame(width: 28, height: 28)
      .overlay(
        Image(systemName: "dumbbell.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
      )
  }
}

/// The compact and minimal island's symbol: the dumbbell, or during a rest
/// a ring emptying over it.
struct IslandMark: View {
  let rest: WorkoutActivityAttributes.ContentState.Rest?

  var body: some View {
    if let rest {
      ProgressView(
        timerInterval: rest.interval,
        countsDown: true,
        label: { EmptyView() },
        currentValueLabel: { EmptyView() }
      )
      .progressViewStyle(.circular)
      .tint(ActivityColors.running)
    } else {
      Image(systemName: "dumbbell").foregroundStyle(ActivityColors.running)
    }
  }
}

/// A bar emptying over the rest, drawn by the system.
struct RestBar: View {
  let rest: WorkoutActivityAttributes.ContentState.Rest

  var body: some View {
    ProgressView(
      timerInterval: rest.interval,
      countsDown: true,
      label: { EmptyView() },
      currentValueLabel: { EmptyView() }
    )
    .progressViewStyle(.linear)
    .tint(ActivityColors.running)
  }
}

/// One dot per set of the exercise, filled where it is done; narrower when
/// there are many.
struct SetDots: View {
  let done: [Bool]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(done.enumerated()), id: \.offset) { _, done in
        Capsule()
          .fill(done ? Color.white : ActivityColors.undone)
          .frame(width: self.done.count > 5 ? 10 : 18, height: 6)
      }
    }
  }
}

/// A set as the app names it, "Next: Bench Press · set 2 of 3", on one
/// line: a long exercise name ends with "…", the part from the last " · "
/// on is never cut.
struct SetLine: View {
  let line: String

  var body: some View {
    if let split = line.range(of: " · ", options: .backwards) {
      HStack(spacing: 0) {
        Text(line[..<split.lowerBound]).lineLimit(1)
        Text(line[split.lowerBound...]).lineLimit(1).fixedSize()
      }
    } else {
      Text(line).lineLimit(1)
    }
  }
}

/// The rest's time left, counted down by the system. Never an hours part:
/// a rest ends within 30 min.
struct RestClock: View {
  let rest: WorkoutActivityAttributes.ContentState.Rest

  var body: some View {
    let now = Date()
    // The range never runs backwards, which would crash.
    Text(timerInterval: now...max(now, rest.endsAt), countsDown: true, showsHours: false)
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
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
      RestClock(rest: rest)
    } else {
      Text(state.startedAt, style: .timer)
    }
  }
}

extension WorkoutActivityAttributes.ContentState.Rest {
  /// From its start to its end; never backwards, which would crash.
  var interval: ClosedRange<Date> {
    min(startsAt, endsAt)...endsAt
  }
}
