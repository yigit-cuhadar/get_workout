import 'dart:async';

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

/// The Premium paywall. Pops with true once the user has Premium, also when
/// they already had it on opening.
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
        body: SafeArea(
          top: false,
          child: BlocBuilder<PaywallCubit, PaywallState>(
            // A restore after a failed load keeps the load's message; the
            // footer shows the restore in progress.
            builder: (context, state) => switch (state) {
              PaywallState(status: PaywallStatus.loading) => const _PinOrScroll(
                fill: LoadingView(),
              ),
              PaywallState(:final loadFailure?) => _PinOrScroll(
                fill: ErrorView(
                  message: switch (loadFailure) {
                    PurchaseFailure() ||
                    NetworkFailure() => l10n.purchaseError(loadFailure),
                    _ => l10n.paywallLoadFailed,
                  },
                  retryLabel: l10n.retry,
                  onRetry: state.isBusy
                      ? null
                      : context.read<PaywallCubit>().load,
                ),
              ),
              _ => _PinOrScroll(offer: _Offer(state, layout: widget.layout)),
            },
          ),
        ),
      ),
    );
  }
}

/// The page above [_Footer]. The footer is pinned to the bottom while it
/// takes at most half the height; taller (large text), the whole page
/// scrolls as one, the footer last, so every plan and link stays reachable.
class _PinOrScroll extends StatefulWidget {
  const _PinOrScroll({this.offer, this.fill});

  /// Scrolls above a pinned footer.
  final Widget? offer;

  /// Fills the room above a pinned footer.
  final Widget? fill;

  @override
  State<_PinOrScroll> createState() => _PinOrScrollState();
}

class _PinOrScrollState extends State<_PinOrScroll> {
  final _footer = GlobalKey();
  bool _pinned = false;
  double _height = 0;

  /// Runs after layout, when the footer's height is known; starts unpinned
  /// so the first frame never overflows.
  void _measure() {
    if (!mounted) return;
    final footer = _footer.currentContext?.size?.height;
    if (footer == null) return;
    final pinned = footer <= _height / 2;
    if (pinned != _pinned) setState(() => _pinned = pinned);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _height = constraints.maxHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      final footer = NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
          return true;
        },
        child: SizeChangedLayoutNotifier(
          child: KeyedSubtree(key: _footer, child: const _Footer()),
        ),
      );
      final offer = widget.offer;
      final fill = widget.fill;
      if (_pinned) {
        return Column(
          children: [
            Expanded(child: fill ?? ListView(children: [?offer])),
            footer,
          ],
        );
      }
      return ListView(
        children: [
          ?offer,
          if (fill != null) SizedBox(height: _height / 2, child: fill),
          footer,
        ],
      );
    },
  );
}

class _Offer extends StatelessWidget {
  const _Offer(this.state, {required this.layout});

  final PaywallState state;
  final PaywallLayout layout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            groupValue: state.selected,
            onChanged: (plan) {
              if (plan != null && !state.isBusy) {
                context.read<PaywallCubit>().select(plan);
              }
            },
            child: switch (layout) {
              PaywallLayout.list => _PlanList(state),
              PaywallLayout.cards => _PlanCards(state),
            },
          ),
        ],
      ),
    );
  }
}

/// Layout A: one row per plan, its whole offer on the row.
class _PlanList extends StatelessWidget {
  const _PlanList(this.state);

  final PaywallState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final plan in state.plans)
          RadioListTile<Plan>(
            value: plan,
            enabled: !state.isBusy,
            title: Text(l10n.planName(plan)),
            subtitle: Text(l10n.planOffer(plan)),
          ),
      ],
    );
  }
}

/// Layout B: one card per plan, side by side, the price standing out.
class _PlanCards extends StatelessWidget {
  const _PlanCards(this.state);

  final PaywallState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          for (final plan in state.plans)
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                color: plan == state.selected ? colors.primaryContainer : null,
                child: InkWell(
                  onTap: state.isBusy
                      ? null
                      : () => context.read<PaywallCubit>().select(plan),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<Plan>(value: plan, enabled: !state.isBusy),
                        Text(
                          l10n.planName(plan),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(plan.price, style: theme.textTheme.titleLarge),
                        for (final line in l10n.planCardLines(plan))
                          Text(line, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The selected plan's purchase button and terms over restore and the legal
/// links; restore and the links on every state of the paywall.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<PaywallCubit>();
    final state = context.watch<PaywallCubit>().state;
    final selected = state.selected;
    final canRestore =
        state.status == PaywallStatus.ready ||
        state.status == PaywallStatus.loadFailed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected != null) ...[
            ForgeButton(
              label: l10n.purchaseButton(selected),
              loading: state.status == PaywallStatus.purchasing,
              onPressed: state.isBusy ? null : cubit.purchase,
            ),
            for (final terms in l10n.purchaseTerms(selected)) ...[
              const SizedBox(height: Gap.sm),
              Text(
                terms,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: canRestore ? cubit.restore : null,
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
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    final messenger = ScaffoldMessenger.of(context);
    if (await openLink(uri)) return;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
