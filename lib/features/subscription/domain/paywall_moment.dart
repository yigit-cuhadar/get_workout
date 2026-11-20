import '../../settings/domain/user_settings.dart';

/// The moments the app shows the paywall by itself.
enum PaywallMoment {
  /// After onboarding's program suggestion.
  onboarding(Tip.onboardingPaywall),

  /// When the user leaves the summary of their first workout ever.
  firstWorkout(Tip.firstWorkoutPaywall),

  /// Every app open of a free user while the offering is hard, until they
  /// have Premium (`HardPaywallGate`).
  appOpen(null);

  const PaywallMoment(this.tip);

  /// Marks a moment shown once per user in `settings.seenTips`; null for
  /// one that is not once.
  final Tip? tip;

  /// Whether the store setup can make this moment's paywall not
  /// dismissible ([offeringDismissible]); every other paywall always is.
  bool get offeringDecides => this != firstWorkout;
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
