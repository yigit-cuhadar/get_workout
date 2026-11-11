import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_text.dart';

/// The widest the form grows on a desktop screen.
const _maxWidth = 420.0;

/// Email and password sign-in only: admins are existing accounts.
/// The router leaves this page once `AccessCubit` sees the session.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<AuthFormCubit>(),
    child: const _SignInView(),
  );
}

class _SignInView extends StatefulWidget {
  const _SignInView();

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<_SignInView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  static final _emailPattern = RegExp(r'^\S+@\S+\.\S+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) =>
      _emailPattern.hasMatch(value?.trim() ?? '') ? null : 'Enter an email.';

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthFormCubit>().signIn(_email.text, _password.text);
  }

  void _resetPassword() {
    final error = _validateEmail(_email.text);
    if (error != null) return _show(error);
    context.read<AuthFormCubit>().resetPassword(_email.text);
  }

  void _show(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthFormCubit, AuthFormState>(
      listener: (context, state) => switch (state.status) {
        AuthFormStatus.failure => _show(failureMessage(state.failure!)),
        AuthFormStatus.resetSent => _show('Password reset email sent.'),
        _ => null,
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('GetWorkout admin')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Sign in with an admin account.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Gap.lg),
                      ForgeTextField(
                        label: 'Email',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: Gap.md),
                      ForgeTextField(
                        label: 'Password',
                        controller: _password,
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        validator: (value) => (value?.isEmpty ?? true)
                            ? 'Enter the password.'
                            : null,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: Gap.lg),
                      ForgeButton(
                        label: 'Sign in',
                        loading: state.isLoading,
                        onPressed: _submit,
                      ),
                      TextButton(
                        onPressed: state.isLoading ? null : _resetPassword,
                        child: const Text('Forgot password'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
