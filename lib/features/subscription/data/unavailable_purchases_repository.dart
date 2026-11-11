import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';

/// A release build without RevenueCat keys: nobody is entitled and every
/// store call reports the store as unavailable.
class UnavailablePurchasesRepository implements PurchasesRepository {
  const UnavailablePurchasesRepository();

  static const _unavailable = Err<Never>(
    PurchaseFailure(
      PurchaseFailureReason.storeUnavailable,
      'No purchases backend is configured',
    ),
  );

  @override
  Future<Result<void>> configure() async => const Ok(null);

  @override
  Future<Result<Entitlement>> identify(String userId) async =>
      const Ok(Entitlement.none());

  @override
  Future<Result<Entitlement>> reset() async => const Ok(Entitlement.none());

  @override
  Stream<Entitlement> watchEntitlement() => const Stream.empty();

  @override
  Future<Result<Entitlement>> refresh() async => const Ok(Entitlement.none());

  @override
  Future<Result<Offering>> offering() async => _unavailable;

  @override
  Future<Result<Entitlement>> purchase(Plan plan) async => _unavailable;

  @override
  Future<Result<Entitlement>> restore() async => _unavailable;

  @override
  Future<Result<Uri>> managementUrl() async => _unavailable;
}
