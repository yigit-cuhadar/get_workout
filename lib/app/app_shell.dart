import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/consent_prompt.dart';
import '../features/programs/presentation/program_writes_notice.dart';
import '../features/workout/presentation/workout_bar.dart';
import '../l10n/app_localizations.dart';

/// The five tabs, with the minimized workout above them. Each branch keeps
/// its own stack; tapping the open tab returns it to its first page, the
/// way back would, so a page that refuses to pop
/// (e.g. with unsaved changes) can ask first and stop it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: ConsentPrompt(child: ProgramWritesNotice(child: shell)),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RunningWorkoutBar(),
          ForgeNavigationBar(
            selectedIndex: shell.currentIndex,
            onSelected: (index) => index == shell.currentIndex
                ? _popToFirst(index)
                : shell.goBranch(index),
            destinations: [
              ForgeDestination(icon: ForgeIcons.today, label: l10n.tabToday),
              ForgeDestination(
                icon: ForgeIcons.description,
                label: l10n.tabPrograms,
              ),
              ForgeDestination(
                icon: ForgeIcons.fitnessCenter,
                label: l10n.tabExercises,
              ),
              ForgeDestination(
                icon: ForgeIcons.barChart,
                label: l10n.tabProgress,
              ),
              ForgeDestination(icon: ForgeIcons.person, label: l10n.tabProfile),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _popToFirst(int index) async {
    final navigator = shell.route.branches[index].navigatorKey.currentState;
    while (navigator != null && navigator.mounted && navigator.canPop()) {
      if (_top(navigator).popDisposition == RoutePopDisposition.doNotPop) {
        // The page is asked like on back; it leaves on its own if it agrees.
        await navigator.maybePop();
        return;
      }
      navigator.pop();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// The route on top of [navigator]. A predicate that accepts the first
  /// route it sees pops nothing.
  static Route<Object?> _top(NavigatorState navigator) {
    late Route<Object?> top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }
}
