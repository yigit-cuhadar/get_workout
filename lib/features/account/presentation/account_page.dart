import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../subscription/presentation/premium.dart';
import '../../subscription/presentation/subscription_summary.dart';
import '../../subscription/presentation/subscription_text.dart';
import 'sync_status_cubit.dart';

/// Account status. A signed-in user sees how they sign in and whether
/// their data is backed up, then the subscription, then Sign out and
/// Delete account; a guest is offered an account instead, with the
/// subscription and Delete my data.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider(
      create: (_) => sl<SyncStatusCubit>(),
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.accountTitle),
        body: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, state) => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              SettingsColumn(
                children: switch (state) {
                  Authenticated(:final user) when user.isAnonymous => [
                    const _GuestCard(),
                    SectionLabel(l10n.accountSubscription),
                    const ListRowCard(children: [_SubscriptionRow()]),
                    ListRowCard(children: [_deleteRow(context, l10n, true)]),
                  ],
                  Authenticated(:final user) => [
                    _MemberCard(user),
                    SectionLabel(l10n.accountSubscription),
                    const ListRowCard(children: [_SubscriptionRow()]),
                    ListRowCard(
                      children: [
                        ListRow(
                          title: l10n.accountSignOut,
                          onTap: () => _signOut(context),
                        ),
                        _deleteRow(context, l10n, false),
                      ],
                    ),
                  ],
                  _ => [
                    const ListRowCard(
                      children: [
                        ListRow.loading(),
                        ListRow.loading(index: 1),
                        ListRow.loading(index: 2),
                      ],
                    ),
                    SectionLabel(l10n.accountSubscription),
                    const ListRowCard(children: [ListRow.loading()]),
                    const ListRowCard(
                      children: [ListRow.loading(), ListRow.loading(index: 1)],
                    ),
                  ],
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Destructive, so in danger.
  static Widget _deleteRow(
    BuildContext context,
    AppLocalizations l10n,
    bool guest,
  ) => ListRow(
    title: guest ? l10n.accountDeleteGuest : l10n.accountDelete,
    destructive: true,
    onTap: () => context.push(Routes.accountDelete),
  );

  static Future<void> _signOut(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthCubit>();
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.accountSignOutTitle,
        message: l10n.accountSignOutBody,
        action: ForgeButton(
          label: l10n.accountSignOut,
          onPressed: () => Navigator.pop(dialog, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(dialog, false),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Logged while still the user's: after it, the new guest's.
    unawaited(context.read<Analytics>().signOut());
    await _runSignOut(context, auth);
  }

  /// Retry signs out again without asking: the user already said yes.
  static Future<void> _runSignOut(BuildContext context, AuthCubit auth) async {
    final l10n = AppLocalizations.of(context);
    final result = await auth.signOut();
    if (result.isOk || !context.mounted) return;
    showForgeSnackbar(
      context,
      message: l10n.accountSignOutFailed,
      actionLabel: l10n.retry,
      onAction: () => _runSignOut(context, auth),
      error: true,
    );
  }
}

/// The signed-in user's email, how they sign in and whether this device's
/// data is on the server.
class _MemberCard extends StatelessWidget {
  const _MemberCard(this.user);

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sync = context.watch<SyncStatusCubit>().state;
    final email = user.email;
    final methods = user.signInMethods;
    return ListRowCard(
      children: [
        if (email != null) ListRow(title: l10n.accountEmail, detail: email),
        if (methods.isNotEmpty)
          ListRow(
            title: l10n.accountSignedInWith,
            detail: [
              for (final method in SignInMethod.values)
                if (methods.contains(method)) l10n.signInMethodName(method),
            ].join(', '),
          ),
        switch (sync) {
          SyncStatus.checking => const ListRow.loading(index: 2),
          SyncStatus.backedUp => ListRow(
            title: l10n.accountData,
            detail: l10n.accountBackedUp,
          ),
          SyncStatus.waiting => ListRow(
            title: l10n.accountData,
            detail: l10n.accountWaitingToSync,
          ),
        },
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard.plain(
      title: l10n.accountGuestInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.xs,
        children: [
          ForgeButton(
            label: l10n.accountCreate,
            onPressed: () => context.push(Routes.accountAuth),
          ),
          ForgeButton(
            label: l10n.accountHaveOne,
            variant: ForgeButtonVariant.text,
            onPressed: () => context.push(Routes.accountSignIn),
          ),
        ],
      ),
    );
  }
}

/// GetWorkout Premium and the user's state: opens the paywall for a free
/// user and the store's manage page for a subscriber; nothing while the
/// state is unknown or for Premium that does not renew.
class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = context.select(
      (EntitlementCubit cubit) => SubscriptionSummary.of(cubit.state),
    );
    final VoidCallback? onTap = switch (summary) {
      SubscriptionFree() => () => context.openPaywall(),
      SubscriptionChecking() || SubscriptionLifetime() => null,
      _ => context.manageSubscription,
    };
    return ListRow(
      title: l10n.premiumTitle,
      detail: l10n.subscriptionState(summary) ?? l10n.accountOnFree,
      end: onTap == null ? ListRowEnd.none : ListRowEnd.chevron,
      onTap: onTap,
    );
  }
}

extension on AppLocalizations {
  String signInMethodName(SignInMethod method) => switch (method) {
    SignInMethod.email => signInMethodEmail,
    SignInMethod.google => signInMethodGoogle,
    SignInMethod.apple => signInMethodApple,
  };
}
