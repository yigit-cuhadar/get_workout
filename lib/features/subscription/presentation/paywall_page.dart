import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/paywall_layout.dart';
import '../domain/paywall_moment.dart';
import 'premium_paywall_cubit.dart';
import 'subscription_text.dart';

/// The Premium paywall: Forge's [SubscriptionPlans] fed from
/// [PremiumPaywallCubit]. Pops with true once the user has Premium, also
/// when they already had it on opening. Opened at [moment] (null: by the
/// user), it may not be closable ([PremiumPaywallCubit.closable]): no close
/// button, back or drag down.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.moment});

  final PaywallMoment? moment;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  late final _cubit = sl<PremiumPaywallCubit>(param1: widget.moment)..load();

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<PaywallCubit>.value(
    value: _cubit,
    child: _PaywallView(_cubit),
  );
}

class _PaywallView extends StatefulWidget {
  const _PaywallView(this.cubit);

  final PremiumPaywallCubit cubit;

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
        builder: (context, state) => PopScope<bool>(
          canPop: widget.cubit.closable,
          onPopInvokedWithResult: (didPop, premium) {
            if (didPop && premium != true) widget.cubit.dismissed();
          },
          child: _plans(context, l10n, state),
        ),
      ),
    );
  }

  Widget _plans(
    BuildContext context,
    AppLocalizations l10n,
    PaywallState state,
  ) {
    final cubit = widget.cubit;
    final layout = cubit.layout;
    final plans = state.plans;
    final selected = state.selected;
    final monthly = plans
        .where((plan) => plan.period == PlanPeriod.monthly)
        .firstOrNull;
    // The single layout links to the plan after the shown one.
    final other = layout == PaywallLayout.single && plans.length > 1
        ? plans[(plans.indexOf(selected!) + 1) % plans.length]
        : null;
    return SubscriptionPlans(
      onClose: cubit.closable ? () => _close(null, premium: false) : null,
      title: l10n.premiumTitle,
      lead: l10n.paywallLead,
      benefits: [
        (
          icon: ForgeIcons.autoAwesome,
          title: l10n.paywallBenefitGenerator,
          detail: l10n.paywallBenefitGeneratorDetail,
        ),
        (
          icon: ForgeIcons.description,
          title: l10n.paywallBenefitPrograms,
          detail: l10n.paywallBenefitProgramsDetail,
        ),
      ],
      layout: switch (layout) {
        PaywallLayout.list => SubscriptionLayout.rows,
        PaywallLayout.cards => SubscriptionLayout.tiles,
        PaywallLayout.single => SubscriptionLayout.single,
      },
      plans: [
        for (final plan in plans)
          l10n.paywallPlan(plan, layout, monthly: monthly),
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
        // A paywall that cannot be closed waits for it.
        PaywallState(outcome: PaywallOutcome.pending) =>
          SubscriptionMessage.pending(
            title: l10n.paywallPendingTitle,
            message: l10n.paywallPending,
            actionLabel: cubit.closable ? l10n.paywallGotIt : null,
            onAction: cubit.closable
                ? () => _close(null, premium: false)
                : null,
          ),
        _ => null,
      },
    );
  }
}
