import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// Account status: offers a guest to create an account or sign in, and a
/// signed-in user to sign out.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) => switch (state) {
          Authenticated(:final user) => ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: user.isAnonymous
                ? _guest(context, l10n)
                : _member(context, l10n, user),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }

  List<Widget> _guest(BuildContext context, AppLocalizations l10n) => [
    Text(l10n.accountGuestInfo),
    const SizedBox(height: Gap.lg),
    ForgeButton(
      label: l10n.accountCreate,
      onPressed: () => context.push(Routes.accountAuth),
    ),
    TextButton(
      onPressed: () => context.push(Routes.accountSignIn),
      child: Text(l10n.accountHaveOne),
    ),
  ];

  List<Widget> _member(
    BuildContext context,
    AppLocalizations l10n,
    AuthUser user,
  ) => [
    Text(user.email ?? '', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: Gap.lg),
    ForgeButton(
      label: l10n.accountSignOut,
      onPressed: () => _signOut(context, l10n),
    ),
  ];

  Future<void> _signOut(BuildContext context, AppLocalizations l10n) async {
    final auth = context.read<AuthCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountSignOutTitle),
        content: Text(l10n.accountSignOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.accountSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await auth.signOut();
    if (!result.isOk) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.accountSignOutFailed)),
      );
    }
  }
}
