import 'package:forge_core/forge_core.dart';

/// Whether the user was asked for step access on this device. HealthKit
/// never tells, so the app remembers it itself.
abstract interface class StepsPrompt {
  Future<Result<bool>> askedHere();

  Future<Result<void>> markAskedHere();
}
