import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_queries.dart';
import '../domain/program_usecases.dart';

enum ProgramCatalogueStatus {
  loading,
  ready,

  /// Offline, and the cards were never loaded on this device.
  offline,
  failure,
}

class ProgramCatalogueState extends Equatable {
  const ProgramCatalogueState({
    this.status = ProgramCatalogueStatus.loading,
    this.programs = const [],
    this.filter = const CatalogueFilter(),
    this.profile = const TrainingProfile(),
    this.premium,
  });

  final ProgramCatalogueStatus status;

  /// Every live program, by catalogue order.
  final List<CatalogueProgram> programs;
  final CatalogueFilter filter;

  /// The user's answers and equipment, for [recommended] and
  /// [CatalogueFilter.fitsMyEquipment].
  final TrainingProfile profile;

  /// Null while unknown.
  final bool? premium;

  /// The programs [filter] lets through.
  List<CatalogueProgram> get visible => [
    for (final program in programs)
      if (filter.matches(program, profile.equipment)) program,
  ];

  List<Recommendation> get recommended => recommendPrograms(programs, profile);

  /// The days per week the programs have, for the filter.
  List<int> get dayOptions =>
      {for (final program in programs) program.daysPerWeek}.toList()..sort();

  CatalogueProgram? program(String id) =>
      programs.where((program) => program.id == id).firstOrNull;

  ProgramCatalogueState copyWith({
    ProgramCatalogueStatus? status,
    List<CatalogueProgram>? programs,
    CatalogueFilter? filter,
    TrainingProfile? profile,
    bool? Function()? premium,
  }) => ProgramCatalogueState(
    status: status ?? this.status,
    programs: programs ?? this.programs,
    filter: filter ?? this.filter,
    profile: profile ?? this.profile,
    premium: premium != null ? premium() : this.premium,
  );

  @override
  List<Object?> get props => [status, programs, filter, profile, premium];
}

/// The ready-made programs for the whole app, with the filters and what
/// the user's profile and premium status mean for them.
class ProgramCatalogueCubit extends Cubit<ProgramCatalogueState> {
  ProgramCatalogueCubit({
    required this._watchCatalogue,
    required WatchPremium watchPremium,
    required ProfileCubit profile,
    required EquipmentCubit equipment,
  }) : _profile = profile,
       _equipment = equipment,
       super(const ProgramCatalogueState()) {
    _follow();
    _premiumSubscription = watchPremium().listen(
      (premium) => emit(state.copyWith(premium: () => premium)),
      onError: (Object error, StackTrace stack) =>
          Log.e('catalogue', 'premium status failed', error, stack),
    );
    _updateProfile();
    _profileSubscription = profile.stream.listen((_) => _updateProfile());
    _equipmentSubscription = equipment.stream.listen((_) => _updateProfile());
  }

  final WatchCatalogue _watchCatalogue;
  final ProfileCubit _profile;
  final EquipmentCubit _equipment;
  StreamSubscription<List<CatalogueProgram>>? _programsSubscription;
  late final StreamSubscription<bool?> _premiumSubscription;
  late final StreamSubscription<Object?> _profileSubscription;
  late final StreamSubscription<Object?> _equipmentSubscription;

  /// Listens again after a failure.
  void retry() {
    if (state.status == ProgramCatalogueStatus.ready) return;
    emit(state.copyWith(status: ProgramCatalogueStatus.loading));
    _follow();
  }

  void toggleLevel(Level level) => _setFilter(
    state.filter.copyWith(levels: _toggled(state.filter.levels, level)),
  );

  void toggleDays(int days) => _setFilter(
    state.filter.copyWith(
      daysPerWeek: _toggled(state.filter.daysPerWeek, days),
    ),
  );

  void toggleGoal(Goal goal) => _setFilter(
    state.filter.copyWith(goals: _toggled(state.filter.goals, goal)),
  );

  void toggleProfile(EquipmentProfile profile) => _setFilter(
    state.filter.copyWith(profiles: _toggled(state.filter.profiles, profile)),
  );

  void setFitsMyEquipment(bool value) =>
      _setFilter(state.filter.copyWith(fitsMyEquipment: value));

  void clearFilters() => _setFilter(const CatalogueFilter());

  void _setFilter(CatalogueFilter filter) =>
      emit(state.copyWith(filter: filter));

  static Set<T> _toggled<T>(Set<T> values, T value) => values.contains(value)
      ? ({...values}..remove(value))
      : {...values, value};

  void _follow() {
    unawaited(_programsSubscription?.cancel());
    _programsSubscription = _watchCatalogue().listen(
      (programs) => emit(
        state.copyWith(
          status: ProgramCatalogueStatus.ready,
          programs: programs,
        ),
      ),
      onError: (Object error) {
        // Cards on screen stay; they are only as old as the last change.
        if (state.status == ProgramCatalogueStatus.ready) return;
        emit(
          state.copyWith(
            status: error is NetworkFailure
                ? ProgramCatalogueStatus.offline
                : ProgramCatalogueStatus.failure,
          ),
        );
      },
    );
  }

  void _updateProfile() {
    final profile = _profile.state.profile;
    emit(
      state.copyWith(
        profile: TrainingProfile(
          goal: profile.goal,
          level: profile.level,
          daysPerWeek: profile.daysPerWeek,
          equipment: _equipment.state.owned,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _programsSubscription?.cancel();
    await _premiumSubscription.cancel();
    await _profileSubscription.cancel();
    await _equipmentSubscription.cancel();
    return super.close();
  }
}
