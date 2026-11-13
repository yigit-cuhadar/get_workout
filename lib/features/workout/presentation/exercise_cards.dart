import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/grouping.dart';
import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'set_bubbles.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// The exercises of the workout [editor] edits, as a sliver: a card for
/// each one or each superset or circuit. Only the card of the selected set
/// is open, showing its [SetBubbles]; the others show each exercise's
/// progress on one line, and tapping one opens it. [picker] is the route
/// of the exercise picker above the page.
///
/// Holding an exercise's header shows every card as its one-line exercises,
/// then drags its card (a group as one) to another place; once it is
/// dropped the cards open as before, the selection having followed its
/// exercise. Screen readers move a card up or down instead.
class ExerciseCards extends StatefulWidget {
  const ExerciseCards({
    super.key,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
  });

  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;

  @override
  State<ExerciseCards> createState() => _ExerciseCardsState();
}

/// A pointer held on the header of [exercise] since [down].
typedef _Hold = ({int pointer, int exercise, Offset down, double slop});

class _ExerciseCardsState extends State<ExerciseCards> {
  final _list = GlobalKey<SliverReorderableListState>();

  /// The held exercise's line while [_collapsed].
  final _heldLine = GlobalKey();

  _Hold? _hold;

  /// Where the held pointer is now.
  Offset _finger = Offset.zero;
  Timer? _holdTimer;

  /// Every card shows only its one-line exercises: from the moment a header
  /// is held until its card is dropped, so the dragged card and the list
  /// are short.
  bool _collapsed = false;
  bool _dragging = false;
  Animation<double>? _proxyAnimation;
  Timer? _dropTimer;

  /// How long after collapsing the drag starts: the frames that lay the
  /// cards out short and scroll the held line back under the finger, as the
  /// drag measures the card when it starts.
  static const _settle = Duration(milliseconds: 100);

  /// Expands the cards should the drop's own end not be seen (a drag the
  /// list cancelled); longer than the drop animation.
  static const _dropFallback = Duration(milliseconds: 500);

