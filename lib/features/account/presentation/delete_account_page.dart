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

/// What deleting removes, then a confirmation, a sign-in again (password or
/// a linked provider) when the server wants a recent one, and the deletion. Afterwards the app
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
        if (state.status == DeleteStatus.needsSignIn) {
          unawaited(_askSignIn(context, state.failure));
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
              back: !partly,
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

  /// "Delete everything?". A user with Apple linked confirms with Apple,
  /// whose sign-in is revoked before deleting (App Store rule), so the
  /// Delete button is "Continue with Apple" for them.
  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final apple =
        context.read<AuthCubit>().user?.signInMethods.contains(
          SignInMethod.apple,
        ) ??
        false;
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.deleteConfirmTitle,
        message: apple ? l10n.deleteConfirmAppleBody : l10n.deleteConfirmBody,
        action: apple
            ? SignInProviderButtons(
                apple: SignInProvider(
                  mark: const ProviderMark(SocialProvider.apple, enabled: true),
                  label: l10n.authContinueWithApple,
                  onPressed: () => Navigator.pop(dialog, true),
                ),
                signingInLabel: l10n.authSigningIn,
              )
            : ForgeButton(
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
    if (confirmed != true) return;
    await (apple ? cubit.deleteWithApple() : cubit.delete());
  }

  /// Asks for the password, the linked providers, or both. A user with
  /// neither known is asked for the password, as before sign-in methods.
  Future<void> _askSignIn(BuildContext context, Failure? failure) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<DeleteAccountCubit>();
    final methods =
        context.read<AuthCubit>().user?.signInMethods ?? const <SignInMethod>{};
    final providers = {
      if (methods.contains(SignInMethod.google)) SocialProvider.google,
      if (methods.contains(SignInMethod.apple)) SocialProvider.apple,
    };
    // A String is a password, a SocialProvider a provider to sign in with.
    final answer = await showForgeDialog<Object>(
      context: context,
      builder: (context) => _SignInDialog(
        password: methods.contains(SignInMethod.email) || providers.isEmpty,
        providers: providers,
        error: failure == null ? null : _failureText(l10n, failure),
      ),
    );
    switch (answer) {
      case final String password:
        await cubit.confirmPassword(password);
      case final SocialProvider provider:
        await cubit.confirmWithProvider(provider);
      default:
        cubit.cancel();
    }
  }

  static String _failureText(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        DeletionUnavailableFailure() => l10n.deleteUnavailable,
        // Apple's codes are not a password's: only offline and another
        // account keep their own words.
        AppleRevokeFailure(cause: NetworkFailure()) => l10n.deleteOffline,
        AppleRevokeFailure(cause: AuthFailure(code: 'user-mismatch')) =>
          l10n.deleteOtherAccount,
        AppleRevokeFailure() => l10n.deleteFailed,
        NetworkFailure() => l10n.deleteOffline,
        AuthFailure(code: 'invalid-credential' || 'wrong-password') =>
          l10n.deletePasswordWrong,
        AuthFailure(code: 'user-mismatch') => l10n.deleteOtherAccount,
        AuthFailure(code: 'too-many-requests') => l10n.authErrorTooManyRequests,
        _ => l10n.deleteFailed,
      };
}

/// "Confirm it's you": the password field and Delete when the user has a
/// password, then "or" and a button per linked provider; without a password
/// only the provider buttons, which sign in and delete at once.
class _SignInDialog extends StatefulWidget {
  const _SignInDialog({
    required this.password,
    required this.providers,
    this.error,
  });

  final bool password;
  final Set<SocialProvider> providers;

  /// Why the previous sign-in did not work.
  final String? error;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
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

  SignInProvider? _provider(AppLocalizations l10n, SocialProvider provider) =>
      widget.providers.contains(provider)
      ? SignInProvider(
          mark: ProviderMark(provider, enabled: true),
          label: switch (provider) {
            SocialProvider.google => l10n.authContinueWithGoogle,
            SocialProvider.apple => l10n.authContinueWithApple,
          },
          onPressed: () => Navigator.pop(context, provider),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providers = widget.providers.isEmpty
        ? null
        : SignInProviderButtons(
            apple: _provider(l10n, SocialProvider.apple),
            google: _provider(l10n, SocialProvider.google),
            signingInLabel: l10n.authSigningIn,
          );
    final cancel = ForgeButton(
      label: l10n.cancel,
      variant: ForgeButtonVariant.secondary,
      onPressed: () => Navigator.pop(context),
    );
    if (!widget.password && providers != null) {
      final error = widget.error;
      return ForgeDialog(
        title: l10n.deletePasswordTitle,
        message: switch (widget.providers.toList()) {
          [SocialProvider.google] => l10n.deleteSignInGoogleBody,
          [SocialProvider.apple] => l10n.deleteSignInAppleBody,
          _ => l10n.deleteSignInBody,
        },
        field: error == null
            ? null
            : Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: ForgeStyle.of(context).colors.danger),
              ),
        action: providers,
        cancel: cancel,
      );
    }
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
      alternative: providers == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.md,
              children: [
                OrDivider(label: l10n.deleteSignInOr),
                providers,
              ],
            ),
      cancel: cancel,
    );
  }
}
