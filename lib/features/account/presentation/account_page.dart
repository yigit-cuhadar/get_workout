import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Account status: offers a guest to create an account or sign in, and a
/// signed-in user to sign out.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) => switch (state) {
          Authenticated(:final user) => ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              if (user.isAnonymous)
                ..._guest(context)
              else
                ..._member(context, user),
              const SizedBox(height: Gap.xl),
              // TODO(app-shell): remove; shown only to verify linking keeps the uid.
              Text(
                'User id: ${user.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }

  List<Widget> _guest(BuildContext context) => [
    const Text(
      "You're using GetWorkout as a guest. Create an account to keep your "
      'data if you change phones.',
    ),
    const SizedBox(height: Gap.lg),
    ForgeButton(
      label: 'Create account',
      onPressed: () => context.push(Routes.accountAuth),
    ),
    TextButton(
      onPressed: () => context.push(Routes.accountSignIn),
      child: const Text('I already have an account'),
    ),
  ];

  List<Widget> _member(BuildContext context, AuthUser user) => [
    Text(user.email ?? '', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: Gap.lg),
    ForgeButton(label: 'Sign out', onPressed: () => _signOut(context)),
  ];

  Future<void> _signOut(BuildContext context) async {
    final auth = context.read<AuthCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll continue as a new guest on this device."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await auth.signOut();
    if (!result.isOk) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not sign out. Try again')),
      );
    }
  }
}
