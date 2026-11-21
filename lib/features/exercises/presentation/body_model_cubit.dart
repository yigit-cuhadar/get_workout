import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';

import '../../../core/user_stream_follower.dart';
import '../../profile/domain/profile_usecases.dart';
import '../../profile/domain/user_profile.dart';

sealed class BodyModelState extends Equatable {
  const BodyModelState();

  @override
  List<Object?> get props => [];
}

final class BodyModelLoading extends BodyModelState {
  const BodyModelLoading();
}

final class BodyModelReady extends BodyModelState {
  const BodyModelReady(this.model);

  final Model3D model;

  @override
  List<Object?> get props => [model];
}

final class BodyModelFailed extends BodyModelState {
  const BodyModelFailed();
}

/// The body model matching the signed-in user's sex: the female model for
/// a user who answered female, the male one otherwise (also before the
/// answer). Each model is parsed at most once per app run and shared by
/// every screen that shows it. Nothing is loaded until the first [load];
/// after that, a change of sex loads the other model.
///
/// The model is a bundled asset and a renderer type, not domain data, so the
/// module injects the loader instead of a use case.
class BodyModelCubit extends Cubit<BodyModelState> {
  BodyModelCubit({
    required this._loadModel,
    required WatchAuthUser watchAuthUser,
    required WatchProfile watchProfile,
  }) : super(const BodyModelLoading()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: (uid) => watchProfile(uid).map((profile) => profile.sex),
      onUser: (uid) {
        if (uid == null) _setSex(Sex.male);
      },
      onData: (sex) => _setSex(sex ?? Sex.male),
      logTag: 'model',
    );
  }

  final Future<Model3D> Function(Sex sex) _loadModel;
  late final UserStreamFollower<Sex?> _follower;
  final _models = <Sex, Model3D>{};
  Sex _sex = Sex.male;
  bool _started = false;
  bool _loading = false;

  /// Starts loading the current model unless it is loaded or loading; after
  /// a failure, tries again.
  Future<void> load() async {
    _started = true;
    await _show();
  }

  void _setSex(Sex sex) {
    if (sex == _sex) return;
    _sex = sex;
    if (_started) unawaited(_show());
  }

  Future<void> _show() async {
    final sex = _sex;
    if (_models[sex] case final model?) {
      emit(BodyModelReady(model));
      return;
    }
    if (_loading) return;
    _loading = true;
    if (state is! BodyModelLoading) emit(const BodyModelLoading());
    try {
      final model = await _loadModel(sex);
      _models[sex] = model;
    } catch (error, stack) {
      Log.e('model', 'Body model failed to load', error, stack);
      _loading = false;
      if (!isClosed && sex == _sex) emit(const BodyModelFailed());
      return;
    }
    _loading = false;
    if (isClosed) return;
    // The sex may have changed while this one loaded.
    await _show();
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
