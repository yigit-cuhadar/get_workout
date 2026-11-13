/// How the paywall shows its plans: the two arms of an A/B test, each with
/// its Remote Config and analytics [code].
enum PaywallLayout {
  /// A: one row per plan. The default.
  list('a'),

  /// B: one card per plan, side by side.
  cards('b');

  const PaywallLayout(this.code);

  final String code;
}

/// The Remote Config key holding the layout's code; [paywallLayoutDefault]
/// until the server sends one.
const paywallLayoutKey = 'paywall_layout';
const paywallLayoutDefault = 'a';

/// Debug builds only: the layout picked in the Profile tab's debug rows,
/// over Remote Config's; null follows Remote Config. In memory until
/// restart.
class PaywallLayoutOverride {
  PaywallLayout? layout;
}
