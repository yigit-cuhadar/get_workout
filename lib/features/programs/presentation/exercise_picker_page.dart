import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/library_cubit.dart';
import '../../exercises/presentation/widgets/exercise_tile.dart';
import '../../exercises/presentation/widgets/library_list_view.dart';
import '../programs_module.dart';
import 'exercise_picker_cubit.dart';

/// The library list in selection mode. Pops with the chosen exercises: up
/// to [max], or with [multiple] off the one tapped.
class ExercisePickerPage extends StatelessWidget {
  const ExercisePickerPage({
    super.key,
    required this.max,
    required this.multiple,
  });

  final int max;
  final bool multiple;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) =>
            sl<LibraryCubit>(instanceName: ProgramsModule.pickerLibrary),
      ),
      BlocProvider(
        create: (_) => sl<ExercisePickerCubit>(param1: max, param2: multiple),
      ),
    ],
    child: const _PickerView(),
  );
}

class _PickerView extends StatefulWidget {
  const _PickerView();

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
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
    final picker = context.read<ExercisePickerCubit>();
    return BlocConsumer<ExercisePickerCubit, ExercisePickerState>(
      listenWhen: (_, current) => current.done,
      listener: (context, state) => context.pop(state.selected),
      builder: (context, state) {
        final count = state.selected.length;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              picker.multiple
                  ? l10n.pickerTitleMany(count, picker.max)
                  : l10n.pickerTitleOne,
            ),
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
                  tileBuilder: (context, exercise) => ExerciseTile(
                    exercise,
                    selected: state.isSelected(exercise),
                    onSelect: () => picker.toggle(exercise),
                  ),
                ),
              ),
            },
          ),
          bottomNavigationBar: picker.multiple
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: ForgeButton(
                      label: l10n.pickerAdd(count),
                      onPressed: count == 0
                          ? null
                          : () => context.pop(state.selected),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
