import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/muscle_meshes.dart';
import '../../domain/vocabulary.dart';
import '../body_model_cubit.dart';
import '../vocabulary_labels.dart';

/// The body model: tap a muscle, or press and slide across muscles, to open
/// the exercise list filtered to it.
class BodyView extends StatefulWidget {
  const BodyView({super.key});

  @override
  State<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<BodyView> {
  final _camera = ModelViewerController();

  /// The muscle under the finger while scrubbing.
  Muscle? _scrubbed;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

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
    // The viewer also ends a scrub when it is disposed.
    if (!mounted) return;
    setState(() => _scrubbed = null);
    // An interrupted scrub reports no part and opens nothing.
    if (part != null) _open(muscleOfMesh(part));
  }

  void _open(Muscle? muscle) {
    if (muscle != null) context.push(Routes.exerciseListOf(muscle));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<BodyModelCubit, BodyModelState>(
      builder: (context, state) => switch (state) {
        BodyModelLoading() => const LoadingView(),
        BodyModelFailed() => ErrorView(
          message: l10n.modelLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<BodyModelCubit>().load,
        ),
        BodyModelReady(:final model) => _viewer(context, model),
      },
    );
  }

  Widget _viewer(BuildContext context, Model3D model) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final scrubbed = _scrubbed;
    return Stack(
      children: [
        Positioned.fill(
          child: ModelViewer(
            model: model,
            controller: _camera,
            partColors: {
              for (final mesh in scrubbed?.meshNames ?? const <String>[])
                mesh: colors.primary,
            },
            selectable: (part) => muscleOfMesh(part) != null,
            onPartTap: (part) => _open(muscleOfMesh(part)),
            onScrub: _onScrub,
            onScrubEnd: _onScrubEnd,
            semanticLabel: l10n.libraryModelLabel,
          ),
        ),
        if (scrubbed != null)
          Align(
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.sm,
                    ),
                    child: Text(
                      l10n.muscleName(scrubbed),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => _camera.animateTo(0, 0, 1),
                  child: Text(l10n.libraryFront),
                ),
                const SizedBox(width: Gap.sm),
                OutlinedButton(
                  onPressed: () => _camera.animateTo(math.pi, 0, 1),
                  child: Text(l10n.libraryBack),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
