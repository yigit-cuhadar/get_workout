import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
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
    this.query = '',
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

  /// The search text, as typed.
  final String query;

  /// Whether a search is on.
  bool get searching => query.trim().isNotEmpty;

  /// The programs [filter] lets through whose name in [language] holds the
  /// search text, ignoring case.
  List<CatalogueProgram> shown(String language) {
    final text = query.trim().toLowerCase();
    return [
      for (final program in visible)
        if (program.text(language).name.toLowerCase().contains(text)) program,
    ];
  }

  /// The programs [filter] lets through.
  List<CatalogueProgram> get visible => [
    for (final program in programs)
      if (filter.matches(program, profile.equipment)) program,
  ];

  /// Whether the filters leave anything out.
  bool get filtering => filter.isActive(profile.equipment);

  /// How many filter values are on.
  int get filterCount => filter.activeCount(profile.equipment);

  List<Recommendation> get recommended => recommendedWithout(null);

  /// [recommended] without [program] (the active program's source), the
  /// next best in its place.
  List<Recommendation> recommendedWithout(CatalogueProgram? program) =>
      recommendPrograms([
        for (final each in programs)
          if (each != program) each,
      ], profile);

  /// The filter the catalogue opens with: the user's equipment type alone;
  /// null while the equipment is unknown.
  CatalogueFilter? get defaultFilter => switch (profile.equipment) {
    null => null,
    final owned => CatalogueFilter(profiles: {EquipmentProfile.typeOf(owned)}),
  };

  /// Whether the catalogue shows its recommendations: no search, and no
  /// filter or only [defaultFilter].
  bool get recommending =>
      !searching && (!filtering || filter == defaultFilter);

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
    String? query,
  }) => ProgramCatalogueState(
    status: status ?? this.status,
    programs: programs ?? this.programs,
    filter: filter ?? this.filter,
    profile: profile ?? this.profile,
    premium: premium != null ? premium() : this.premium,
    query: query ?? this.query,
  );

  @override
  List<Object?> get props => [
    status,
    programs,
    filter,
    profile,
    premium,
    query,
  ];
}

/// The ready-made programs for the whole app, with the filters and what
/// the user's profile and premium status mean for them.
class ProgramCatalogueCubit extends Cubit<ProgramCatalogueState> {
  ProgramCatalogueCubit({
    required WatchAuthUser watchAuthUser,
    required WatchCatalogue watchCatalogue,
    required WatchPremium watchPremium,
    required ProfileCubit profile,
    required EquipmentCubit equipment,
    Duration retryDelay = const Duration(seconds: 1),
  }) : _profile = profile,
       _equipment = equipment,
       super(const ProgramCatalogueState()) {
    // Listens again for every user (the rules need one, and signing out
    // ends the listener with an error) and after every failure.
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: (_) => watchCatalogue(),
      onUser: (_) {},
      onData: (programs) => emit(
        state.copyWith(
          status: ProgramCatalogueStatus.ready,
          programs: programs,
        ),
      ),
      onError: (error) {
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
      logTag: 'catalogue',
      retryDelay: retryDelay,
    );
    _premiumSubscription = watchPremium().listen(
      (premium) => emit(state.copyWith(premium: () => premium)),
      onError: (Object error, StackTrace stack) =>
          Log.e('catalogue', 'premium status failed', error, stack),
    );
    _updateProfile();
    _profileSubscription = profile.stream.listen((_) => _updateProfile());
    _equipmentSubscription = equipment.stream.listen((_) => _updateProfile());
  }

  final ProfileCubit _profile;
  final EquipmentCubit _equipment;
  late final UserStreamFollower<List<CatalogueProgram>> _follower;
  late final StreamSubscription<bool?> _premiumSubscription;
  late final StreamSubscription<Object?> _profileSubscription;
  late final StreamSubscription<Object?> _equipmentSubscription;
  bool _defaultPending = false;

  /// Listens again at once after a failure.
  void retry() {
    if (state.status != ProgramCatalogueStatus.ready) {
      emit(state.copyWith(status: ProgramCatalogueStatus.loading));
    }
    _follower.resume();
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

  /// Sets [ProgramCatalogueState.defaultFilter], each time the catalogue
  /// page opens; while the equipment is unknown, once it is known unless
  /// the filters change first.
  void openCatalogue() {
    _defaultPending = true;
    _applyDefaultFilter();
  }

  void search(String query) => emit(state.copyWith(query: query));

  void _setFilter(CatalogueFilter filter) {
    _defaultPending = false;
    emit(state.copyWith(filter: filter));
  }

  void _applyDefaultFilter() {
    final filter = state.defaultFilter;
    if (!_defaultPending || filter == null) return;
    _setFilter(filter);
  }

  static Set<T> _toggled<T>(Set<T> values, T value) => values.contains(value)
      ? ({...values}..remove(value))
      : {...values, value};

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
    _applyDefaultFilter();
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    await _premiumSubscription.cancel();
    await _profileSubscription.cancel();
    await _equipmentSubscription.cancel();
    return super.close();
  }
}
