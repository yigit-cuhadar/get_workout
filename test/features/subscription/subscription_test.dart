import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/subscription/data/unavailable_purchases_repository.dart';
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
    final monthly = fakePlans.firstWhere(
      (plan) => plan.period == PlanPeriod.monthly,
    );
    final yearly = fakePlans.firstWhere(
      (plan) => plan.period == PlanPeriod.yearly,
    );

    test('names the trial on the button', () {
      expect(l10n.purchaseButton(monthly), 'Subscribe');
      expect(l10n.purchaseButton(yearly), 'Start 7-day free trial');
    });

    test('a row has the price per period and the tag', () {
      final row = l10n.paywallPlan(yearly, PaywallLayout.list, bestValue: true);
      expect(row.name, 'Yearly');
      expect(row.price, r'$39.99 / year');
      expect(row.tag, 'Best value');
      expect(row.detail, isNull);
      expect(row.terms, l10n.purchaseTerms(yearly).join(' '));
    });

    test('a tile has the price, then the trial or the billing', () {
      final yearlyTile = l10n.paywallPlan(
        yearly,
        PaywallLayout.cards,
        bestValue: true,
      );
      expect(yearlyTile.price, r'$39.99');
      expect(yearlyTile.detail, '7 days free');
      expect(yearlyTile.tag, isNull);
      expect(
        l10n.paywallPlan(monthly, PaywallLayout.cards, bestValue: false).detail,
        'billed monthly',
      );
      const lifetime = Plan(
        id: 'l',
        period: PlanPeriod.lifetime,
        price: r'$79.99',
        priceAmount: 79.99,
        currencyCode: 'USD',
      );
      expect(
        l10n
            .paywallPlan(lifetime, PaywallLayout.cards, bestValue: false)
            .detail,
        'once',
      );
    });

    test('the single plan names its trial and its monthly price', () {
      final single = l10n.paywallPlan(
        yearly,
        PaywallLayout.single,
        bestValue: true,
      );
      expect(single.name, 'Yearly · 7 days free');
      expect(single.price, r'$39.99 / year');
      expect(single.detail, r'That is $3.33 a month.');
      expect(
        l10n
            .paywallPlan(monthly, PaywallLayout.single, bestValue: false)
            .detail,
        isNull,
      );
      expect(l10n.paywallSeePlan(monthly), 'See monthly plan');
    });

    test('discloses the trial and the auto-renewal', () {
      final terms = l10n.purchaseTerms(yearly);
      expect(terms.first, contains(r'Free for 7 days, then $39.99 per year'));
      expect(terms.last, contains(r'renews automatically at $39.99 per year'));
      expect(l10n.purchaseTerms(monthly).first, l10n.paywallChargeTerms);
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
          l10n.paywallPlan(intro, PaywallLayout.cards, bestValue: false).detail,
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
        isNull,
      );
    });
  });

  group('UnavailablePurchasesRepository', () {
    const repository = UnavailablePurchasesRepository();

    test('entitles nobody and reports the store unavailable', () async {
      expect(
        (await repository.identify('u1')).valueOrNull,
        const Entitlement.none(),
      );
      final failure = (await repository.offering()).failureOrNull;
      expect(
        failure,
        isA<PurchaseFailure>().having(
          (f) => f.reason,
          'reason',
          PurchaseFailureReason.storeUnavailable,
        ),
      );
    });
  });
}
