import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/paywall_layout.dart';
import 'premium_paywall_cubit.dart';
import 'subscription_text.dart';

/// The Premium paywall: Forge's [SubscriptionPlans] fed from
/// [PremiumPaywallCubit]. Pops with true once the user has Premium, also
/// when they already had it on opening.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  final _cubit = sl<PremiumPaywallCubit>()..load();

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<PaywallCubit>.value(
    value: _cubit,
    child: _PaywallView(_cubit.layout),
  );
}

class _PaywallView extends StatefulWidget {
  const _PaywallView(this.layout);

  final PaywallLayout layout;

  @override
  State<_PaywallView> createState() => _PaywallViewState();
}

class _PaywallViewState extends State<_PaywallView> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    if (context.read<EntitlementCubit>().isActive) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _close(AppLocalizations.of(context).paywallPremiumActive),
      );
    }
  }

  /// Closes this paywall's own route, even when something is above it,
  /// with true once Premium is there, after showing [message].
  void _close(String? message, {bool premium = true}) {
    if (_closing || !mounted) return;
    _closing = true;
    if (message != null) _show(message);
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    route.isCurrent
        ? navigator.pop(premium)
        : navigator.removeRoute(route, premium);
  }

  void _show(String message, {bool error = false}) =>
      showForgeSnackbar(context, message: message, error: error);

  void _onOutcome(PaywallState state) {
    final l10n = AppLocalizations.of(context);
    switch (state.outcome) {
      // A pending purchase shows its card in place of the plans.
      case null || PaywallOutcome.cancelled || PaywallOutcome.pending:
        return;
      case PaywallOutcome.purchased:
        _close(l10n.paywallPurchased);
      case PaywallOutcome.restored:
        _close(l10n.paywallRestored);
      case PaywallOutcome.nothingToRestore:
        _show(l10n.paywallNothingToRestore);
      case PaywallOutcome.notEntitled:
        _show(l10n.paywallNotEntitled, error: true);
      case PaywallOutcome.failed:
        _show(
          l10n.purchaseError(state.failure ?? const UnknownFailure()),
          error: true,
        );
    }
  }

  Future<void> _open(Uri uri) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    if (await openLink(uri) || !mounted) return;
    _show(failed, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<PaywallCubit, PaywallState>(
          listenWhen: (previous, current) =>
              current.outcome != null && previous.outcome != current.outcome,
          listener: (_, state) => _onOutcome(state),
        ),
        // Premium arriving any other way: an approved pending purchase, or
        // a purchase made elsewhere. A purchase in progress reports itself.
        BlocListener<EntitlementCubit, EntitlementState>(
          listenWhen: (_, current) => current is EntitlementActive,
          listener: (context, _) {
            if (context.read<PaywallCubit>().state.isBusy) return;
            _close(l10n.paywallPremiumActive);
          },
        ),
      ],
      child: BlocBuilder<PaywallCubit, PaywallState>(
        builder: (context, state) => _plans(context, l10n, state),
      ),
    );
  }

  Widget _plans(
    BuildContext context,
    AppLocalizations l10n,
    PaywallState state,
  ) {
    final cubit = context.read<PaywallCubit>();
    final layout = widget.layout;
    final plans = state.plans;
    final selected = state.selected;
    final hasMonthly = plans.any((plan) => plan.period == PlanPeriod.monthly);
    // The single layout links to the plan after the shown one.
    final other = layout == PaywallLayout.single && plans.length > 1
        ? plans[(plans.indexOf(selected!) + 1) % plans.length]
        : null;
    return SubscriptionPlans(
      onClose: () => _close(null, premium: false),
      title: l10n.premiumTitle,
      benefits: [
        l10n.paywallBenefitGenerator,
        l10n.paywallBenefitPrograms,
        l10n.paywallBenefitCharts,
        l10n.paywallBenefitVolume,
      ],
      layout: switch (layout) {
        PaywallLayout.list => SubscriptionLayout.rows,
        PaywallLayout.cards => SubscriptionLayout.tiles,
        PaywallLayout.single => SubscriptionLayout.single,
      },
      plans: [
        for (final plan in plans)
          l10n.paywallPlan(
            plan,
            layout,
            bestValue: hasMonthly && plan.period == PlanPeriod.yearly,
          ),
      ],
      selected: selected == null ? -1 : plans.indexOf(selected),
      onSelected: (index) => cubit.select(plans[index]),
      purchaseLabel: selected == null
          ? l10n.paywallSubscribe
          : l10n.purchaseButton(selected),
      onPurchase: cubit.purchase,
      restoreLabel: l10n.paywallRestore,
      onRestore: cubit.restore,
      termsLabel: l10n.paywallTerms,
      onTerms: () => _open(LegalLinks.terms),
      privacyLabel: l10n.paywallPrivacy,
      onPrivacy: () => _open(LegalLinks.privacy),
      alternativeLabel: other == null ? null : l10n.paywallSeePlan(other),
      onAlternative: other == null ? null : () => cubit.select(other),
      loading: state.status == PaywallStatus.loading,
      purchasing: state.status == PaywallStatus.purchasing
          ? defaultTargetPlatform == TargetPlatform.iOS
                ? l10n.paywallConfirmingAppStore
                : l10n.paywallConfirmingPlay
          : null,
      restoring: state.status == PaywallStatus.restoring
          ? l10n.paywallRestoring
          : null,
      message: switch (state) {
        PaywallState(
          loadFailure: PurchaseFailure(
            reason: PurchaseFailureReason.storeUnavailable,
          ),
        ) =>
          SubscriptionMessage.unavailable(
            message: l10n.paywallUnavailable,
            actionLabel: l10n.retry,
            onAction: cubit.load,
          ),
        PaywallState(loadFailure: _?) => SubscriptionMessage.failed(
          title: l10n.paywallLoadFailedTitle,
          message: l10n.paywallLoadFailed,
          actionLabel: l10n.retry,
          onAction: cubit.load,
        ),
        // Nothing more to do here: Premium unlocks by itself once approved.
        PaywallState(outcome: PaywallOutcome.pending) =>
          SubscriptionMessage.pending(
            title: l10n.paywallPendingTitle,
            message: l10n.paywallPending,
            actionLabel: l10n.paywallGotIt,
            onAction: () => _close(null, premium: false),
          ),
        _ => null,
      },
    );
  }
}
