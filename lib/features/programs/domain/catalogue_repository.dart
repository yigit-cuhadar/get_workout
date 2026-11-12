import 'package:forge_core/forge_core.dart';

import 'catalogue_program.dart';
import 'program.dart';

/// The ready-made programs: cards in `programs/{id}`, days in
/// `programs/{id}/detail/main`. Read through Firestore's cache, so cards
/// and days once loaded are there offline.
abstract interface class CatalogueRepository {
  /// The live programs by `order`, again on every change. Cards that cannot
  /// be read are skipped. While nothing is cached and the device is
  /// offline, a [NetworkFailure] arrives instead and listening goes on, so
  /// the cards follow once the device is online.
  Stream<List<CatalogueProgram>> watchPrograms();

  /// The days of program [id]: a [PermissionFailure] for a premium program
  /// without an active entitlement, a [NetworkFailure] when they are not
  /// cached and the device is offline, a [NotFoundFailure] when there are
  /// none.
  Future<Result<List<ProgramDay>>> getDays(String id);
}
