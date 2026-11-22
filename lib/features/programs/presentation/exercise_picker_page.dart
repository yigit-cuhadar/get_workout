import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/exercise_detail_cubit.dart';
import '../../exercises/presentation/library_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../exercises/presentation/widgets/exercise_tile.dart';
import '../../exercises/presentation/widgets/library_list_view.dart';
import '../programs_module.dart';
import 'exercise_picker_cubit.dart';

/// Where a page's exercise picker opens: the route for picking up to
/// `max` exercises, or with `multiple` off one.
typedef PickerRoute = String Function({
  required int max,
  required bool multiple,
});

/// What the picker is for; it sets the title and, for [swap] and
/// [replace], lists the exercise's similar ones first.
enum ExercisePickerForm {
  add,

  /// Exercises the generator leaves out.
  leaveOut,

  /// A workout's exercise, some of whose sets may be logged.
  swap,

  /// A program's exercise, possibly no longer in the library.
  replace;

  static ExercisePickerForm byName(String? name) =>
      values.asNameMap()[name] ?? add;
}

/// Opens [picker]'s page in its Swap form for [exerciseId], [logged] of
/// whose working sets and [warmups] of whose warm-ups are done (its note
/// says they stay); the picked exercise's id, or null when none is picked.
Future<String?> pickSwap(
  BuildContext context, {
  required String exerciseId,
  required int logged,
  required int warmups,
  required PickerRoute picker,
}) async {
  final picked = await context.push<List<Exercise>>(
    _withForm(
      picker(max: 1, multiple: false),
      ExercisePickerForm.swap,
      exerciseId: exerciseId,
      logged: logged,
      warmups: warmups,
    ),
  );
  return picked?.firstOrNull?.id;
}

/// Opens [picker]'s page in its Replace form for [exerciseId], or for an
/// exercise no longer in the library when null; the picked exercise, or
/// null when none is picked.
Future<Exercise?> pickReplacement(
  BuildContext context, {
  required String? exerciseId,
  required PickerRoute picker,
}) async {
  final picked = await context.push<List<Exercise>>(
    _withForm(
      picker(max: 1, multiple: false),
      ExercisePickerForm.replace,
      exerciseId: exerciseId,
    ),
  );
  return picked?.firstOrNull;
}

/// The Swap and Replace forms' path, beside the picker's own (`pick`):
/// they are steps of their page, while adding opens over the flow.
const pickStepPath = 'swap';

/// [location], the picker's, in [form] at [pickStepPath].
String _withForm(
  String location,
  ExercisePickerForm form, {
  String? exerciseId,
  int logged = 0,
  int warmups = 0,
}) {
  final uri = Uri.parse(location);
  return uri
      .replace(
        path:
            '${uri.path.substring(0, uri.path.lastIndexOf('/'))}/$pickStepPath',
        queryParameters: {
          ...uri.queryParameters,
          'form': form.name,
          'exercise': ?exerciseId,
          if (logged > 0) 'logged': '$logged',
          if (warmups > 0) 'warmups': '$warmups',
        },
      )
      .toString();
}

/// The library list for choosing exercises. Pops with the chosen ones: up
/// to [max] (of at most [limit] in all, which the bar names once the pick
/// is full), or with [multiple] off the one tapped. The Swap and Replace
/// forms list [exerciseId]'s similar exercises first.
class ExercisePickerPage extends StatelessWidget {
  const ExercisePickerPage({
    super.key,
    required this.max,
    required this.limit,
    required this.multiple,
    this.form = ExercisePickerForm.add,
    this.exerciseId,
    this.logged = 0,
    this.warmups = 0,
  });

  final int max;
  final int limit;
  final bool multiple;
  final ExercisePickerForm form;
  final String? exerciseId;
  final int logged;
  final int warmups;

  @override
  Widget build(BuildContext context) {
    final exerciseId = this.exerciseId;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              sl<LibraryCubit>(instanceName: ProgramsModule.pickerLibrary),
        ),
        BlocProvider(
          create: (_) => sl<ExercisePickerCubit>(param1: max, param2: multiple),
        ),
        if (exerciseId != null)
          BlocProvider(
            create: (_) => sl<ExerciseDetailCubit>(
              param1: exerciseId,
              param2: ExerciseViewSource.catalogue,
            ),
          ),
      ],
      child: _PickerView(
        form: form,
        limit: limit,
        logged: logged,
        warmups: warmups,
        exerciseId: exerciseId,
      ),
    );
  }
}

class _PickerView extends StatefulWidget {
  const _PickerView({
    required this.form,
    required this.limit,
    required this.logged,
    required this.warmups,
    required this.exerciseId,
  });

  final ExercisePickerForm form;
  final int limit;
  final int logged;
  final int warmups;

