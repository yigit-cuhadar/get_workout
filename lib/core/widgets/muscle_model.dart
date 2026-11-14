import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/muscle_meshes.dart';
import '../../features/exercises/domain/vocabulary.dart';
import '../../features/exercises/presentation/vocabulary_labels.dart';
import '../../l10n/app_localizations.dart';

/// The body's colour where no muscle colour is given.
Color muscleModelBase(ForgePalette p) =>
    Color.lerp(p.surface, p.lineStrong, 0.45)!;

/// Every mesh of each muscle in [colors] in that muscle's colour.
Map<String, Color> muscleMeshColors(Map<Muscle, Color> colors) => {
  for (final MapEntry(key: muscle, value: color) in colors.entries)
    for (final mesh in muscle.meshNames) mesh: color,
};

/// Every mesh of [muscles].
Set<String> muscleMeshes(Iterable<Muscle> muscles) => {
  for (final muscle in muscles) ...muscle.meshNames,
};

/// The one rotatable body model where muscles are explored (Exercises,
/// Weekly volume), in a framed panel with Front / Back in its corner. A
/// tap on a muscle, or a slide across muscles and its release, opens it
/// through [onOpen]; while sliding, the muscle under the finger shows in
/// a bar at the bottom. Muscles in [colors] are painted so, those in
/// [outlined] ringed in danger. With [sides] Front / Back sit in the
/// corner.
class MuscleModel extends StatefulWidget {
  const MuscleModel({
    super.key,
    required Model3D this.model,
    required ValueChanged<Muscle> this.onOpen,
    required String this.semanticLabel,
    this.colors = const {},
    this.outlined = const {},
    this.sides = true,
  }) : onRetry = null;

  /// The model loads: a shimmering figure.
  const MuscleModel.loading({super.key, this.sides = true})
    : model = null,
      onOpen = null,
      semanticLabel = null,
      colors = const {},
      outlined = const {},
      onRetry = null;

  /// The model could not load: the error and Retry; the page around it
  /// keeps working.
  const MuscleModel.failed({super.key, required VoidCallback this.onRetry})
    : sides = false,
      model = null,
      onOpen = null,
      semanticLabel = null,
      colors = const {},
      outlined = const {};

  final Model3D? model;
  final ValueChanged<Muscle>? onOpen;
  final String? semanticLabel;
  final Map<Muscle, Color> colors;
  final Set<Muscle> outlined;
  final VoidCallback? onRetry;
  final bool sides;

  @override
  State<MuscleModel> createState() => _MuscleModelState();
}

class _MuscleModelState extends State<MuscleModel> {
  final _camera = ModelViewerController();

  /// The muscle under the finger while sliding.
  Muscle? _scrubbed;

  static const double _segmentsWidth = 120;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onScrub(String? part) {
    final muscle = part == null ? null : muscleOfMesh(part);
    if (muscle == _scrubbed) return;
    if (muscle != null) HapticFeedback.selectionClick();
    setState(() => _scrubbed = muscle);
  }

  void _onScrubEnd(String? part) {
    // The viewer also ends a slide when it is disposed.
    if (!mounted) return;
    setState(() => _scrubbed = null);
    // An interrupted slide reports no part and opens nothing.
    if (part != null) _open(part);
  }

