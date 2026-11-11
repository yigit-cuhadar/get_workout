import '../domain/premium_status.dart';

/// Nobody has premium, until the subscription feature registers its own
/// [PremiumStatus].
class NoPremium implements PremiumStatus {
  const NoPremium();

  @override
  Stream<bool?> watch() => Stream.value(false);
}
