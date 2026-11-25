import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/subscription/domain/paywall_layout.dart';
import 'package:get_workout/features/subscription/presentation/premium.dart';
import 'package:get_workout/features/subscription/presentation/subscription_summary.dart';
import 'package:get_workout/features/subscription/presentation/subscription_text.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/l10n/app_localizations_en.dart';

void main() {
  final date = DateTime.utc(2027, 3, 1);

  group('premiumStatusOf', () {
    test('is unknown, free or premium', () {
      expect(
        premiumStatusOf(const EntitlementUnknown()),
        PremiumStatus.unknown,
      );
      expect(premiumStatusOf(const EntitlementInactive()), PremiumStatus.free);
      expect(
        premiumStatusOf(const EntitlementActive(Entitlement(isActive: true))),
        PremiumStatus.premium,
      );
    });
  });

  group('SubscriptionSummary', () {
    SubscriptionSummary active(Entitlement entitlement) =>
        SubscriptionSummary.of(EntitlementActive(entitlement));

    test('checks while unknown and is free when inactive', () {
      expect(
        SubscriptionSummary.of(const EntitlementUnknown()),
        const SubscriptionChecking(),
      );
      expect(
        SubscriptionSummary.of(const EntitlementInactive()),
        const SubscriptionFree(),
      );
    });

    test('tells trial, renewal and end apart', () {
      expect(
        active(
          Entitlement(
            isActive: true,
            expiresAt: date,
            isInTrial: true,
            willRenew: true,
          ),
        ),
        SubscriptionTrial(date),
      );
      expect(
        active(Entitlement(isActive: true, expiresAt: date, willRenew: true)),
        SubscriptionRenews(date),
      );
      expect(
        active(Entitlement(isActive: true, expiresAt: date)),
        SubscriptionEnds(date),
      );
      expect(
        active(const Entitlement(isActive: true)),
        const SubscriptionLifetime(),
      );
    });

    test('puts a billing issue first', () {
      expect(
        active(
          Entitlement(
            isActive: true,
            expiresAt: date,
            willRenew: true,
            hasBillingIssue: true,
          ),
        ),
        const SubscriptionBillingIssue(),
      );
    });
  });

  group('SubscriptionText', () {
    final l10n = AppLocalizationsEn();
    // As offered to a user who never subscribed: no win-back offer.
    Plan offered(PlanPeriod period) {
      final plan = fakePlans.firstWhere((plan) => plan.period == period);
      return Plan(
        id: plan.id,
        period: plan.period,
        price: plan.price,
        priceAmount: plan.priceAmount,
        currencyCode: plan.currencyCode,
        trial: plan.trial,
      );
    }

    final monthly = offered(PlanPeriod.monthly);
    final yearly = offered(PlanPeriod.yearly);

    test('names the trial on the button', () {
      expect(l10n.purchaseButton(monthly), 'Subscribe');
      expect(l10n.purchaseButton(yearly), 'Start 7-day free trial');
    });

    test('a row has the price per period, a month and the saving', () {
      final row = l10n.paywallPlan(
        yearly,
        PaywallLayout.list,
        monthly: monthly,
      );
      expect(row.name, 'Yearly');
      expect(row.price, r'$39.99 / year');
      expect(row.tag, 'Save 58%');
      expect(row.detail, r'$3.33 a month');
      // Alone, a yearly row compares with nothing.
      expect(l10n.paywallPlan(yearly, PaywallLayout.list).tag, isNull);
      expect(row.terms, l10n.purchaseTerms(yearly).join(' '));
    });

    test('a tile has the price, then the trial or the billing', () {
      final yearlyTile = l10n.paywallPlan(
        yearly,
        PaywallLayout.cards,
        monthly: monthly,
      );
      expect(yearlyTile.price, r'$39.99');
      expect(yearlyTile.detail, '7 days free');
      expect(yearlyTile.tag, isNull);
      expect(
        l10n.paywallPlan(monthly, PaywallLayout.cards).detail,
        'billed monthly',
      );
      const lifetime = Plan(
        id: 'l',
        period: PlanPeriod.lifetime,
        price: r'$79.99',
        priceAmount: 79.99,
        currencyCode: 'USD',
      );
      expect(l10n.paywallPlan(lifetime, PaywallLayout.cards).detail, 'once');
    });

    test('the single plan names its trial and its monthly price', () {
      final single = l10n.paywallPlan(
        yearly,
        PaywallLayout.single,
        monthly: monthly,
      );
      expect(single.name, 'Yearly · 7 days free');
      expect(single.price, r'$39.99 / year');
      expect(single.detail, r'That is $3.33 a month.');
      expect(l10n.paywallPlan(monthly, PaywallLayout.single).detail, isNull);
      expect(l10n.paywallSeePlan(monthly), 'See monthly plan');
    });

    test('discloses the trial and the auto-renewal', () {
      final terms = l10n.purchaseTerms(yearly);
      expect(terms.first, contains(r'Free for 7 days, then $39.99 per year'));
      expect(terms.last, contains(r'renews automatically at $39.99 per year'));
      expect(l10n.purchaseTerms(monthly).first, l10n.paywallChargeTerms);
    });

    group('a win-back offer (W2)', () {
      final lapsed = fakePlans.firstWhere(
        (plan) => plan.period == PlanPeriod.yearly,
      );

      test('tags the plan and takes the trial\'s place', () {
        expect(l10n.purchaseButton(lapsed), 'Start free month');
        final row = l10n.paywallPlan(
          lapsed,
          PaywallLayout.list,
          monthly: monthly,
        );
        expect(row.offer, 'Welcome back · 1 month free');
        expect(row.price, r'1 month free, then $39.99 / year');
        expect(row.tag, 'Save 58%');
        final tile = l10n.paywallPlan(
          lapsed,
          PaywallLayout.cards,
          monthly: monthly,
        );
        expect(tile.detail, '1 month free');
        expect(tile.offer, row.offer);
        final single = l10n.paywallPlan(
          lapsed,
          PaywallLayout.single,
          monthly: monthly,
        );
        expect(single.name, 'Yearly · 1 month free');
        expect(single.offer, row.offer);
        expect(
          l10n.purchaseTerms(lapsed).first,
          contains(r'Free for 1 month, then $39.99 per year'),
        );
      });

      test('a plan without one is unchanged', () {
        expect(
          l10n.paywallPlan(yearly, PaywallLayout.list, monthly: monthly).offer,
          isNull,
        );
      });

      test('a discount is stated as a price', () {
        const discounted = Plan(
          id: 'm',
          period: PlanPeriod.monthly,
          price: r'$7.99',
          priceAmount: 7.99,
          currencyCode: 'USD',
          winBack: WinBackOffer.discount(
            'w',
            IntroOffer(
              price: r'$0.99',
              period: OfferPeriod(1, PeriodUnit.month),
              cycles: 1,
            ),
          ),
        );
        expect(l10n.purchaseButton(discounted), r'Start for $0.99');
        expect(
          l10n.paywallPlan(discounted, PaywallLayout.list).offer,
          r'Welcome back · $0.99 for 1 month',
        );
      });
    });

    group('a paid intro offer', () {
      const intro = Plan(
        id: 'm',
        period: PlanPeriod.monthly,
        price: r'$4.99',
        priceAmount: 4.99,
        currencyCode: 'USD',
        intro: IntroOffer(
          price: r'$0.99',
          period: OfferPeriod(1, PeriodUnit.month),
          cycles: 3,
        ),
      );

      test('is stated, then the regular price', () {
        expect(l10n.purchaseButton(intro), r'Start for $0.99');
        expect(
          l10n.paywallPlan(intro, PaywallLayout.cards).detail,
          r'$0.99 per month for 3 months',
        );
        final terms = l10n.purchaseTerms(intro);
        expect(terms.first, contains(r'Introductory price: $0.99 per month'));
        expect(terms.first, contains(r'costs $4.99 per month'));
        expect(
          terms.last,
          contains(r'renews automatically at $4.99 per month'),
        );
      });

      test('a single period reads as a length', () {
        const once = IntroOffer(
          price: r'$1.99',
          period: OfferPeriod(2, PeriodUnit.week),
          cycles: 1,
        );
        expect(l10n.introOffer(once), r'$1.99 for 2 weeks');
        const each = IntroOffer(
          price: r'$1.99',
          period: OfferPeriod(2, PeriodUnit.week),
          cycles: 2,
        );
        expect(l10n.introOffer(each), r'$1.99 every 2 weeks for 4 weeks');
      });

      test('follows a free trial', () {
        final both = Plan(
          id: intro.id,
          period: intro.period,
          price: intro.price,
          priceAmount: intro.priceAmount,
          currencyCode: intro.currencyCode,
          trial: const OfferPeriod(7, PeriodUnit.day),
          intro: intro.intro,
        );
        expect(l10n.purchaseButton(both), 'Start 7-day free trial');
        expect(
          l10n.purchaseTerms(both).first,
          startsWith(
            r'Free for 7 days, then $0.99 per month for 3 months, '
            r'then $4.99 per month.',
          ),
        );
      });
    });

    test('maps failures to messages', () {
      expect(
        l10n.purchaseError(
          const PurchaseFailure(PurchaseFailureReason.storeUnavailable),
        ),
        l10n.paywallUnavailable,
      );
      expect(l10n.purchaseError(const NetworkFailure()), l10n.errorNetwork);
      expect(l10n.purchaseError(const UnknownFailure()), l10n.errorGeneric);
    });
  });

  group('purchasesBackend', () {
    test('uses RevenueCat when this platform has a key', () {
      expect(
        purchasesBackend(
          platform: TargetPlatform.iOS,
          release: true,
          iosKey: 'appl_x',
          androidKey: '',
        ),
        isA<RevenueCatBackend>(),
      );
      expect(
        purchasesBackend(
          platform: TargetPlatform.android,
          release: false,
          iosKey: 'appl_x',
          androidKey: '',
        ),
        isA<FakeBackend>(),
      );
    });

    test('never uses the fake in release builds', () {
      expect(
        purchasesBackend(
          platform: TargetPlatform.iOS,
          release: true,
          iosKey: '',
          androidKey: '',
        ),
        isA<UnavailableBackend>(),
      );
    });
  });
}
