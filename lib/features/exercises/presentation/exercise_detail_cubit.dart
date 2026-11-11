import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise.dart';
import '../domain/exercise_queries.dart';
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

/// No live exercise has this id, e.g. it was retired since it was linked.
final class DetailNotFound extends ExerciseDetailState {
  const DetailNotFound();
}

final class DetailReady extends ExerciseDetailState {
  const DetailReady(
    this.exercise, {
    this.alternatives = const [],
    this.variations = const [],
  });

  final Exercise exercise;
  final List<Exercise> alternatives;
  final List<Exercise> variations;

  @override
  List<Object?> get props => [exercise, alternatives, variations];
}

/// One exercise with its alternatives (preferring the user's equipment) and
/// variations, kept current as the catalogue and the equipment change.
class ExerciseDetailCubit extends Cubit<ExerciseDetailState> {
  ExerciseDetailCubit(
    this.exerciseId, {
    required ExerciseCatalogueCubit catalogue,
    required EquipmentCubit equipment,
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
  late final List<StreamSubscription<Object?>> _subscriptions;
  ExerciseCatalogueState _catalogue;
  Set<Equipment>? _owned;

  void _update() => emit(switch (_catalogue) {
    CatalogueLoading() => const DetailLoading(),
    CatalogueFailed() => const DetailFailed(),
    CatalogueReady(:final exercises) => _detail(exercises),
  });

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
