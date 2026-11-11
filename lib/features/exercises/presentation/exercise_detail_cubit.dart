import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise.dart';
import '../domain/exercise_queries.dart';
import '../domain/exercise_usecases.dart';
import '../domain/vocabulary.dart';
import 'equipment_cubit.dart';
import 'exercise_catalogue_cubit.dart';

sealed class ExerciseDetailState extends Equatable {
  const ExerciseDetailState();

  @override
  List<Object?> get props => [];
}

/// The catalogue has not arrived yet.
final class DetailLoading extends ExerciseDetailState {
  const DetailLoading();
}

/// The catalogue could not be loaded.
final class DetailFailed extends ExerciseDetailState {
  const DetailFailed();
}

/// No exercise has this id, e.g. it was retired or deleted since it was
/// linked.
final class DetailNotFound extends ExerciseDetailState {
  const DetailNotFound();
}

final class DetailReady extends ExerciseDetailState {
  const DetailReady(
    this.exercise, {
    this.alternatives = const [],
    this.variations = const [],
    this.deleting = false,
    this.deleteFailure,
  });

  final Exercise exercise;
  final List<Exercise> alternatives;
  final List<Exercise> variations;

  /// A delete of this custom exercise is starting.
  final bool deleting;

  /// Why the last delete failed; the exercise is still there.
  final Failure? deleteFailure;

  DetailReady _copyWith({bool deleting = false, Failure? deleteFailure}) =>
      DetailReady(
        exercise,
        alternatives: alternatives,
        variations: variations,
        deleting: deleting,
        deleteFailure: deleteFailure,
      );

  @override
  List<Object?> get props => [
    exercise,
    alternatives,
    variations,
    deleting,
    deleteFailure,
  ];
}

/// The custom exercise was deleted here; the page closes. Final.
final class DetailDeleted extends ExerciseDetailState {
  const DetailDeleted();
}

/// One exercise with its alternatives (preferring the user's equipment) and
/// variations, kept current as the catalogue and the equipment change. A
/// custom exercise can be deleted here.
class ExerciseDetailCubit extends Cubit<ExerciseDetailState> {
  ExerciseDetailCubit(
    this.exerciseId, {
    required ExerciseCatalogueCubit catalogue,
    required EquipmentCubit equipment,
    required this._getCurrentUser,
    required this._deleteCustomExercise,
  }) : _catalogue = catalogue.state,
       _owned = equipment.state.owned,
       super(const DetailLoading()) {
    _update();
    _subscriptions = [
      catalogue.stream.listen((state) {
        _catalogue = state;
        _update();
      }),
      equipment.stream.map((state) => state.owned).distinct().listen((owned) {
        _owned = owned;
        _update();
      }),
    ];
  }

  final String exerciseId;
  final GetCurrentUser _getCurrentUser;
  final DeleteCustomExercise _deleteCustomExercise;
  late final List<StreamSubscription<Object?>> _subscriptions;
  ExerciseCatalogueState _catalogue;
  Set<Equipment>? _owned;

  void _update() {
    // While deleting and after, the catalogue dropping the exercise is no
    // news; the page closes instead of showing it missing.
    final current = state;
    if (current is DetailDeleted ||
        (current is DetailReady && current.deleting)) {
      return;
    }
    emit(_current());
  }

  ExerciseDetailState _current() => switch (_catalogue) {
    CatalogueLoading() => const DetailLoading(),
    CatalogueFailed() => const DetailFailed(),
    CatalogueReady(:final exercises) => _detail(exercises),
  };

  /// Deletes the shown custom exercise; does nothing for a catalogue one.
  Future<void> delete() async {
    final current = state;
    final uid = _getCurrentUser()?.id;
    if (current is! DetailReady ||
        !current.exercise.isCustom ||
        current.deleting ||
        uid == null) {
      return;
    }
    emit(current._copyWith(deleting: true));
    final result = await _deleteCustomExercise((uid: uid, id: exerciseId));
    if (isClosed) return;
    if (result.failureOrNull case final failure?) {
      // The catalogue may have changed meanwhile.
      final latest = _current();
      emit(
        latest is DetailReady
            ? latest._copyWith(deleteFailure: failure)
            : latest,
      );
    } else {
      emit(const DetailDeleted());
    }
  }

  ExerciseDetailState _detail(List<Exercise> catalogue) {
    final exercise = catalogue.where((e) => e.id == exerciseId).firstOrNull;
    if (exercise == null) return const DetailNotFound();
    return DetailReady(
      exercise,
      // Unknown equipment counts as bodyweight only.
      alternatives: alternativesFor(
        exercise,
        catalogue,
        owned: _owned ?? const {},
      ),
      variations: variationsOf(exercise, catalogue),
    );
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
