import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/muscle_model.dart';

/// Debug-only harness of the exercise animation spike: plays each clip on
/// the body model and shows what a frame costs.
class AnimationSpikeEntry extends StatelessWidget {
  const AnimationSpikeEntry({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Animation spike'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AnimationSpikePage())),
  );
}

class AnimationSpikePage extends StatefulWidget {
  const AnimationSpikePage({super.key});

  @override
  State<AnimationSpikePage> createState() => _AnimationSpikePageState();
}

typedef _Exercise = ({
  String file,
  String title,
  Set<String> main,
  Set<String> secondary,
});

const _exercises = <_Exercise>[
  (
    file: 'ex_barbell_back_squat',
    title: 'Back squat',
    main: {'quads', 'glute'},
    secondary: {'adductor', 'hamstring', 'erector', 'abdominal'},
  ),
  (
    file: 'ex_barbell_bench_press',
    title: 'Bench press',
    main: {'pec'},
    secondary: {'front_delt', 'triceps'},
  ),
  (
    file: 'ex_pull_up',
    title: 'Pull-up',
    main: {'lat'},
    secondary: {'biceps', 'rear_delt', 'trap', 'forearm'},
  ),
  (
    file: 'ex_lat_pulldown',
    title: 'Lat pulldown',
    main: {'lat'},
    secondary: {'biceps', 'rear_delt', 'trap', 'forearm'},
  ),
  (
    file: 'ex_barbell_deadlift',
    title: 'Deadlift',
    main: {'hamstring', 'glute', 'erector'},
    secondary: {'quads', 'trap', 'lat', 'forearm'},
  ),
];

class _AnimationSpikePageState extends State<AnimationSpikePage> {
  late final Future<Model3D> _body = _model('assets/models/body_male.glb');
  var _exercise = _exercises.first;
  late Future<(Model3D, ModelClip)> _scene = _load(_exercise);
  final _timings = <FrameTiming>[];
  var _cost = '';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  static Future<Model3D> _model(String asset) async =>
      Model3D.fromGlb((await rootBundle.load(asset)).buffer.asUint8List());

  Future<(Model3D, ModelClip)> _load(_Exercise exercise) async {
    final gear = await _model('assets/animations/${exercise.file}.glb');
    final clip = await rootBundle.load(
      'assets/animations/${exercise.file}.clip',
    );
    return (
      Model3D.joined([await _body, gear]),
      ModelClip.parse(clip.buffer.asUint8List()),
    );
  }

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    if (_timings.length < 60) return;
    double mean(Duration Function(FrameTiming) of) =>
        _timings.fold(0, (sum, t) => sum + of(t).inMicroseconds) /
        _timings.length /
        1000;
    final build = mean((t) => t.buildDuration);
    final raster = mean((t) => t.rasterDuration);
    _timings.clear();
    setState(
      () => _cost =
          'build ${build.toStringAsFixed(1)} ms · raster ${raster.toStringAsFixed(1)} ms',
    );
  }

  Map<String, Color> _colors(BuildContext context) {
    final gw = GwColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    Map<String, Color> muscles(Set<String> codes, Color color) => {
      for (final code in codes) ...{
        code: color,
        '${code}_left': color,
        '${code}_right': color,
      },
    };
    return {
      ...muscles(_exercise.secondary, gw.muscleSecondary),
      ...muscles(_exercise.main, gw.heatHigh),
      'gear': scheme.outlineVariant,
      'pad': scheme.outline,
      'steel': scheme.outline,
      'plate': scheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Animation spike')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder(
                future: _scene,
                builder: (context, snapshot) => switch (snapshot) {
                  AsyncSnapshot(:final error?) => Center(child: Text('$error')),
                  AsyncSnapshot(data: (final model, final clip)) => ModelViewer(
                    model: model,
                    clip: clip,
                    baseColor: muscleModelBase(style.colors),
                    partColors: _colors(context),
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ),
            Text(_cost),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final exercise in _exercises)
                  ChoiceChip(
                    label: Text(exercise.title),
                    selected: exercise == _exercise,
                    onSelected: (_) => setState(() {
                      _exercise = exercise;
                      _scene = _load(exercise);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Gap.md),
          ],
        ),
      ),
    );
  }
}
