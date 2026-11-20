import '../../settings/domain/user_settings.dart';

/// The moments the app offers the paywall by itself, each once per user,
/// marked shown as its [tip] in `settings.seenTips`.
enum PaywallMoment {
  /// After onboarding's program suggestion. The only moment the store setup
  /// can make not dismissible (see [offeringDismissible]).
  onboarding(Tip.onboardingPaywall),

  /// When the user leaves the summary of their first workout ever.
  firstWorkout(Tip.firstWorkoutPaywall);

  const PaywallMoment(this.tip);

  final Tip tip;
}

/// Whether [moment] shows now: only to a user known to be free ([premium]
/// false; null while unknown) whose settings are known ([seen] non-null)
/// and who has not had it yet.
bool paywallMomentDue(
  PaywallMoment moment, {
  required bool? premium,
  required Set<Tip>? seen,
}) => premium == false && seen != null && !seen.contains(moment.tip);

/// The store setup's offering metadata key that makes the paywall hard.
const dismissibleKey = 'dismissible';

/// Whether the offering's [metadata] lets its paywall be closed: true
/// unless [dismissibleKey] is false (a JSON bool, or the string "false").
bool offeringDismissible(Map<String, Object?> metadata) {
  final value = metadata[dismissibleKey];
  return value != false && value != 'false';
}
