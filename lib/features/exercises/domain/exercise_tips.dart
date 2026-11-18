import '../../settings/domain/user_settings.dart';

/// Whether the Exercises tab tells what the body model does, until the tip
/// is seen; not while the user's settings ([seen]) are unknown.
bool muscleModelTipDue(Set<Tip>? seen) =>
    seen != null && !seen.contains(Tip.muscleModel);
