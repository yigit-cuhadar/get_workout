import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:go_router/go_router.dart';

import 'access/presentation/access_cubit.dart';
import 'access/presentation/access_page.dart';
import 'access/presentation/sign_in_page.dart';
import 'announcements/presentation/announcements_page.dart';
import 'dashboard/presentation/dashboard_page.dart';
import 'exercises/presentation/exercise_editor_page.dart';
import 'exercises/presentation/exercise_list_cubit.dart';
import 'exercises/presentation/exercise_list_page.dart';
import 'feedback/presentation/feedback_admin_page.dart';
import 'programs/presentation/program_editor_page.dart';
import 'programs/presentation/program_list_cubit.dart';
import 'programs/presentation/program_list_page.dart';
import 'shell/admin_shell.dart';
import 'shell/coming_soon_page.dart';
import 'users/presentation/user_page.dart';
import 'users/presentation/users_cubit.dart';
import 'users/presentation/users_page.dart';

abstract final class AdminRoutes {
  static const signIn = '/sign-in';
  static const access = '/access';
  static const dashboard = '/dashboard';
  static const users = '/users';
  static String user(String uid) => '$users/${Uri.encodeComponent(uid)}';
  static const exercises = '/exercises';
  static const newExercise = '$exercises/new';
  static String exercise(String id) => '$exercises/$id';
  static const programs = '/programs';
  static const newProgram = '$programs/new';
  static String program(String id) => '$programs/$id';
  static const announcements = '/announcements';
  static const feedback = '/feedback';
  static const appSettings = '/app-settings';
}

/// Where [location] leads in [access], or null to stay. Only an admin gets
/// past the sign-in and access pages; they carry the location asked for in
/// `from`, so an admin lands there once admitted (a reload of an exercise's
/// page comes back to it).
String? adminRedirect(AccessState access, Uri location) {
  final path = location.path;
  final atGate = path == AdminRoutes.signIn || path == AdminRoutes.access;
  final from = atGate ? location.queryParameters['from'] : location.toString();
  // Only paths of this app, never a full URL.
  final target = from != null && from.startsWith('/') && !from.startsWith('//')
      ? from
      : AdminRoutes.dashboard;
  String gate(String gatePath) => target == AdminRoutes.dashboard
      ? gatePath
      : Uri(path: gatePath, queryParameters: {'from': target}).toString();
  return switch (access) {
    SignedIn(isAdmin: true) => atGate ? target : null,
    SignedOut() => path == AdminRoutes.signIn ? null : gate(AdminRoutes.signIn),
    _ => path == AdminRoutes.access ? null : gate(AdminRoutes.access),
  };
}

/// A page of the left menu: the [group] whose heading it sits under (none
/// for Dashboard), its [label], the [path] it opens and the [route] that
/// serves it with its subpages. The menu lists the sections in order with a
/// heading wherever the group changes; the router serves their routes
/// inside the menu's shell.
class AdminSection {
  const AdminSection({
    this.group,
    required this.label,
    required this.path,
    required this.route,
  });

  final String? group;
  final String label;
  final String path;
  final RouteBase route;

  /// Whether [location] is this section's page or one of its subpages.
  bool opens(String location) =>
      location == path || location.startsWith('$path/');
}

/// The menu, in order.
final adminSections = [
  AdminSection(
    label: 'Dashboard',
    path: AdminRoutes.dashboard,
    route: GoRoute(
      path: AdminRoutes.dashboard,
      builder: (_, _) => const DashboardPage(),
    ),
  ),
  AdminSection(
    group: 'People',
    label: 'Users',
    path: AdminRoutes.users,
    // The list lives while a user's page is open, so the sign-ups loaded
    // survive a trip to one.
    route: ShellRoute(
      builder: (_, _, child) =>
          BlocProvider(create: (_) => sl<UsersCubit>()..load(), child: child),
      routes: [
        GoRoute(
          path: AdminRoutes.users,
          builder: (_, _) => const UsersPage(),
          routes: [
            GoRoute(
              path: ':uid',
              builder: (_, state) => UserPage(
                key: ValueKey(state.pathParameters['uid']),
                uid: state.pathParameters['uid']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ),
  // The feedback page until the inbox replaces it.
  AdminSection(
    group: 'People',
    label: 'Support inbox',
    path: AdminRoutes.feedback,
    route: GoRoute(
      path: AdminRoutes.feedback,
      builder: (_, _) => const FeedbackAdminPage(),
    ),
  ),
  AdminSection(
    group: 'Content',
    label: 'Exercises',
    path: AdminRoutes.exercises,
    // The list lives while any exercise page is open, so its search and
    // filters survive a trip to the editor.
    route: ShellRoute(
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
  ),
  AdminSection(
    group: 'Content',
    label: 'Programs',
    path: AdminRoutes.programs,
    // Like the exercises: the list outlives a trip to the editor.
    route: ShellRoute(
      builder: (_, _, child) =>
          BlocProvider(create: (_) => sl<ProgramListCubit>(), child: child),
      routes: [
        GoRoute(
          path: AdminRoutes.programs,
          builder: (_, _) => const ProgramListPage(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, _) => const ProgramEditorPage(id: null),
            ),
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  ProgramEditorPage(id: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
  ),
  AdminSection(
    group: 'Content',
    label: 'Announcements',
    path: AdminRoutes.announcements,
    route: GoRoute(
      path: AdminRoutes.announcements,
      builder: (_, _) => const AnnouncementsPage(),
    ),
  ),
  AdminSection(
    group: 'App',
    label: 'App settings',
    path: AdminRoutes.appSettings,
    route: GoRoute(
      path: AdminRoutes.appSettings,
      builder: (_, _) => const ComingSoonPage(title: 'App settings'),
    ),
  ),
];

/// Every route of the panel: the gates on their own, the sections inside
/// the menu.
GoRouter buildAdminRouter(AccessCubit access) {
  return GoRouter(
    initialLocation: AdminRoutes.dashboard,
    refreshListenable: _StreamListenable(access.stream),
    redirect: (_, state) => adminRedirect(access.state, state.uri),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AdminRoutes.dashboard),
      GoRoute(path: AdminRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: AdminRoutes.access, builder: (_, _) => const AccessPage()),
      ShellRoute(
        builder: (_, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [for (final section in adminSections) section.route],
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
