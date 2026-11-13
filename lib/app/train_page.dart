import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/exercises/presentation/exercises_page.dart';
import '../features/programs/presentation/programs_page.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

enum TrainView { program, exercises }

/// The Train tab: the programs and the exercises, two features' first pages
/// as two views of one page. Each view has its own location, so links and
/// back keep working; both locations show this page under [pageKey], so the
/// navigator updates it in place and the other view keeps its state (the
/// body model is not loaded again).
class TrainPage extends StatefulWidget {
  const TrainPage({super.key, required this.view});

  final TrainView view;

  /// The key of the page both views are shown in.
  static const pageKey = ValueKey('train');

  static String location(TrainView view) => switch (view) {
    TrainView.program => Routes.programs,
    TrainView.exercises => Routes.exercises,
  };

  @override
  State<TrainPage> createState() => _TrainPageState();
}

class _TrainPageState extends State<TrainPage> {
  /// The views shown so far; a view is built the first time it shows, as a
  /// tab would be.
  late final _shown = {widget.view};

  @override
  void didUpdateWidget(TrainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shown.add(widget.view);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabTrain)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
            child: SegmentedButton<TrainView>(
              segments: [
                ButtonSegment(
                  value: TrainView.program,
                  label: Text(l10n.trainMyProgram),
                ),
                ButtonSegment(
                  value: TrainView.exercises,
                  label: Text(l10n.trainExercises),
                ),
              ],
              selected: {widget.view},
              onSelectionChanged: (selection) =>
                  context.go(TrainPage.location(selection.single)),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: widget.view.index,
              children: [
                for (final view in TrainView.values)
                  if (!_shown.contains(view))
                    const SizedBox.shrink()
                  else
                    // A hidden view's heroes do not fly.
                    HeroMode(
                      enabled: view == widget.view,
                      child: switch (view) {
                        TrainView.program => const ProgramsPage(),
                        TrainView.exercises => const ExercisesPage(),
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
