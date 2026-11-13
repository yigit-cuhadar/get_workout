import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';

import 'paywall_layout.dart';

/// This session's paywall layout: Remote Config's, A for an unknown or
/// empty value; a debug build's [PaywallLayoutOverride] wins.
class GetPaywallLayout {
  const GetPaywallLayout(this._config, [this._override]);
  final RemoteConfigRepository _config;
  final PaywallLayoutOverride? _override;

  PaywallLayout call() {
    if (_override?.layout case final layout?) return layout;
    final code = _config.getString(paywallLayoutKey);
    return PaywallLayout.values.firstWhere(
      (layout) => layout.code == code,
      orElse: () => PaywallLayout.list,
    );
  }
}

/// The A/B test's activation event: the paywall showed its plans.
class LogPaywallView {
  const LogPaywallView(this._telemetry);
  final Telemetry _telemetry;

  Future<void> call(PaywallLayout layout) =>
      _telemetry.logEvent('paywall_view', {'layout': layout.code});
}

/// The A/B test's goal: a plan bought, or its trial started, on the
/// paywall. The plan is its period, the same on both stores (their product
/// ids differ).
class LogPaywallPurchase {
  const LogPaywallPurchase(this._telemetry);
  final Telemetry _telemetry;

  Future<void> call({
    required PlanPeriod plan,
    required PaywallLayout layout,
  }) => _telemetry.logEvent('paywall_purchase', {
    'plan': plan.name,
    'layout': layout.code,
  });
}
