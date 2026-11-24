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

  /// [plan] worded for the paywall's [layout]. Beside a [monthly] plan, a
  /// yearly row says what it costs a month and what it saves. A win-back
  /// offer (W2) tags the plan in every layout and takes the trial's place
  /// in its lines.
  SubscriptionPlan paywallPlan(
    Plan plan,
    PaywallLayout layout, {
    Plan? monthly,
  }) {
    final terms = purchaseTerms(plan).join(' ');
    final trial = plan.trial;
    final winBack = plan.winBack == null ? null : _winBackOffer(plan.winBack!);
    final offer = winBack == null ? null : paywallWinBackTag(winBack);
    return switch (layout) {
      PaywallLayout.list => SubscriptionPlan(
        name: planName(plan),
        price: winBack == null
            ? _planPriceShort(plan)
            : paywallThen(winBack, _planPriceShort(plan)),
        terms: terms,
        detail: plan.period == PlanPeriod.yearly
            ? paywallAMonth(_perMonth(plan))
            : null,
        tag: switch ((plan.period, monthly)) {
          (PlanPeriod.yearly, final monthly?) when _saving(plan, monthly) > 0 =>
            paywallSave(_saving(plan, monthly)),
          _ => null,
        },
        offer: offer,
      ),
      PaywallLayout.cards => SubscriptionPlan(
        name: planName(plan),
        price: plan.price,
        terms: terms,
        offer: offer,
        detail:
            winBack ??
            (trial != null
                ? paywallCardTrial(offerPeriod(trial))
                : plan.intro != null
                ? introOffer(plan.intro!)
                : switch (plan.period) {
                    PlanPeriod.monthly => paywallBilledMonthly,
                    PlanPeriod.yearly => paywallBilledYearly,
                    PlanPeriod.lifetime => paywallCardOnce,
                  }),
      ),
      PaywallLayout.single => SubscriptionPlan(
        name: winBack != null
            ? paywallPlanTrial(planName(plan), winBack)
            : trial == null
            ? planName(plan)
            : paywallPlanTrial(
                planName(plan),
                paywallCardTrial(offerPeriod(trial)),
              ),
        offer: offer,
        price: _planPriceShort(plan),
        terms: terms,
        detail: plan.period == PlanPeriod.yearly
            ? paywallMonthlyEquivalent(_perMonth(plan))
            : null,
      ),
    };
  }

  /// A yearly [plan]'s price a month, in its currency: `$3.33`.
  String _perMonth(Plan plan) => NumberFormat.simpleCurrency(
    locale: localeName,
    name: plan.currencyCode,
  ).format(plan.priceAmount / 12);

  /// How much a yearly [plan] saves against twelve months of [monthly], in
  /// whole percent.
  int _saving(Plan plan, Plan monthly) =>
      ((1 - plan.priceAmount / (monthly.priceAmount * 12)) * 100).floor();

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

  /// A win-back offer: `1 month free` or `$0.99 for 1 month`.
  String _winBackOffer(WinBackOffer offer) => switch (offer) {
    WinBackOffer(free: final free?) => paywallCardTrial(offerPeriod(free)),
    WinBackOffer(discount: final discount?) => introOffer(discount),
    _ => throw StateError('A win-back offer is free or a discount'),
  };

  String purchaseButton(Plan plan) {
    final intro = plan.intro;
    final trial = plan.trial;
    switch (plan.winBack) {
      case WinBackOffer(free: final free?):
        return free.count == 1
            ? paywallStartWinBack(free.unit.name)
            : paywallStartTrial(_trialLength(free));
      case WinBackOffer(discount: final discount?):
        return paywallStartIntro(discount.price);
    }
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
    final winBack = plan.winBack;
    return [
      if (winBack?.free case final free?)
        paywallTrialTerms(offerPeriod(free), planPrice(plan))
      else if (winBack?.discount case final discount?)
        paywallIntroTerms(introOffer(discount), planPrice(plan))
      else if (trial != null)
        paywallTrialTerms(offerPeriod(trial), _afterTrial(plan))
      else if (intro != null)
        paywallIntroTerms(introOffer(intro), planPrice(plan))
      else
        paywallChargeTerms,
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
