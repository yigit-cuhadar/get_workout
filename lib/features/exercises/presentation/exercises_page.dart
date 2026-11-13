import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'equipment_cubit.dart';
import 'custom_write_rejections_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'favorites_cubit.dart';
import 'library_cubit.dart';
import 'widgets/body_view.dart';
import 'widgets/library_list_view.dart';

/// Train's "Exercises" view: the catalogue on the body model or as a list.
/// The page around it gives the app bar.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      // App-wide, so the view, search and filters last while the app runs.
      BlocProvider.value(value: sl<LibraryCubit>()),
      BlocProvider.value(value: sl<CustomWriteRejectionsCubit>()),
    ],
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
    // Favourites, equipment and custom exercises change only on this view's
    // pages, which all sit above this one, so their failures are reported
    // once, here.
    return MultiBlocListener(
      listeners: [
        BlocListener<FavoritesCubit, FavoritesState>(
          listenWhen: (previous, current) =>
              current.failure != null && current.failure != previous.failure,
          listener: (context, _) => _report(context, l10n.favoriteSaveFailed),
        ),
        BlocListener<CustomWriteRejectionsCubit, bool>(
          listenWhen: (_, rejected) => rejected,
          listener: (context, _) {
            _report(context, l10n.customWriteRejected);
            context.read<CustomWriteRejectionsCubit>().shown();
          },
        ),
        BlocListener<EquipmentCubit, EquipmentState>(
          listenWhen: (previous, current) =>
              current.failure != null && current.failure != previous.failure,
          listener: (context, _) => _report(context, l10n.equipmentSaveFailed),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Expanded(
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
                if (view == LibraryView.list)
                  IconButton(
                    tooltip: l10n.customNew,
                    icon: const Icon(Icons.add),
                    onPressed: () => context.push(Routes.customExerciseNew),
                  ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<ExerciseCatalogueCubit, ExerciseCatalogueState>(
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
    );
  }

  static void _report(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}
