import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/settings_group.dart';
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
    return BlocConsumer<DeleteAccountCubit, DeleteAccountState>(
      listenWhen: (previous, current) => previous != current,
      listener: (context, state) {
        if (state.status == DeleteStatus.needsPassword) {
          unawaited(_askPassword(context, state.failure));
        } else if (state case DeleteAccountState(
          status: DeleteStatus.failed,
          :final failure?,
        )) {
          showForgeSnackbar(
            context,
            message: _failureText(l10n, failure),
            error: true,
          );
        }
      },
      // Half deleted, the user may only finish; the account is unusable.
      builder: (context, state) {
        final partly = state.status == DeleteStatus.partlyDeleted;
        final colors = ForgeStyle.of(context).colors;
        final text = Theme.of(context).textTheme;
        final strong = text.bodyMedium!.copyWith(fontWeight: FontWeight.w600);
        final muted = text.bodySmall!.copyWith(color: colors.inkMuted);
        return PopScope(
          canPop: !partly,
          child: Scaffold(
            appBar: ForgeAppBar(
              title: email == null
                  ? l10n.accountDeleteGuest
                  : l10n.accountDelete,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(
                Gap.md,
                Gap.xs,
                Gap.md,
                Gap.md,
              ),
              children: [
                SettingsColumn(
                  children: [
                    if (partly)
                      SectionCard.plain(
                        title: l10n.deleteAlmostDone,
                        child: ForgeButton(
                          label: l10n.deleteFinish,
                          onPressed: context.read<DeleteAccountCubit>().delete,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.xs,
                        Gap.xs,
                        Gap.xs,
                        0,
                      ),
                      child: Text(
                        l10n.deleteIntro,
                        style: text.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ListRowCard(
                      children: [
                        for (final item in [
                          l10n.deleteItemProfile,
                          l10n.deleteItemTraining,
                          l10n.deleteItemBody,
                          if (email != null) l10n.deleteItemSignIn(email),
                        ])
                          ListRow(
                            title: item,
                            leading: ForgeIcon(
                              ForgeIcons.removeCircle,
                              size: 20,
                              color: colors.danger,
                            ),
                          ),
                      ],
                    ),
                    Text(l10n.deleteDeviceNote, style: muted),
                    Text(l10n.deleteSubscriptionNote, style: muted),
                    Text(l10n.deleteAfter, style: strong),
                    ForgeButton(
                      label: email == null
                          ? l10n.accountDeleteGuest
                          : l10n.accountDelete,
                      variant: ForgeButtonVariant.danger,
                      loading: state.status == DeleteStatus.deleting,
                      onPressed: partly ? null : () => _confirm(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.deleteConfirmTitle,
        message: l10n.deleteConfirmBody,
        action: ForgeButton(
          label: l10n.deleteConfirm,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(dialog, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(dialog, false),
        ),
      ),
    );
    if (confirmed == true) await cubit.delete();
  }

  Future<void> _askPassword(BuildContext context, Failure? failure) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final password = await showForgeDialog<String>(
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
          l10n.deletePasswordWrong,
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
    return ForgeDialog(
      title: l10n.deletePasswordTitle,
      message: l10n.deletePasswordBody,
      field: ForgeTextField(
        label: l10n.authPassword,
        controller: _password,
        obscure: true,
        autofocus: true,
        autofillHints: const [AutofillHints.password],
        errorText: widget.error,
        onSubmitted: (_) => _submit(),
      ),
      action: ForgeButton(
        label: l10n.deleteConfirm,
        variant: ForgeButtonVariant.danger,
        onPressed: _submit,
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}
