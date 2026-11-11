import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';

/// The Exercises tab: the body model. Tapping or scrubbing a muscle shows its
/// mesh name for now; the muscle sheet arrives with the Library feature.
class ExercisesPage extends StatefulWidget {
  const ExercisesPage({super.key});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  static const _bodyPart = 'none';

  late final Future<Model3D> _model = rootBundle
      .load('assets/models/body_male.glb')
      .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));
  String? _part;

  void _select(String? part) {
    if (part == _part) return;
    HapticFeedback.selectionClick();
    setState(() => _part = part);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_part ?? l10n.tabExercises)),
      body: FutureBuilder<Model3D>(
        future: _model,
        builder: (context, snapshot) {
          final model = snapshot.data;
          if (snapshot.hasError) {
            return ErrorView(message: l10n.modelLoadFailed);
          }
          if (model == null) return const LoadingView();
          return ModelViewer(
            model: model,
            highlightedPart: _part,
            selectable: (part) => part != _bodyPart,
            onPartTap: _select,
            onScrub: _select,
            semanticLabel: l10n.tabExercises,
          );
        },
      ),
    );
  }
}