  void _open(String part) {
    if (muscleOfMesh(part) case final muscle?) widget.onOpen!(muscle);
  }

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final l10n = AppLocalizations.of(context);
    final model = widget.model;
    final onRetry = widget.onRetry;
    final segments = SizedBox(
      width: _segmentsWidth,
      child: ListenableBuilder(
        listenable: _camera,
        builder: (context, _) => ForgeSegmentedControl<bool>(
          segments: [
            ForgeSegment(value: true, label: l10n.libraryFront),
            ForgeSegment(value: false, label: l10n.libraryBack),
          ],
          selected: math.cos(_camera.yaw) >= 0,
          onChanged: (front) =>
              _camera.animateTo(front ? 0 : math.pi, 0, _camera.zoom),
        ),
      ),
    );
    final scrubbed = _scrubbed;
    final Widget content;
    if (model != null) {
      content = Stack(
        children: [
          Positioned.fill(
            child: ModelViewer(
              model: model,
              controller: _camera,
              baseColor: muscleModelBase(p),
              partColors: {
                ...muscleMeshColors(widget.colors),
                ...muscleMeshColors({?scrubbed: p.accent}),
              },
              outlinedParts: muscleMeshes(widget.outlined),
              outlineColor: p.danger,
              selectable: (part) => muscleOfMesh(part) != null,
              onPartTap: _open,
              onScrub: _onScrub,
              onScrubEnd: _onScrubEnd,
              semanticLabel: widget.semanticLabel,
            ),
          ),
          if (widget.sides) Positioned(top: 10, right: 10, child: segments),
          if (scrubbed != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(child: _ScrubBar(scrubbed)),
            ),
        ],
      );
    } else if (onRetry != null) {
      content = Center(
        child: ErrorView(
          title: l10n.muscleModelFailedTitle,
          message: l10n.muscleModelFailedDetail,
          retryLabel: l10n.retry,
          onRetry: onRetry,
        ),
      );
    } else {
      content = Stack(
        children: [
          const Center(child: _SkeletonFigure()),
          if (widget.sides)
            Positioned(
              top: 10,
              right: 10,
              child: IgnorePointer(
                child: Opacity(opacity: 0.5, child: segments),
              ),
            ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: Border.all(color: p.line),
        gradient: model == null
            ? null
            : RadialGradient(
                center: const Alignment(0, -0.1),
                radius: 0.7,
                colors: [p.accentSoft, p.surface],
              ),
        color: model == null ? p.surface : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(style.radii.lg),
        child: content,
      ),
    );
  }
}

/// The muscle under the finger while sliding, and that releasing opens it.
class _ScrubBar extends StatelessWidget {
  const _ScrubBar(this.muscle);
  final Muscle muscle;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: Border.all(color: p.line),
      ),
      child: Row(
        spacing: Gap.sm,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
          ),
          Expanded(
            child: Text(l10n.muscleName(muscle), style: text.titleMedium),
          ),
          Text(
            l10n.muscleModelRelease,
            style: text.labelMedium!.copyWith(
              fontWeight: FontWeight.w400,
              color: p.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A body made of shimmering bars while the model loads.
class _SkeletonFigure extends StatelessWidget {
  const _SkeletonFigure();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    spacing: Gap.sm,
    children: [
      SkeletonBar(width: 40, height: 40),
      SkeletonBar(width: 104, height: 116, radius: 24),
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          SkeletonBar(width: 36, height: 110),
          SkeletonBar(width: 36, height: 110),
        ],
      ),
    ],
  );
}

/// The body's front and back side by side, still, under a [title]: the
/// [main] muscles in accent, the [secondary] ones in a 40% accent tint,
/// with a legend naming them.
class MuscleModelPair extends StatelessWidget {
  const MuscleModelPair({
    super.key,
    required this.model,
    required this.title,
    required this.main,
    this.secondary = const [],
  });

  final Model3D model;
  final String title;
  final List<Muscle> main;
  final List<Muscle> secondary;

  static const double _width = 120;

  /// The model's height to width, as its figure stands.
  static const double _aspect = 330 / 170;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final soft = Color.lerp(p.surface, p.accent, 0.4)!;
    final colors = muscleMeshColors({
      for (final muscle in secondary) muscle: soft,
      for (final muscle in main) muscle: p.accent,
    });
    Widget side(String label, {required bool back}) => Column(
      spacing: 6,
      children: [
        SizedBox(
          width: _width,
          height: _width * _aspect,
          child: StillMuscleModel(
            model: model,
            back: back,
            base: muscleModelBase(p),
            colors: colors,
          ),
        ),
        Text(
          label,
          style: text.labelMedium!.copyWith(
            fontWeight: FontWeight.w400,
            color: p.inkMuted,
          ),
        ),
      ],
    );
    Widget legend(Color color, String label, List<Muscle> muscles) => Row(
      spacing: Gap.sm,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        Text(
          label,
          style: text.bodySmall!.copyWith(
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
        ),
        Flexible(child: Text(l10n.muscleNames(muscles), style: text.bodySmall)),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: p.line, width: style.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(title, style: text.titleMedium),
          Semantics(
            image: true,
            label: l10n.muscleNames([...main, ...secondary]),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 28,
                children: [
                  side(l10n.libraryFront, back: false),
                  side(l10n.libraryBack, back: true),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              legend(p.accent, l10n.muscleModelMain, main),
              if (secondary.isNotEmpty)
                legend(soft, l10n.muscleModelSecondary, secondary),
            ],
          ),
        ],
      ),
    );
  }
}

/// The model held still, facing the front or the [back], in [base] with
/// a colour per mesh in [colors] and the meshes in [outlined] ringed in
/// danger.
class StillMuscleModel extends StatefulWidget {
  const StillMuscleModel({
    super.key,
    required this.model,
    required this.back,
    required this.base,
    required this.colors,
    this.outlined = const {},
  });

  final Model3D model;
  final bool back;
  final Color base;
  final Map<String, Color> colors;
  final Set<String> outlined;

  @override
  State<StillMuscleModel> createState() => _StillMuscleModelState();
}

class _StillMuscleModelState extends State<StillMuscleModel> {
  late final _camera = ModelViewerController(yaw: widget.back ? math.pi : 0);

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModelViewer(
    model: widget.model,
    controller: _camera,
    interactive: false,
    baseColor: widget.base,
    partColors: widget.colors,
    outlinedParts: widget.outlined,
    outlineColor: ForgeStyle.of(context).colors.danger,
  );
}
