import 'dart:async';

import 'package:forge_purchases/forge_purchases.dart';

import '../../analytics/domain/analytics.dart';
import '../domain/paywall_layout.dart';
import '../domain/paywall_moment.dart';
import '../domain/subscription_usecases.dart';

/// The package's paywall in this session's [layout]; given
/// [GetPaywallOffering], the yearly plan comes first and is selected. Logs
/// the A/B test's events: a view once the plans first show to a user
/// without Premium (a subscriber's paywall closes at once), and each
/// purchase; and each restore and the user closing it. Opened at [moment]
/// (null: by the user), see [closable].
class PremiumPaywallCubit extends PaywallCubit {
  PremiumPaywallCubit({
    required super.getOffering,
    required super.purchasePlan,
    required super.restorePurchases,
    required GetPaywallLayout getLayout,
    required this._analytics,
    required this._isPremium,
    this.moment,
  }) : layout = getLayout();

  final PaywallMoment? moment;

  /// Whether the user can close the paywall. Always, but at a moment the
  /// offering decides ([PaywallMoment.offeringDecides]), where its metadata
  /// does ([offeringDismissible]): not until it is known, and always when it
  /// could not be loaded.
  bool get closable =>
      !(moment?.offeringDecides ?? false) ||
      state.status == PaywallStatus.loadFailed ||
      state.status != PaywallStatus.loading &&
          offeringDismissible(state.metadata);

  /// Read once, when the paywall opens.
  final PaywallLayout layout;
  final Analytics _analytics;
  final bool Function() _isPremium;
  bool _viewLogged = false;

  @override
  Future<void> load() async {
    await super.load();
    if (isClosed) return;
    if (state.status == PaywallStatus.ready && !_viewLogged && !_isPremium()) {
      _viewLogged = true;
      unawaited(_analytics.paywallView(layout: layout, moment: moment));
    }
  }

  @override
  Future<void> purchase() async {
    final plan = state.selected;
    await super.purchase();
    // An ignored call (busy, nothing loaded) leaves no purchased outcome.
    if (plan != null && state.outcome == PaywallOutcome.purchased) {
      unawaited(
        _analytics.paywallPurchase(
          plan: plan.period,
          layout: layout,
          moment: moment,
        ),
      );
    }
  }

  @override
  Future<void> restore() async {
    await super.restore();
    switch (state.outcome) {
      case PaywallOutcome.restored:
        unawaited(_analytics.restore(premium: true));
      case PaywallOutcome.nothingToRestore:
        unawaited(_analytics.restore(premium: false));
      case _:
    }
  }

  /// The user closed the paywall without Premium.
  void dismissed() => unawaited(_analytics.paywallClose(moment));
}
