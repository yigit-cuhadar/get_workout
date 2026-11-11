import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_text.dart';
import 'access_cubit.dart';

/// The widest the message grows on a desktop screen.
const _maxWidth = 480.0;

/// Shown while the claims are read, and to a signed-in user who may not
/// edit or whose claims could not be read.
class AccessPage extends StatelessWidget {
  const AccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<AccessCubit, AccessState>(
        builder: (context, state) => switch (state) {
          SignedIn(:final user, isAdmin: false) => _Message(
            title: 'This account is not an admin',
            body:
                '${user.email ?? user.id} has no admin claim. Once '
                'tool/set_admin.sh has granted it, refresh access.',
          ),
          AccessCheckFailed(:final failure) => _Message(
            title: 'Access could not be checked',
            body: failureMessage(failure),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = context.read<AccessCubit>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline, color: theme.colorScheme.error),
              const SizedBox(height: Gap.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Gap.sm),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: Gap.lg),
              ForgeButton(
                label: 'Refresh access',
                onPressed: access.refreshAccess,
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton(
                onPressed: access.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