  @override
  void dispose() {
    _endTracking();
    _dropTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverReorderableList(
    key: _list,
    itemCount: groupBlocks(widget.state.workout!.exercises).length,
    onReorderStart: (_) => _dragging = true,
    onReorderItem: widget.editor.moveBlock,
    proxyDecorator: (_, index, animation) {
      _expandWhenDropped(animation);
      // The proxy is built in the navigator's overlay, above this page's
      // providers: it gets those its cards read, and no drag listeners.
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<SettingsCubit>()),
          BlocProvider.value(value: context.read<EquipmentCubit>()),
        ],
        child: _card(index, proxy: true),
      );
    },
    itemBuilder: (context, index) => _card(index, key: ValueKey(index)),
  );

  /// Card [block] of [groupBlocks]; as the drag's [proxy], only its lines.
  Widget _card(int block, {Key? key, bool proxy = false}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = widget.state;
    final exercises = state.workout!.exercises;
    final blocks = groupBlocks(exercises);
    final (start, end) = blocks[block];
    final selected = state.selection?.exercise;
    final lines = _collapsed || proxy;
    final open =
        !lines && selected != null && selected >= start && selected < end;
    final moves = proxy ? null : _moves(block, blocks.length);
    return Card(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (end - start > 1 && !lines)
            ListTile(
              dense: true,
              title: Text(
                l10n.groupLabel(exercises[start].group!, end - start),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          for (var i = start; i < end; i++)
            _ExerciseHeader(
              key: _collapsed && !proxy && _hold?.exercise == i
                  ? _heldLine
                  : null,
              index: i,
              open: open,
              state: state,
              editor: widget.editor,
              picker: widget.picker,
              exerciseRoute: widget.exerciseRoute,
              draggable: moves == null
                  ? null
                  : (tile) => Semantics(
                      customSemanticsActions: moves,
                      child: Listener(
                        onPointerDown: (event) => _holdStarted(event, i),
                        child: _HoldDragStartListener(
                          index: block,
                          child: tile,
                        ),
                      ),
                    ),
            ),
          if (open)
            SetBubbles(
              start: start,
              end: end,
              state: state,
              editor: widget.editor,
            ),
        ],
      ),
    );
  }

  Map<CustomSemanticsAction, VoidCallback> _moves(int block, int count) {
    final labels = WidgetsLocalizations.of(context);
    return {
      if (block > 0)
        CustomSemanticsAction(label: labels.reorderItemUp): () =>
            widget.editor.moveBlock(block, block - 1),
      if (block < count - 1)
        CustomSemanticsAction(label: labels.reorderItemDown): () =>
            widget.editor.moveBlock(block, block + 1),
    };
  }

  /// Follows the pointer down on exercise [exercise]'s header, wherever the
  /// header goes, and collapses the cards once it is held as long as a
  /// long press; [_HoldDragStartListener] starts the drag after [_settle].
  void _holdStarted(PointerDownEvent event, int exercise) {
    if (_hold != null || _collapsed) return;
    _hold = (
      pointer: event.pointer,
      exercise: exercise,
      down: event.position,
      slop: computeHitSlop(
        event.kind,
        MediaQuery.maybeGestureSettingsOf(context),
      ),
    );
    _finger = event.position;
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _held);
    _holdTimer = Timer(kLongPressTimeout, _collapse);
  }

  void _held(PointerEvent event) {
    final hold = _hold;
    if (hold == null) return;
    if (event is PointerMoveEvent) {
      _finger = event.position;
      // Moved before the drag started: a scroll, so no drag comes.
      if (!_dragging && (event.position - hold.down).distance > hold.slop) {
        _holdEnded();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _holdEnded();
    }
  }

  void _holdEnded() {
    _endTracking();
    if (_dragging) {
      _dropTimer = Timer(_dropFallback, _expand);
    } else {
      _expand();
    }
  }

  void _endTracking() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_hold case final hold?) {
      GestureBinding.instance.pointerRouter.removeRoute(hold.pointer, _held);
    }
    _hold = null;
  }

  void _collapse() {
    if (!mounted || _hold == null) return;
    setState(() => _collapsed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepUnderFinger());
  }

  /// Scrolls the held exercise's line back under the finger, the open card
  /// above it having shrunk. A line laid out of reach gets no drag.
  void _keepUnderFinger() {
    if (!mounted || _hold == null) return;
    final line = _heldLine.currentContext?.findRenderObject();
    if (line is! RenderBox || !line.hasSize) {
      _list.currentState?.cancelReorder();
      _holdEnded();
      return;
    }
    final position = Scrollable.of(context).position;
    final centre = line.localToGlobal(line.size.center(Offset.zero)).dy;
    position.jumpTo(
      (position.pixels + centre - _finger.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Expands the cards once [animation], the dragged card's, has carried it
  /// to where it was dropped.
  void _expandWhenDropped(Animation<double> animation) {
    if (identical(animation, _proxyAnimation)) return;
    _proxyAnimation = animation;
    animation.addListener(() {
      if (animation.isDismissed) _expand();
    });
  }

  void _expand() {
    _dropTimer?.cancel();
    _dragging = false;
    _proxyAnimation = null;
    if (mounted && _collapsed) setState(() => _collapsed = false);
  }
}

/// Starts dragging card [index] once its header is held [_settle] longer
/// than a long press, after [_ExerciseCardsState._collapse].
class _HoldDragStartListener extends ReorderableDelayedDragStartListener {
  const _HoldDragStartListener({required super.index, required super.child});

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        debugOwner: this,
        delay: kLongPressTimeout + _ExerciseCardsState._settle,
      );
}

Widget? _groupLeading(List<WorkoutExercise> exercises, int index) =>
    exercises[index].group == null
    ? null
    : CircleAvatar(child: Text(groupItemLabel(exercises, index)));

/// Exercise [index]'s line in its card, [draggable] wrapping all of it but
/// its menu. [open], its name, goal, last time and note, and within a group
/// tapping it moves the selection to it; else its progress, and tapping it
/// opens it.
class _ExerciseHeader extends StatelessWidget {
  const _ExerciseHeader({
    super.key,
    required this.index,
    required this.open,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
    required this.draggable,
  });

  final int index;
  final bool open;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;
  final Widget Function(Widget tile)? draggable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    final Widget tile;
    if (open) {
      final unit = context.select(
        (SettingsCubit cubit) => cubit.state.settings.weightUnit,
      );
      final last = state.stats[exercise.exerciseId]?.last;
      final details = [
        ?l10n.goalText(exercise, unit),
        if (last != null) l10n.lastTimeText(last.date),
        ?exercise.note,
      ];
      final grouped = exercise.group != null;
      tile = ListTile(
        leading: _groupLeading(exercises, index),
        title: Text(
          exercise.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: details.isEmpty ? null : Text(details.join('\n')),
        selected: grouped && state.selection?.exercise == index,
        onTap: grouped ? () => editor.openExercise(index) : null,
      );
    } else {
      tile = ListTile(
        leading: _groupLeading(exercises, index),
        title: Text(
          l10n.workoutExerciseProgress(
            exercise.name,
            exercise.doneSets.length,
            exercise.sets.length,
          ),
        ),
        onTap: () => editor.openExercise(index),
      );
    }
    return Row(
      children: [
        Expanded(child: draggable?.call(tile) ?? tile),
        _ExerciseMenu(
          index: index,
          state: state,
          editor: editor,
          picker: picker,
          exerciseRoute: exerciseRoute,
        ),
      ],
    );
  }
}

enum _ExerciseAction { details, swap, link, ungroup, note, remove }

/// The actions on exercise [index]: its detail page, swap, group, note,
/// remove.
class _ExerciseMenu extends StatelessWidget {
  const _ExerciseMenu({
    required this.index,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
  });

  final int index;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;

  /// Where an exercise's detail page opens above the page.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    return PopupMenuButton<_ExerciseAction>(
      tooltip: l10n.programItemActions,
      onSelected: (action) => switch (action) {
        _ExerciseAction.details => context.push(
          exerciseRoute(exercise.exerciseId),
        ),
        _ExerciseAction.swap => _swap(context),
        _ExerciseAction.link => editor.linkWithNext(index),
        _ExerciseAction.ungroup => editor.ungroup(index),
        _ExerciseAction.note => _editNote(context, exercise),
        _ExerciseAction.remove => _remove(context, exercise),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ExerciseAction.details,
          child: Text(l10n.workoutExerciseDetails),
        ),
        PopupMenuItem(
          value: _ExerciseAction.swap,
          child: Text(l10n.workoutSwap),
        ),
        if (canLinkWithNext(exercises, index))
          PopupMenuItem(
            value: _ExerciseAction.link,
            child: Text(
              linkedSize(exercises, index) == 2
                  ? l10n.programMakeSuperset
                  : l10n.programMakeCircuit,
            ),
          ),
        if (exercise.group != null)
          PopupMenuItem(
            value: _ExerciseAction.ungroup,
            child: Text(l10n.programUngroup),
          ),
        PopupMenuItem(
          value: _ExerciseAction.note,
          child: Text(
            exercise.note == null ? l10n.workoutAddNote : l10n.workoutEditNote,
          ),
        ),
        PopupMenuItem(
          value: _ExerciseAction.remove,
          child: Text(l10n.programRemoveItem),
        ),
      ],
    );
  }

  /// The exercise's alternatives first, then the whole library.
  Future<void> _swap(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final owned = context.read<EquipmentCubit>().state.owned ?? const {};
    final alternatives = editor.alternatives(index, owned).take(8).toList();
    const browse = Object();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.workoutSwapBrowse),
              onTap: () => Navigator.pop(context, browse),
            ),
            if (alternatives.isNotEmpty)
              ListTile(
                dense: true,
                title: Text(
                  l10n.workoutSwapAlternatives,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            for (final exercise in alternatives)
              ListTile(
                title: Text(exercise.localized(context).name),
                subtitle: Text(
                  l10n.exerciseSummary(
                    l10n.muscleNames(exercise.mainMuscles),
                    l10n.equipmentNames(exercise.equipment),
                  ),
                ),
                onTap: () => Navigator.pop(context, exercise),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    var replacement = choice is Exercise ? choice : null;
    if (identical(choice, browse)) {
      final picked = await context.push<List<Exercise>>(
        picker(max: 1, multiple: false),
      );
      replacement = picked?.firstOrNull;
    }
    if (replacement != null) {
      editor.swapExercise(index, replacement, language);
    }
  }

  Future<void> _editNote(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: exercise.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exercise.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            maxLengthFormatter(WorkoutLimits.maxExerciseNoteLength),
          ],
          decoration: InputDecoration(labelText: l10n.workoutExerciseNote),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programSave),
          ),
        ],
      ),
    );
    if (saved == true) editor.setExerciseNote(index, controller.text);
    controller.dispose();
  }

  Future<void> _remove(BuildContext context, WorkoutExercise exercise) async {
    final l10n = AppLocalizations.of(context);
    if (exercise.doneSets.isNotEmpty &&
        !await confirmChoice(
          context,
          title: l10n.workoutRemoveExerciseTitle,
          body: null,
          cancel: l10n.cancel,
          confirm: l10n.programRemoveItem,
        )) {
      return;
    }
    editor.removeExercise(index);
  }
}
