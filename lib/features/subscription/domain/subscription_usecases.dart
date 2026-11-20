import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';

import 'paywall_layout.dart';
import 'paywall_moment.dart';

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

/// The store's offering with yearly before monthly, as the paywall shows
/// them whatever order the store gives, its metadata and its id.
class GetPaywallOffering extends GetOffering {
  const GetPaywallOffering(super.repository);

  static const _order = [
    PlanPeriod.yearly,
    PlanPeriod.monthly,
    PlanPeriod.lifetime,
  ];

  @override
  Future<Result<Offering>> call([NoParams params = const NoParams()]) async =>
      (await super.call(params)).map(
        (offering) => Offering(
          [...offering.plans]..sort(
            (a, b) =>
                _order.indexOf(a.period).compareTo(_order.indexOf(b.period)),
          ),
          metadata: offering.metadata,
          id: offering.id,
        ),
      );
}

/// The free trial the paywall offers first; null when no plan has one.
class GetPremiumTrial {
  const GetPremiumTrial(this._offering);
  final GetPaywallOffering _offering;

  Future<Result<OfferPeriod?>> call() async => (await _offering()).map(
    (offering) => offering.plans.map((plan) => plan.trial).nonNulls.firstOrNull,
  );
}

/// Whether the current offering's paywall cannot be closed: its metadata
/// says it is not [offeringDismissible].
class GetOfferingHard {
  const GetOfferingHard(this._offering);
  final GetPaywallOffering _offering;

  Future<Result<bool>> call() async => (await _offering()).map(
    (offering) => !offeringDismissible(offering.metadata),
  );
}
