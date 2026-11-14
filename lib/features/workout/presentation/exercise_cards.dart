import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/grouping.dart';
import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'set_bubbles.dart';
import 'widgets/exercise_card.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// The exercises of the workout [editor] edits, as a sliver: a card for
/// each one or each superset or circuit. Only the card of the selected set
/// is open, showing its set bubbles; the others show each exercise's
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
typedef _Hold = ({int pointer, int exercise, Offset down});

/// The drag of a card goes through these, all owned by
/// [_ExerciseCardsState]: a header is held as long as a long press, the
/// cards collapse to their lines, the held line is scrolled back under the
/// finger, and only then is the drag let start ([_HoldGate.open]), so it
/// measures the one-line card; once the finger is lifted the cards expand
/// when the drop has been applied (or at the latest after [_dropFallback]).
/// Any pointer end, a scroll first, or the page going away ends it.
class _ExerciseCardsState extends State<ExerciseCards> {
  /// The held exercise's line while [_collapsed].
  final _heldLine = GlobalKey();

  _Hold? _hold;

  /// The drag of the held header, waiting for [_HoldGate.open].
  _HoldGate? _gate;

  /// The gate a header just made, before [_holdStarted] takes it.
  _HoldGate? _newGate;

  /// Where the held pointer is now.
  Offset _finger = Offset.zero;
  Timer? _holdTimer;

  /// Every card shows only its one-line exercises: from the moment a header
  /// is held until its card is dropped, so the dragged card and the list
  /// are short. Headers cannot be held meanwhile.
  bool _collapsed = false;
  bool _dragging = false;
  Animation<double>? _proxyAnimation;
  Timer? _dropTimer;

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
    final exercises = widget.state.workout!.exercises;
    final blocks = groupBlocks(exercises);
    final (start, _) = blocks[block];
    // Nothing to hold while a card moves or edits are refused.
    final holdable = !proxy && !_collapsed && widget.editor.canEdit;
    final moves = holdable ? _moves(block, blocks.length) : null;
    return _Card(
      key: key,
      block: block,
      form: proxy
          ? ExerciseCardForm.lifted
          : _collapsed
          ? ExerciseCardForm.line
          : null,
      state: widget.state,
      editor: widget.editor,
      picker: widget.picker,
      exerciseRoute: widget.exerciseRoute,
      wrapLine: (item, line) {
        final exercise = start + item;
        var wrapped = line;
        if (moves != null) {
          wrapped = Semantics(
            customSemanticsActions: moves,
            child: Listener(
              onPointerDown: (event) => _holdStarted(event, exercise),
              child: _HoldDragStartListener(
                index: block,
                onGate: (gate) => _newGate = gate,
                child: wrapped,
              ),
            ),
          );
        }
        return _collapsed && !proxy && _hold?.exercise == exercise
            ? KeyedSubtree(key: _heldLine, child: wrapped)
            : wrapped;
      },
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
  /// long press. The header's [_HoldDragStartListener] has made [_gate]
  /// just before.
  void _holdStarted(PointerDownEvent event, int exercise) {
    final gate = _newGate;
    _newGate = null;
    if (_hold != null || _collapsed || _dragging) {
      gate?.reject();
      return;
    }
    _gate = gate;
    _hold = (pointer: event.pointer, exercise: exercise, down: event.position);
    _finger = event.position;
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _held);
    _holdTimer = Timer(kLongPressTimeout, _collapse);
  }

