import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';

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

/// The body model, parsed once per app run and shared by every screen that
/// shows it. Nothing is loaded until the first [load].
///
/// The model is a bundled asset and a renderer type, not domain data, so the
/// module injects the loader instead of a use case.
class BodyModelCubit extends Cubit<BodyModelState> {
  BodyModelCubit(this._loadModel) : super(const BodyModelLoading());

  final Future<Model3D> Function() _loadModel;
  bool _started = false;

  /// Starts loading unless the model is loaded or loading; after a failure,
  /// tries again.
  Future<void> load() async {
    if (_started && state is! BodyModelFailed) return;
    _started = true;
    if (state is BodyModelFailed) emit(const BodyModelLoading());
    try {
      final model = await _loadModel();
      if (!isClosed) emit(BodyModelReady(model));
    } catch (error, stack) {
      Log.e('model', 'Body model failed to load', error, stack);
      if (!isClosed) emit(const BodyModelFailed());
    }
  }
}
