import 'package:forge_core/forge_core.dart';

/// The chime that says a rest is over, played in the app.
abstract interface class RestChime {
  Future<Result<void>> play();
}
