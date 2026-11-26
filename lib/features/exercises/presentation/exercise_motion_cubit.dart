import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_motion/forge_motion.dart';

import '../../profile/domain/user_profile.dart';
import '../domain/exercise_animation.dart';
import '../domain/exercise_usecases.dart';
import 'body_model_cubit.dart';

sealed class ExerciseMotionState extends Equatable {
  const ExerciseMotionState();

  @override
  List<Object?> get props => [];
}

final class MotionLoading extends ExerciseMotionState {
  const MotionLoading();
}

/// The exercise has no animation.
final class MotionNone extends ExerciseMotionState {
  const MotionNone();
}

final class MotionFailed extends ExerciseMotionState {
  const MotionFailed();
}

final class MotionReady extends ExerciseMotionState {
  const MotionReady({
    required this.clips,
    required this.selected,
    required this.model,
    required this.motion,
  });

  /// The correct form first, then each shown mistake in catalogue order.
  final List<AnimationClip> clips;

  /// Index into [clips] of the clip [model] and [motion] play.
  final int selected;

  /// The body joined with the selected clip's gear, floor and shadow.
  final Model3D model;
  final ClipMotion motion;

  @override
  List<Object?> get props => [clips, selected, model, motion];
}

/// An exercise's animation on the user's body: the recipe from
/// [GetExerciseAnimation], the body from [BodyModelCubit] and the joints of
/// that body from the injected rig loader (a bundled asset, like the body).
/// Each clip is solved once, when first selected; a change of body solves
/// the selected one again.
class ExerciseMotionCubit extends Cubit<ExerciseMotionState> {
  ExerciseMotionCubit(
    this._exerciseId, {
    required this._getAnimation,
    required this._body,
    required this._loadRig,
  }) : super(const MotionLoading());

  final String _exerciseId;
  final GetExerciseAnimation _getAnimation;
  final BodyModelCubit _body;
  final Future<MotionRig> Function(Sex sex) _loadRig;

  ExerciseAnimation? _animation;
  List<AnimationClip> _clips = const [];
  StreamSubscription<BodyModelState>? _bodyChanges;
  BodyModelReady? _shown;
  MotionRig? _rig;
  final _solved = <int, (Model3D, ClipMotion)>{};
  int _selected = 0;

  /// Reads the animation, then follows the body. Call once.
  Future<void> load() async {
    final result = await _getAnimation(_exerciseId);
    if (isClosed) return;
    switch (result) {
      case Err():
        emit(const MotionFailed());
      case Ok(value: null):
        emit(const MotionNone());
      case Ok(:final value?):
        try {
          _clips = value.clips;
        } catch (error, stack) {
          Log.e('motion', 'Malformed animation of $_exerciseId', error, stack);
          emit(const MotionFailed());
          return;
        }
        _animation = value;
        _bodyChanges = _body.stream.listen(_onBody);
        unawaited(_onBody(_body.state));
        unawaited(_body.load());
    }
  }

  /// Plays clip [index] of [MotionReady.clips].
  void select(int index) {
    if (state is! MotionReady || index == _selected) return;
    _selected = index;
    _emitSelected();
  }

  Future<void> _onBody(BodyModelState body) async {
    switch (body) {
      case BodyModelLoading():
        return;
      case BodyModelFailed():
        if (state is! MotionReady) emit(const MotionFailed());
      case BodyModelReady():
        if (body == _shown) return;
        _shown = body;
        try {
          final rig = await _loadRig(body.sex);
          if (isClosed || body != _shown) return;
          _rig = rig;
          _solved.clear();
          _emitSelected();
        } catch (error, stack) {
          Log.e('motion', 'Rig failed to load', error, stack);
          if (!isClosed && body == _shown) emit(const MotionFailed());
        }
    }
  }

  void _emitSelected() {
    try {
      final (model, motion) = _solved[_selected] ??= _solve(_selected);
      emit(
        MotionReady(
          clips: _clips,
          selected: _selected,
          model: model,
          motion: motion,
        ),
      );
    } catch (error, stack) {
      Log.e('motion', 'Clip $_selected of $_exerciseId failed', error, stack);
      emit(const MotionFailed());
    }
  }

  (Model3D, ClipMotion) _solve(int index) {
    final animation = _animation!;
    final motion = Motion(
      rig: _rig!,
      kits: animation.kits,
      recipe: animation.recipe,
      mistake: _clips[index].mistake,
    );
    final gear = motion.gear;
    final model = Model3D.joined([
      _shown!.model,
      Model3D.fromMesh(
        partNames: gear.partNames,
        positions: gear.positions,
        normals: gear.normals,
        vertexParts: gear.vertexParts,
        indices: gear.indices,
        joints: gear.joints,
      ),
    ]);
    return (model, ClipMotion(motion));
  }

  @override
  Future<void> close() async {
    await _bodyChanges?.cancel();
    return super.close();
  }
}

/// A solved clip as the viewer plays it.
class ClipMotion implements ModelMotion {
  ClipMotion(this._motion)
    : bounds = Float64List.fromList([
        for (var axis = 0; axis < 3; axis++) _motion.bounds[axis] - _pad,
        for (var axis = 3; axis < 6; axis++) _motion.bounds[axis] + _pad,
      ]);

  /// The motion's bounds hold joints, not skin: 0.08 of the body's height
  /// (0.98 units in both body files) is added on every side.
  static const double _pad = 0.08 * 0.98;

  final Motion _motion;

  /// The recipe's camera: yaw and pitch in degrees; yaw 0 faces the body's
  /// front, 90 its left side, and pitch looks down from above.
  (double, double) get view => _motion.view;

  @override
  final Float64List bounds;

  @override
  Duration get duration => _motion.duration;

  @override
  int get jointCount => _motion.jointCount;

  @override
  int get markerCount => _motion.markerCount;

  @override
  void sample(Duration time, Float32List out) => _motion.sample(time, out);

  @override
  void sampleMarkers(Duration time, Float32List out) =>
      _motion.sampleMarkers(time, out);
}
