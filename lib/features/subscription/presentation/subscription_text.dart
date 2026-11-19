import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/paywall_layout.dart';
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

  /// [plan] worded for the paywall's [layout]; [bestValue] tags a row.
  SubscriptionPlan paywallPlan(
    Plan plan,
    PaywallLayout layout, {
    required bool bestValue,
  }) {
    final terms = purchaseTerms(plan).join(' ');
    final trial = plan.trial;
    return switch (layout) {
      PaywallLayout.list => SubscriptionPlan(
        name: planName(plan),
        price: _planPriceShort(plan),
        terms: terms,
        tag: bestValue ? paywallBestValue : null,
      ),
      PaywallLayout.cards => SubscriptionPlan(
        name: planName(plan),
        price: plan.price,
        terms: terms,
        detail: trial != null
            ? paywallCardTrial(offerPeriod(trial))
            : plan.intro != null
            ? introOffer(plan.intro!)
            : switch (plan.period) {
                PlanPeriod.monthly => paywallBilledMonthly,
                PlanPeriod.yearly => paywallBilledYearly,
                PlanPeriod.lifetime => paywallCardOnce,
              },
      ),
      PaywallLayout.single => SubscriptionPlan(
        name: trial == null
            ? planName(plan)
            : paywallPlanTrial(
                planName(plan),
                paywallCardTrial(offerPeriod(trial)),
              ),
        price: _planPriceShort(plan),
        terms: terms,
        detail: plan.period == PlanPeriod.yearly
            ? paywallMonthlyEquivalent(
                NumberFormat.simpleCurrency(
                  locale: localeName,
                  name: plan.currencyCode,
                ).format(plan.priceAmount / 12),
              )
            : null,
      ),
    };
  }

  /// The single layout's link to [plan]: `See monthly plan`.
  String paywallSeePlan(Plan plan) => switch (plan.period) {
    PlanPeriod.monthly => paywallSeeMonthly,
    PlanPeriod.yearly => paywallSeeYearly,
    PlanPeriod.lifetime => paywallSeeLifetime,
  };

  /// `$39.99 / year`, in a plan's box.
  String _planPriceShort(Plan plan) => switch (plan.period) {
    PlanPeriod.monthly => paywallPriceMonth(plan.price),
    PlanPeriod.yearly => paywallPriceYear(plan.price),
    PlanPeriod.lifetime => paywallOnce(plan.price),
  };

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
    final trial = plan.trial;
    return trial != null
        ? paywallStartTrial(_trialLength(trial))
        : intro != null
        ? paywallStartIntro(intro.price)
        : plan.period == PlanPeriod.lifetime
        ? paywallBuy
        : paywallSubscribe;
  }

  /// `7-day`, before "free trial".
  String _trialLength(OfferPeriod period) => switch (period.unit) {
    PeriodUnit.day => trialLengthDays(period.count),
    PeriodUnit.week => trialLengthWeeks(period.count),
    PeriodUnit.month => trialLengthMonths(period.count),
    PeriodUnit.year => trialLengthYears(period.count),
  };

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

  /// The title of the Profile tab's Premium card; null for a free user,
  /// whose card says what Premium is instead.
  String? subscriptionState(SubscriptionSummary summary) => switch (summary) {
    SubscriptionChecking() => premiumRowChecking,
    SubscriptionFree() => null,
    SubscriptionBillingIssue() => premiumRowBillingIssue,
    SubscriptionLifetime() => premiumRowLifetime,
    SubscriptionTrial(:final date) => premiumRowTrial(_date(date)),
    SubscriptionRenews(:final date) => premiumRowRenews(_date(date)),
    SubscriptionEnds(:final date) => premiumRowEnds(_date(date)),
  };

  /// `Nov 20`, with the year only when it is not this one.
  String _date(DateTime value) {
    final local = value.toLocal();
    final format = local.year == DateTime.now().year
        ? DateFormat.MMMd(localeName)
        : DateFormat.yMMMd(localeName);
    return format.format(local);
  }
}
