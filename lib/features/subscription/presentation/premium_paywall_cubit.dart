import 'dart:async';

import 'package:forge_purchases/forge_purchases.dart';

import '../domain/paywall_layout.dart';
import '../domain/subscription_usecases.dart';

/// The package's paywall with the yearly plan selected by default, when the
/// offering has one, in this session's [layout]. Logs the A/B test's events:
/// a view once the plans first show to a user without Premium (a
/// subscriber's paywall closes at once), and each purchase.
class PremiumPaywallCubit extends PaywallCubit {
  PremiumPaywallCubit({
    required super.getOffering,
    required super.purchasePlan,
    required super.restorePurchases,
    required GetPaywallLayout getLayout,
    required this._logView,
    required this._logPurchase,
    required this._isPremium,
  }) : layout = getLayout();

  /// Read once, when the paywall opens.
  final PaywallLayout layout;
  final LogPaywallView _logView;
  final LogPaywallPurchase _logPurchase;
  final bool Function() _isPremium;
  bool _viewLogged = false;

  @override
  Future<void> load() async {
    await super.load();
    if (isClosed) return;
    if (state.status == PaywallStatus.ready && !_viewLogged && !_isPremium()) {
      _viewLogged = true;
      unawaited(_logView(layout));
    }
    for (final plan in state.plans) {
      if (plan.period == PlanPeriod.yearly) return select(plan);
    }
  }

  @override
  Future<void> purchase() async {
    final plan = state.selected;
    await super.purchase();
    // An ignored call (busy, nothing loaded) leaves no purchased outcome.
    if (plan != null && state.outcome == PaywallOutcome.purchased) {
      unawaited(_logPurchase(plan: plan.period, layout: layout));
    }
  }
}