  /// The exercise being swapped or replaced, if any; an
  /// [ExerciseDetailCubit] gives its similar ones.
  final String? exerciseId;

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
  /// How long a just-created exercise may take to reach the catalogue.
  static const _arrival = Duration(seconds: 5);

  /// At most this many similar exercises come first.
  static const _similarCount = 8;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<LibraryCubit>().setLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  /// Creates [name] as a custom exercise above the picker, then chooses it
  /// once the catalogue holds it.
  Future<void> _create(String name) async {
    final picker = context.read<ExercisePickerCubit>();
    final catalogue = context.read<ExerciseCatalogueCubit>();
    final location = Uri(
      path: '${GoRouterState.of(context).uri.path}/new',
      queryParameters: {'name': name},
    ).toString();
    final id = await context.push<String>(location);
    if (id == null) return;
    Exercise? find(ExerciseCatalogueState state) => state is CatalogueReady
        ? state.exercises.where((e) => e.id == id).firstOrNull
        : null;
    var exercise = find(catalogue.state);
    if (exercise == null) {
      try {
        exercise = await catalogue.stream
            .map(find)
            .firstWhere((e) => e != null)
            .timeout(_arrival);
      } on TimeoutException {
        return;
      }
    }
    if (exercise != null && !picker.isClosed) picker.choose(exercise);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final picker = context.read<ExercisePickerCubit>();
    final detail = widget.exerciseId != null
        ? context.watch<ExerciseDetailCubit>().state
        : null;
    final subject = detail is DetailReady
        ? detail.exercise.localized(context).name
        : null;
    final relations = <String, String>{
      if (detail is DetailReady) ...{
        for (final e in detail.alternatives) e.id: l10n.detailAlternative,
        for (final e in detail.variations) e.id: l10n.detailVariation,
      },
    };
    final similar = switch (widget.form) {
      ExercisePickerForm.swap || ExercisePickerForm.replace => [
        if (detail is DetailReady)
          ...[...detail.alternatives, ...detail.variations].take(_similarCount),
      ],
      _ => null,
    };
    final title = switch (widget.form) {
      ExercisePickerForm.add => l10n.pickerTitleAdd,
      ExercisePickerForm.leaveOut => l10n.pickerTitleLeaveOut,
      ExercisePickerForm.swap =>
        subject == null ? l10n.workoutSwap : l10n.pickerTitleSwap(subject),
      ExercisePickerForm.replace =>
        subject == null
            ? l10n.pickerTitleReplaceUnknown
            : l10n.pickerTitleReplace(subject),
    };
    return BlocConsumer<ExercisePickerCubit, ExercisePickerState>(
      listenWhen: (_, current) => current.done,
      listener: (context, state) => context.pop(state.selected),
      builder: (context, state) {
        final count = state.selected.length;
        final full = picker.isFull;
        return Scaffold(
          appBar: ForgeAppBar(title: title),
          body: Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.form == ExercisePickerForm.swap &&
                    widget.logged + widget.warmups > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.md + Gap.xs,
                      0,
                      Gap.md + Gap.xs,
                      Gap.sm,
                    ),
                    child: Text(
                      _swapNote(l10n, widget.logged, widget.warmups),
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: ForgeStyle.of(context).colors.inkMuted,
                      ),
                    ),
                  ),
                Expanded(
                  child: LibraryListView(
                    similar: similar,
                    replacing: widget.exerciseId,
                    onCreate: _create,
                    tileBuilder: (context, exercise) => picker.multiple
                        ? ExerciseTile(
                            exercise,
                            selected: state.isSelected(exercise),
                            enabled: !full || state.isSelected(exercise),
                            onSelect: () => picker.toggle(exercise),
                          )
                        : ExerciseTile(
                            exercise,
                            tag: relations[exercise.id],
                            onOpen: () => picker.toggle(exercise),
                          ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: picker.multiple
              ? ForgeBottomActionBar.count(
                  count: count == 0
                      ? l10n.pickerNoneChosen
                      : full
                      ? l10n.pickerChosenFull(count, widget.limit)
                      : l10n.pickerChosen(count),
                  none: count == 0,
                  action: ForgeButton(
                    label: widget.form == ExercisePickerForm.leaveOut
                        ? l10n.pickerLeaveOut(count)
                        : l10n.pickerAddCount(count),
                    size: ForgeButtonSize.large,
                    onPressed: count == 0
                        ? null
                        : () => context.pop(state.selected),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// The Swap form's note: which done sets stay, warm-ups named apart from
/// the numbered working sets.
String _swapNote(AppLocalizations l10n, int logged, int warmups) =>
    switch ((logged, warmups)) {
      (_, 0) => l10n.pickerSwapLogged(logged),
      (0, _) => l10n.pickerSwapWarmupsLogged(warmups),
      _ => l10n.pickerSwapBothLogged(warmups, logged),
    };
