import '../../settings/domain/user_settings.dart';

// [seen] is null while the user's settings are not known: no tip shows
// then, so none is marked seen over what is stored.

/// Whether the set bar's effort question tells what it is for, until the
/// tip is seen.
bool effortTipDue(Set<Tip>? seen) => seen != null && !seen.contains(Tip.effort);

/// Whether the add-set sheet tells what the set types are.
bool setTypesTipDue(Set<Tip>? seen) =>
    seen != null && !seen.contains(Tip.setTypes);

/// Whether the workout in progress tells that warm-ups were [added] to it
/// automatically, until the tip is seen.
bool autoWarmupsTipDue(Set<Tip>? seen, {required bool added}) =>
    seen != null && !seen.contains(Tip.autoWarmups) && added;
