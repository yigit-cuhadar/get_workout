import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/account_repository.dart';
import 'delete_account_cubit.dart';

/// What deleting removes, then a confirmation, the password when the
/// server wants a recent sign-in, and the deletion. Afterwards the app
/// starts over as a new guest, which the router shows as onboarding.
class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<DeleteAccountCubit>(),
    child: const _DeleteAccountView(),
  );
}

class _DeleteAccountView extends StatelessWidget {
  const _DeleteAccountView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.select((AuthCubit auth) => auth.user);
    final email = user == null || user.isAnonymous ? null : user.email;
    final theme = Theme.of(context);
    return BlocConsumer<DeleteAccountCubit, DeleteAccountState>(
      listenWhen: (previous, current) => previous != current,
      listener: (context, state) {
        if (state.status == DeleteStatus.needsPassword) {
          unawaited(_askPassword(context, state.failure));
        } else if (state case DeleteAccountState(
          status: DeleteStatus.failed,
          :final failure?,
        )) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_failureText(l10n, failure))));
        }
      },
      // Half deleted, the user may only finish; the account is unusable.
      builder: (context, state) => PopScope(
        canPop: state.status != DeleteStatus.partlyDeleted,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading:
                state.status != DeleteStatus.partlyDeleted,
            title: Text(
              email == null ? l10n.accountDeleteGuest : l10n.accountDelete,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              if (state.status == DeleteStatus.partlyDeleted) ...[
                Text(l10n.deleteAlmostDone, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gap.lg),
                ForgeButton(
                  label: l10n.deleteFinish,
                  onPressed: context.read<DeleteAccountCubit>().delete,
                ),
                const SizedBox(height: Gap.xl),
              ],
              Text(l10n.deleteIntro, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gap.md),
              for (final item in [
                l10n.deleteItemProfile,
                l10n.deleteItemTraining,
                l10n.deleteItemBody,
                if (email != null) l10n.deleteItemSignIn(email),
              ])
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text(item),
                ),
              const SizedBox(height: Gap.md),
              Text(l10n.deleteDeviceNote),
              const SizedBox(height: Gap.md),
              Text(l10n.deleteSubscriptionNote),
              const SizedBox(height: Gap.md),
              Text(l10n.deleteAfter),
              const SizedBox(height: Gap.lg),
              ForgeButton(
                label: email == null
                    ? l10n.accountDeleteGuest
                    : l10n.accountDelete,
                loading: state.status == DeleteStatus.deleting,
                onPressed: state.status == DeleteStatus.partlyDeleted
                    ? null
                    : () => _confirm(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) await cubit.delete();
  }

  Future<void> _askPassword(BuildContext context, Failure? failure) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordDialog(
        error: failure == null ? null : _failureText(l10n, failure),
      ),
    );
    if (password == null) return cubit.cancel();
    await cubit.confirmPassword(password);
  }

  static String _failureText(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        DeletionUnavailableFailure() => l10n.deleteUnavailable,
        NetworkFailure() => l10n.deleteOffline,
        AuthFailure(
          code: 'invalid-credential' || 'wrong-password' || 'user-mismatch',
        ) =>
          l10n.authErrorWrongCredentials,
        AuthFailure(code: 'too-many-requests') => l10n.authErrorTooManyRequests,
        AuthFailure(code: noPasswordCode) => l10n.authErrorRecentLogin,
        _ => l10n.deleteFailed,
      };
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({this.error});

  /// Why the previous password did not work.
  final String? error;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = widget.error;
    return AlertDialog(
      title: Text(l10n.deletePasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.deletePasswordBody),
          const SizedBox(height: Gap.md),
          ForgeTextField(
            label: l10n.authPassword,
            controller: _password,
            obscure: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            const SizedBox(height: Gap.sm),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.deleteConfirm)),
      ],
    );
  }
}
