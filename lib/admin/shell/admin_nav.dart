import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../access/presentation/access_cubit.dart';
import '../admin_router.dart';

/// The app bar actions of a list page: the lists of the panel, the account
/// signed in, and signing out.
class AdminNav extends StatelessWidget {
  const AdminNav({super.key});

  static const _lists = [
    ('Exercises', AdminRoutes.exercises),
    ('Programs', AdminRoutes.programs),
  ];

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessCubit>().state;
    final here = GoRouterState.of(context).matchedLocation;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, path) in _lists)
          TextButton(
            onPressed: here == path ? null : () => context.go(path),
            child: Text(label),
          ),
        const SizedBox(width: Gap.md),
        if (access case SignedIn(:final user)) Text(user.email ?? user.id),
        TextButton(
          onPressed: context.read<AccessCubit>().signOut,
          child: const Text('Sign out'),
        ),
        const SizedBox(width: Gap.sm),
      ],
    );
  }
}
