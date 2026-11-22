import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'equipment_cubit.dart';
import 'custom_write_rejections_cubit.dart';
import 'favorites_cubit.dart';
import 'library_cubit.dart';
import 'widgets/body_view.dart';
import 'widgets/library_list_view.dart';

/// The Exercises tab's first page: the body model under a tap-only search
/// pill. The pill opens the exercise list page, a muscle opens it filtered
/// to that muscle.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      // App-wide, so search and filters last while the app runs.
      BlocProvider.value(value: sl<LibraryCubit>()),
      BlocProvider.value(value: sl<CustomWriteRejectionsCubit>()),
    ],
    child: Scaffold(
      appBar: ForgeAppBar(title: AppLocalizations.of(context).tabExercises),
      body: const _ExercisesView(),
    ),
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
    // Equipment and custom exercises change on this tab's pages, favourites
    // also on a ready-made program's exercise pages in Programs; their
    // failures are reported once, here, while this tab has been opened.
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
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, 10),
            child: ForgeSearchField.tapOnly(
              hint: l10n.librarySearch,
              heroTag: librarySearchHeroTag,
              onTap: () => context.push(Routes.exerciseList),
            ),
          ),
          const Expanded(child: BodyView()),
        ],
      ),
    );
  }

  static void _report(BuildContext context, String message) =>
      showForgeSnackbar(context, message: message, error: true);
}