  void _held(PointerEvent event) {
    final hold = _hold;
    if (hold == null) return;
    if (event is PointerMoveEvent) {
      _finger = event.position;
      final slop = computeHitSlop(
        event.kind,
        MediaQuery.maybeGestureSettingsOf(context),
      );
      // Moved before the drag started: a scroll, so no drag comes.
      if (!_dragging && (event.position - hold.down).distance > slop) {
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
    // A drag that has not started never will.
    _gate?.reject();
    _gate = null;
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
  /// above it having shrunk, then lets the drag start once that is laid
  /// out. A line laid out of reach gets no drag.
  void _keepUnderFinger() {
    if (!mounted || _hold == null) return;
    final line = _heldLine.currentContext?.findRenderObject();
    if (line is! RenderBox || !line.hasSize) return _holdEnded();
    final position = Scrollable.of(context).position;
    final centre = line.localToGlobal(line.size.center(Offset.zero)).dy;
    position.jumpTo(
      (position.pixels + centre - _finger.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hold == null) return;
      final line = _heldLine.currentContext?.findRenderObject();
      if (line is! RenderBox || !line.hasSize) return _holdEnded();
      final gate = _gate;
      _gate = null;
      gate?.open();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Expands the cards once [animation], the dragged card's, has carried it
  /// to where it was dropped and the drop has been applied.
  void _expandWhenDropped(Animation<double> animation) {
    if (identical(animation, _proxyAnimation)) return;
    _proxyAnimation = animation;
    animation.addListener(() {
      // The list applies the drop right after this last tick, in the same
      // frame the cards expand in.
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

/// Starts dragging card [index] only when its [_HoldGate], handed to
/// [onGate], opens.
class _HoldDragStartListener extends ReorderableDragStartListener {
  const _HoldDragStartListener({
    required super.index,
    required this.onGate,
    required super.child,
  });

  final ValueChanged<_HoldGate> onGate;

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _HoldRecognizer(onGate: onGate, debugOwner: this);
}

class _HoldRecognizer extends MultiDragGestureRecognizer {
  _HoldRecognizer({required this.onGate, super.debugOwner});

  final ValueChanged<_HoldGate> onGate;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    final gate = _HoldGate(event.position, event.kind, gestureSettings);
    onGate(gate);
    return gate;
  }

  @override
  String get debugDescription => 'hold to drag';
}

/// A pointer that drags only once [open]ed, and gives way to a scroll if
/// it moves first.
class _HoldGate extends MultiDragPointerState {
  _HoldGate(super.initialPosition, super.kind, super.gestureSettings);

  bool _open = false;
  bool _done = false;
  GestureMultiDragStartCallback? _starter;

  /// Lets the drag start: claims the pointer, or starts at once when it
  /// was already given.
  void open() {
    if (_done || _open) return;
    _open = true;
    final starter = _starter;
    _starter = null;
    starter != null
        ? starter(initialPosition)
        : resolve(GestureDisposition.accepted);
  }

  /// Gives the pointer up; no drag starts.
  void reject() {
    if (_done || _open) return;
    _done = true;
    resolve(GestureDisposition.rejected);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_done) return;
    _open ? starter(initialPosition) : _starter = starter;
  }

  @override
  void checkForResolutionAfterMove() {
    if (_open || _done) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      reject();
    }
  }

  @override
  void dispose() {
    _done = true;
    super.dispose();
  }
}

/// Card [block] of [groupBlocks] as an [ExerciseCard]: open when it has
/// the selected set, else collapsed, unless [form] says otherwise. Within
/// an open group, tapping an exercise moves the selection to it; tapping a
/// collapsed one opens it.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.block,
    required this.form,
    required this.state,
    required this.editor,
    required this.picker,
    required this.exerciseRoute,
    required this.wrapLine,
  });

  final int block;
  final ExerciseCardForm? form;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;
  final String Function({required int max, required bool multiple}) picker;
  final String Function(String id) exerciseRoute;
  final Widget Function(int item, Widget line) wrapLine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final exercises = state.workout!.exercises;
    final (start, end) = groupBlocks(exercises)[block];
    final selected = state.selection?.exercise;
    final grouped = end - start > 1;
    final form =
        this.form ??
        (selected != null && selected >= start && selected < end
            ? ExerciseCardForm.open
            : ExerciseCardForm.collapsed);
    final open = form == ExerciseCardForm.open;
    return Padding(
      padding: const EdgeInsets.all(Gap.sm),
      child: ExerciseCard(
        form: form,
        optionsLabel: l10n.programItemActions,
        group: grouped
            ? l10n.groupLabel(exercises[start].group!, end - start)
            : null,
        wrapLine: wrapLine,
        items: [
          for (var i = start; i < end; i++)
            _item(context, i, open: open, grouped: grouped, unit: unit),
        ],
      ),
    );
  }

  ExerciseCardItem _item(
    BuildContext context,
    int index, {
    required bool open,
    required bool grouped,
    required WeightUnit unit,
  }) {
    final l10n = AppLocalizations.of(context);
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    final total = exercise.sets.length;
    final done = exercise.doneSets.length;
    final last = state.stats[exercise.exerciseId]?.last;
    return ExerciseCardItem(
      name: exercise.name,
      count: l10n.exerciseCardCount(done, total),
      progress: total == 0 ? 0 : done / total,
      allDone: total > 0 && done == total,
      letter: grouped ? groupItemLabel(exercises, index) : null,
      details: open
          ? [
              ?l10n.goalText(exercise, unit),
              if (last != null) l10n.lastTimeText(last.date),
              ?exercise.note,
            ]
          : const [],
      sets: open ? setBubbles(context, index, state, editor) : null,
      onTap: !open || grouped ? () => editor.openExercise(index) : null,
      onOptions: (button) => _ExerciseMenu(
        index: index,
        state: state,
        editor: editor,
        picker: picker,
        exerciseRoute: exerciseRoute,
      ).show(button),
    );
  }
}

/// The actions on exercise [index]: its detail page, swap, group, note,
/// remove.
class _ExerciseMenu {
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

  /// Opens under [button], the exercise's menu button.
  void show(BuildContext button) {
    final l10n = AppLocalizations.of(button);
    final exercises = state.workout!.exercises;
    final exercise = exercises[index];
    showForgeMenu(
      context: button,
      items: [
        ForgeMenuItem(
          label: l10n.workoutExerciseDetails,
          onTap: () => button.push(exerciseRoute(exercise.exerciseId)),
        ),
        ForgeMenuItem(label: l10n.workoutSwap, onTap: () => _swap(button)),
        if (canLinkWithNext(exercises, index))
          ForgeMenuItem(
            label: linkedSize(exercises, index) == 2
                ? l10n.programMakeSuperset
                : l10n.programMakeCircuit,
            onTap: () => editor.linkWithNext(index),
          ),
        if (exercise.group != null)
          ForgeMenuItem(
            label: l10n.programUngroup,
            onTap: () => editor.ungroup(index),
          ),
        ForgeMenuItem(
          label: exercise.note == null
              ? l10n.workoutAddNote
              : l10n.workoutEditNote,
          onTap: () => _editNote(button, exercise),
        ),
        ForgeMenuItem(
          label: l10n.programRemoveItem,
          destructive: true,
          onTap: () => _remove(button, exercise),
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
