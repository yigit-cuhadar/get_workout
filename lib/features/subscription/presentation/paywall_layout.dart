/// How the paywall shows its plans; the two arms of a planned A/B test.
enum PaywallLayout {
  /// A: one row per plan.
  list,

  /// B: one card per plan, side by side.
  cards,
}

/// This device's paywall layout: A until users are assigned to an arm.
/// Debug builds switch it from the Profile tab's debug rows.
class PaywallLayoutChoice {
  PaywallLayout layout = PaywallLayout.list;
}
