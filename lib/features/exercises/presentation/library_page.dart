import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/vocabulary.dart';
import 'exercise_catalogue_cubit.dart';
import 'library_cubit.dart';
import 'widgets/library_list_view.dart';

/// The exercise list: search, filters, sort, favourites and the + for a
/// custom exercise, on the browsing state the Exercises tab shares.
///
/// Opened for a [muscle] picked on the model (the location's `muscle`), it
/// browses that muscle for this visit: the muscle becomes the filter, the
/// list splits into its main and secondary exercises while it stays the
/// only muscle filtered, and leaving (or a link to another muscle) takes
/// it away again. Otherwise the search field takes focus once the page is
/// in.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.muscle});

  final Muscle? muscle;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _library = sl<LibraryCubit>();

  @override
  void initState() {
    super.initState();
    if (widget.muscle case final muscle?) _library.openMuscle(muscle);
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page stays when only its `muscle` changes.
    if (widget.muscle == oldWidget.muscle) return;
    if (oldWidget.muscle case final muscle?) _library.leaveMuscle(muscle);
    if (widget.muscle case final muscle?) _library.openMuscle(muscle);
  }

  @override
  void dispose() {
    if (widget.muscle case final muscle?) _library.leaveMuscle(muscle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: _library,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.libraryTitle),
          actions: [
            IconButton(
              tooltip: l10n.customNew,
              icon: const Icon(Icons.add),
              onPressed: () => context.push(Routes.customExerciseNew),
            ),
          ],
        ),
        body: BlocBuilder<ExerciseCatalogueCubit, ExerciseCatalogueState>(
          builder: (context, catalogue) => switch (catalogue) {
            CatalogueLoading() => const LoadingView(),
            CatalogueFailed() => ErrorView(
              message: l10n.libraryLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<ExerciseCatalogueCubit>().retry,
            ),
            CatalogueReady() => Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: LibraryListView(
                focusSearch: widget.muscle == null,
                sectionsFor: widget.muscle,
              ),
            ),
          },
        ),
      ),
    );
  }
}
