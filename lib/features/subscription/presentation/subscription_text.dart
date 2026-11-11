import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import 'subscription_summary.dart';

extension SubscriptionText on AppLocalizations {
  String planName(Plan plan) => switch (plan.period) {
    PlanPeriod.monthly => paywallPlanMonthly,
    PlanPeriod.yearly => paywallPlanYearly,
    PlanPeriod.lifetime => paywallPlanLifetime,
  };

  /// The store's price string as given, with its period: `$39.99 per year`.
  String planPrice(Plan plan) => switch (plan.period) {
    PlanPeriod.monthly => paywallPerMonth(plan.price),
    PlanPeriod.yearly => paywallPerYear(plan.price),
    PlanPeriod.lifetime => paywallOnce(plan.price),
  };

  /// `7 days free, then $39.99 per year`, or just the price.
  String planOffer(Plan plan) {
    final trial = plan.trial;
    return trial == null
        ? planPrice(plan)
        : paywallTrialThen(offerPeriod(trial), planPrice(plan));
  }

  String offerPeriod(OfferPeriod period) => switch (period.unit) {
    PeriodUnit.day => periodDays(period.count),
    PeriodUnit.week => periodWeeks(period.count),
    PeriodUnit.month => periodMonths(period.count),
    PeriodUnit.year => periodYears(period.count),
  };

  String purchaseButton(Plan plan) => plan.trial != null
      ? paywallStartTrial
      : plan.period == PlanPeriod.lifetime
      ? paywallBuy
      : paywallSubscribe;

  /// What the store charges and when, as the stores' review guidelines ask.
  List<String> purchaseTerms(Plan plan) {
    if (plan.period == PlanPeriod.lifetime) {
      return [paywallLifetimeTerms(plan.price)];
    }
    final trial = plan.trial;
    return [
      trial == null
          ? paywallChargeTerms
          : paywallTrialTerms(offerPeriod(trial), planPrice(plan)),
      paywallRenewTerms(planPrice(plan)),
    ];
  }

  String purchaseError(Failure failure) => switch (failure) {
    NetworkFailure() => errorNetwork,
    PurchaseFailure(reason: PurchaseFailureReason.storeUnavailable) =>
      paywallUnavailable,
    PurchaseFailure(reason: PurchaseFailureReason.productNotAvailable) =>
      paywallProductUnavailable,
    PurchaseFailure(reason: PurchaseFailureReason.alreadyOwned) =>
      paywallAlreadyOwned,
    _ => errorGeneric,
  };

  /// The Profile tab's Premium row.
  String subscriptionSummary(SubscriptionSummary summary) => switch (summary) {
    SubscriptionChecking() => premiumRowChecking,
    SubscriptionFree() => premiumRowFree,
    SubscriptionBillingIssue() => premiumRowBillingIssue,
    SubscriptionLifetime() => premiumRowLifetime,
    SubscriptionTrial(:final date) => premiumRowTrial(_date(date)),
    SubscriptionRenews(:final date) => premiumRowRenews(_date(date)),
    SubscriptionEnds(:final date) => premiumRowEnds(_date(date)),
  };

  String _date(DateTime value) =>
      DateFormat.yMMMd(localeName).format(value.toLocal());
}
