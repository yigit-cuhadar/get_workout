import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:go_router/go_router.dart';

import 'access/presentation/access_cubit.dart';
import 'access/presentation/access_page.dart';
import 'access/presentation/sign_in_page.dart';
import 'exercises/presentation/exercise_editor_page.dart';
import 'exercises/presentation/exercise_list_cubit.dart';
import 'exercises/presentation/exercise_list_page.dart';

abstract final class AdminRoutes {
  static const signIn = '/sign-in';
  static const access = '/access';
  static const exercises = '/exercises';
  static const newExercise = '$exercises/new';
  static String exercise(String id) => '$exercises/$id';
}

/// Every route of the panel. Only an admin gets past the sign-in and access
/// pages.
GoRouter buildAdminRouter(AccessCubit access) {
  return GoRouter(
    initialLocation: AdminRoutes.exercises,
    refreshListenable: _StreamListenable(access.stream),
    redirect: (context, state) {
      final at = state.matchedLocation;
      final gate = at == AdminRoutes.signIn || at == AdminRoutes.access;
      return switch (access.state) {
        SignedOut() => at == AdminRoutes.signIn ? null : AdminRoutes.signIn,
        SignedIn(isAdmin: true) => gate ? AdminRoutes.exercises : null,
        _ => at == AdminRoutes.access ? null : AdminRoutes.access,
      };
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AdminRoutes.exercises),
      GoRoute(path: AdminRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: AdminRoutes.access, builder: (_, _) => const AccessPage()),
      // The list lives while any exercise page is open, so its search and
      // filters survive a trip to the editor.
      ShellRoute(
        builder: (_, _, child) =>
            BlocProvider(create: (_) => sl<ExerciseListCubit>(), child: child),
        routes: [
          GoRoute(
            path: AdminRoutes.exercises,
            builder: (_, _) => const ExerciseListPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const ExerciseEditorPage(id: null),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ExerciseEditorPage(id: state.pathParameters['id']),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
