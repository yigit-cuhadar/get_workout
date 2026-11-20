import 'dart:async';

import 'package:forge_auth/forge_auth.dart';
import 'package:forge_purchases/forge_purchases.dart';

import '../../exercises/domain/vocabulary.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../domain/analytics.dart';

/// Keeps the user properties in step with their sources, each set when it
/// changes, and logs a guest linking an account (`sign_up`) and a sign-in
/// to another account (`login`), told apart on the auth user stream.
/// `acquisition` comes from the purchaser session, which applies the ad
/// attribution.
class AnalyticsSession {
  AnalyticsSession({
    required WatchAuthUser watchAuthUser,
    required ProfileCubit profile,
    required EntitlementCubit entitlement,
    required ProgramListCubit programs,
    required this._analytics,
  }) {
    _subscriptions = [
      watchAuthUser().listen(_userChanged),
      _follow<ProfileState>(profile.state, profile.stream, _profileChanged),
      _follow<EntitlementState>(
        entitlement.state,
        entitlement.stream,
        _entitlementChanged,
      ),
      _follow<ProgramListState>(
        programs.state,
        programs.stream,
        _programsChanged,
      ),
    ];
  }

  final Analytics _analytics;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// The last auth user seen, once one was.
  AuthUser? _user;
  bool _userSeen = false;
  ({Level? level, Goal? goal, int? days})? _profile;
  PremiumTier? _tier;
  bool? _hasProgram;

  static StreamSubscription<S> _follow<S>(
    S current,
    Stream<S> changes,
    void Function(S state) onState,
  ) {
    onState(current);
    return changes.listen(onState);
  }

  void _userChanged(AuthUser? user) {
    final previous = _user;
    final seen = _userSeen;
    _user = user;
    _userSeen = true;
    if (user == null) return;
    final method = signInMethodOf(user);
    if (previous?.id != user.id || previous?.isAnonymous != user.isAnonymous) {
      unawaited(_analytics.account(method));
    }
    if (!seen || previous == null || method == null) return;
    if (previous.id == user.id) {
      if (previous.isAnonymous) unawaited(_analytics.signUp(method));
    } else {
      unawaited(_analytics.login(method));
    }
  }

  void _profileChanged(ProfileState state) {
    if (state.status != ProfileStatus.loaded) return;
    final profile = state.profile;
    final next = (
      level: profile.level,
      goal: profile.goal,
      days: profile.daysPerWeek,
    );
    final previous = _profile;
    _profile = next;
    if (previous?.level != next.level) {
      unawaited(_analytics.level(profile.level));
    }
    if (previous?.goal != next.goal) unawaited(_analytics.goal(profile.goal));
    if (previous?.days != next.days) {
      unawaited(_analytics.daysPerWeek(profile.daysPerWeek));
    }
  }

  void _entitlementChanged(EntitlementState state) {
    final tier = switch (state) {
      EntitlementUnknown() => null,
      EntitlementInactive() => PremiumTier.free,
      EntitlementActive(:final entitlement) =>
        entitlement.isInTrial ? PremiumTier.trial : PremiumTier.premium,
    };
    if (tier == null || tier == _tier) return;
    _tier = tier;
    unawaited(_analytics.premium(tier));
  }

  void _programsChanged(ProgramListState state) {
    if (state.status != ProgramListStatus.ready) return;
    final hasProgram = state.activeProgram != null;
    if (hasProgram == _hasProgram) return;
    _hasProgram = hasProgram;
    unawaited(_analytics.hasProgram(hasProgram));
  }

  Future<void> cancel() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

/// How [user] signs in; null for a guest. An account with several ways
/// names one: Apple, then Google, then email.
SignInMethod? signInMethodOf(AuthUser user) {
  if (user.isAnonymous) return null;
  for (final method in const [
    SignInMethod.apple,
    SignInMethod.google,
    SignInMethod.email,
  ]) {
    if (user.signInMethods.contains(method)) return method;
  }
  return null;
}
