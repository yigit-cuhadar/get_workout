import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'equipment_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'favorites_cubit.dart';
import 'library_cubit.dart';
import 'widgets/body_view.dart';
import 'widgets/library_list_view.dart';

/// The Exercises tab: the catalogue on the body model or as a list.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    // App-wide, so the view, search and filters last while the app runs.
    value: sl<LibraryCubit>(),
    child: const _ExercisesView(),
  );
}

class _ExercisesView extends StatefulWidget {
  const _ExercisesView();

  @override
  State<_ExercisesView> createState() => _ExercisesViewState();
}

class _ExercisesViewState extends State<_ExercisesView> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<LibraryCubit>().setLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = context.select((LibraryCubit library) => library.state.view);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabExercises),
        actions: [
          if (view == LibraryView.list)
            IconButton(
              tooltip: l10n.customNew,
              icon: const Icon(Icons.add),
              onPressed: () => context.push(Routes.customExerciseNew),
            ),
        ],
      ),
      // Favourites, equipment and custom exercises change only on this tab's
      // pages, which all sit above this one, so their failures are reported
      // once, here.
      body: MultiBlocListener(
        listeners: [
          BlocListener<FavoritesCubit, FavoritesState>(
            listenWhen: (previous, current) =>
                current.failure != null && current.failure != previous.failure,
            listener: (context, _) => _report(context, l10n.favoriteSaveFailed),
          ),
          BlocListener<LibraryCubit, LibraryState>(
            listenWhen: (previous, current) =>
                current.customWriteRejected && !previous.customWriteRejected,
            listener: (context, _) {
              _report(context, l10n.customWriteRejected);
              context.read<LibraryCubit>().rejectionShown();
            },
          ),
          BlocListener<EquipmentCubit, EquipmentState>(
            listenWhen: (previous, current) =>
                current.failure != null && current.failure != previous.failure,
            listener: (context, _) =>
                _report(context, l10n.equipmentSaveFailed),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: SegmentedButton<LibraryView>(
                segments: [
                  ButtonSegment(
                    value: LibraryView.body,
                    label: Text(l10n.libraryBody),
                    icon: const Icon(Icons.accessibility_new),
                  ),
                  ButtonSegment(
                    value: LibraryView.list,
                    label: Text(l10n.libraryList),
                    icon: const Icon(Icons.list),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (selection) =>
                    context.read<LibraryCubit>().setView(selection.single),
              ),
            ),
            Expanded(
              child:
                  BlocBuilder<ExerciseCatalogueCubit, ExerciseCatalogueState>(
                    builder: (context, catalogue) => switch (catalogue) {
                      CatalogueLoading() => const LoadingView(),
                      CatalogueFailed() => ErrorView(
                        message: l10n.libraryLoadFailed,
                        retryLabel: l10n.retry,
                        onRetry: context.read<ExerciseCatalogueCubit>().retry,
                      ),
                      CatalogueReady() => switch (view) {
                        LibraryView.body => const BodyView(),
                        LibraryView.list => const LibraryListView(),
                      },
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static void _report(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}
