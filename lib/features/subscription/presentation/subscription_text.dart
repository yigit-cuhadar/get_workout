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

  /// Under the price on the paywall's plan card: the period, then any free
  /// trial and paid intro price.
  List<String> planCardLines(Plan plan) => [
    switch (plan.period) {
      PlanPeriod.monthly => everyMonths(1),
      PlanPeriod.yearly => everyYears(1),
      PlanPeriod.lifetime => paywallCardOnce,
    },
    if (plan.trial case final trial?) paywallCardTrial(offerPeriod(trial)),
    if (plan.intro case final intro?) introOffer(intro),
  ];

  /// `7 days free, then $39.99 per year`, with any paid intro price
  /// between, or just the price.
  String planOffer(Plan plan) {
    final trial = plan.trial;
    return trial == null
        ? _afterTrial(plan)
        : paywallTrialThen(offerPeriod(trial), _afterTrial(plan));
  }

  /// `$0.99 per month for 3 months` or `$0.99 for 1 month`.
  String introOffer(IntroOffer intro) {
    final period = intro.period;
    final total = offerPeriod(
      OfferPeriod(period.count * intro.cycles, period.unit),
    );
    return intro.cycles == 1
        ? paywallIntroOnce(intro.price, total)
        : paywallIntroEach(intro.price, _every(period), total);
  }

  String offerPeriod(OfferPeriod period) => switch (period.unit) {
    PeriodUnit.day => periodDays(period.count),
    PeriodUnit.week => periodWeeks(period.count),
    PeriodUnit.month => periodMonths(period.count),
    PeriodUnit.year => periodYears(period.count),
  };

  String purchaseButton(Plan plan) {
    final intro = plan.intro;
    return plan.trial != null
        ? paywallStartTrial
        : intro != null
        ? paywallStartIntro(intro.price)
        : plan.period == PlanPeriod.lifetime
        ? paywallBuy
        : paywallSubscribe;
  }

  /// What the store charges and when, as the stores' review guidelines ask.
  List<String> purchaseTerms(Plan plan) {
    if (plan.period == PlanPeriod.lifetime) {
      return [paywallLifetimeTerms(plan.price)];
    }
    final trial = plan.trial;
    final intro = plan.intro;
    return [
      trial != null
          ? paywallTrialTerms(offerPeriod(trial), _afterTrial(plan))
          : intro != null
          ? paywallIntroTerms(introOffer(intro), planPrice(plan))
          : paywallChargeTerms,
      paywallRenewTerms(planPrice(plan)),
    ];
  }

  /// The paid intro price, if any, then the regular price.
  String _afterTrial(Plan plan) {
    final intro = plan.intro;
    return intro == null
        ? planPrice(plan)
        : paywallThen(introOffer(intro), planPrice(plan));
  }

  /// `per month`, `every 2 weeks`.
  String _every(OfferPeriod period) => switch (period.unit) {
    PeriodUnit.day => everyDays(period.count),
    PeriodUnit.week => everyWeeks(period.count),
    PeriodUnit.month => everyMonths(period.count),
    PeriodUnit.year => everyYears(period.count),
  };

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

  /// The state line of the Profile tab's Premium card.
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
