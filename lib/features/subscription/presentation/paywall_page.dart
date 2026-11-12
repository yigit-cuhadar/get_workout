import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import 'premium_paywall_cubit.dart';
import 'subscription_text.dart';

/// The Premium paywall. Pops with true once the user has Premium, also when
/// they already had it on opening.
class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<PaywallCubit>(
    create: (_) => sl<PremiumPaywallCubit>()..load(),
    child: const _PaywallView(),
  );
}

class _PaywallView extends StatefulWidget {
  const _PaywallView();

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

  void _close(String message) {
    if (_closing || !mounted) return;
    _closing = true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    // Closes this paywall's own route, even when something is above it.
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    route.isCurrent ? navigator.pop(true) : navigator.removeRoute(route, true);
  }

  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _onOutcome(PaywallState state) {
    final l10n = AppLocalizations.of(context);
    switch (state.outcome) {
      case null || PaywallOutcome.cancelled:
        return;
      case PaywallOutcome.purchased:
        _close(l10n.paywallPurchased);
      case PaywallOutcome.restored:
        _close(l10n.paywallRestored);
      case PaywallOutcome.nothingToRestore:
        _show(l10n.paywallNothingToRestore);
      case PaywallOutcome.pending:
        _show(l10n.paywallPending);
      case PaywallOutcome.notEntitled:
        _show(l10n.paywallNotEntitled);
      case PaywallOutcome.failed:
        _show(l10n.purchaseError(state.failure ?? const UnknownFailure()));
    }
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
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.premiumTitle)),
        body: BlocBuilder<PaywallCubit, PaywallState>(
          // A restore after a failed load keeps the load's message; the
          // footer shows the restore in progress.
          builder: (context, state) => switch (state) {
            PaywallState(status: PaywallStatus.loading) => const LoadingView(),
            PaywallState(:final loadFailure?) => ErrorView(
              message: switch (loadFailure) {
                PurchaseFailure() ||
                NetworkFailure() => l10n.purchaseError(loadFailure),
                _ => l10n.paywallLoadFailed,
              },
              retryLabel: l10n.retry,
              onRetry: state.isBusy ? null : context.read<PaywallCubit>().load,
            ),
            _ => _Offer(state),
          },
        ),
        bottomNavigationBar: const SafeArea(child: _Footer()),
      ),
    );
  }
}

class _Offer extends StatelessWidget {
  const _Offer(this.state);

  final PaywallState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<PaywallCubit>();
    final selected = state.selected;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text(l10n.paywallIntro, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        for (final benefit in [
          l10n.paywallBenefitGenerator,
          l10n.paywallBenefitPrograms,
          l10n.paywallBenefitStats,
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check, color: theme.colorScheme.primary),
            title: Text(benefit),
          ),
        const SizedBox(height: Gap.md),
        RadioGroup<Plan>(
          groupValue: selected,
          onChanged: (plan) {
            if (plan != null && !state.isBusy) cubit.select(plan);
          },
          child: Column(
            children: [
              for (final plan in state.plans)
                RadioListTile<Plan>(
                  value: plan,
                  enabled: !state.isBusy,
                  title: Text(l10n.planName(plan)),
                  subtitle: Text(l10n.planOffer(plan)),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        if (selected != null) ...[
          ForgeButton(
            label: l10n.purchaseButton(selected),
            loading: state.status == PaywallStatus.purchasing,
            onPressed: state.isBusy ? null : cubit.purchase,
          ),
          const SizedBox(height: Gap.md),
          for (final terms in l10n.purchaseTerms(selected)) ...[
            Text(terms, style: theme.textTheme.bodySmall),
            const SizedBox(height: Gap.sm),
          ],
        ],
      ],
    );
  }
}

/// Restore and the legal links, on every state of the paywall.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<PaywallCubit>().state;
    final canRestore =
        state.status == PaywallStatus.ready ||
        state.status == PaywallStatus.loadFailed;
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          onPressed: canRestore ? context.read<PaywallCubit>().restore : null,
          child: state.status == PaywallStatus.restoring
              ? const SizedBox.square(
                  dimension: Gap.md,
                  child: CircularProgressIndicator(),
                )
              : Text(l10n.paywallRestore),
        ),
        TextButton(
          onPressed: () => _open(context, LegalLinks.terms),
          child: Text(l10n.paywallTerms),
        ),
        TextButton(
          onPressed: () => _open(context, LegalLinks.privacy),
          child: Text(l10n.paywallPrivacy),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    final messenger = ScaffoldMessenger.of(context);
    if (await openLink(uri)) return;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
