import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/exercise_usecases.dart';

/// True once the server refused a save or delete of a custom exercise that
/// already looked done; tell the user, then call [shown].
class CustomWriteRejectionsCubit extends Cubit<bool> {
  CustomWriteRejectionsCubit(WatchRejectedCustomExerciseWrites watch)
    : super(false) {
    _subscription = watch().listen((_) => emit(true));
  }

  late final StreamSubscription<Object?> _subscription;

  void shown() => emit(false);

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
