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
/// custom exercise, on the browsing state the Exercises view shares. Opened
/// for a [muscle] picked on the model it browses that muscle, without
/// taking the keyboard; otherwise its search field takes focus.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, this.muscle});

  final Muscle? muscle;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<LibraryCubit>(),
    child: _LibraryView(muscle),
  );
}

class _LibraryView extends StatefulWidget {
  const _LibraryView(this.muscle);

  final Muscle? muscle;

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  @override
  void initState() {
    super.initState();
    if (widget.muscle case final muscle?) {
      context.read<LibraryCubit>().openMuscle(muscle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
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
              autofocus: widget.muscle == null,
              showsMuscle: true,
            ),
          ),
        },
      ),
    );
  }
}
