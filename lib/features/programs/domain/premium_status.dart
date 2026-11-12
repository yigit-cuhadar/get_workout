/// Whether whoever is signed in has premium. The subscription feature
/// provides it; until then nobody has.
abstract interface class PremiumStatus {
  /// Null while unknown, e.g. after a user change; again on every change.
  Stream<bool?> watch();
}
