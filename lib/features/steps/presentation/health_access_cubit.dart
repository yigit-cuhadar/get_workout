import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../domain/steps.dart';
import '../domain/steps_usecases.dart';

/// Where step access stands, for the settings' Connected apps row; null
/// until known or when it could not be told. [load] again when the app
/// comes back: access can change in the system settings at any time.
class HealthAccessCubit extends Cubit<StepsAccess?> {
  HealthAccessCubit(this._getAccess, this._openSettings) : super(null);

  final GetStepsAccess _getAccess;
  final OpenHealthSettings _openSettings;

  Future<void> load() async {
    final result = await _getAccess();
    if (result.failureOrNull case final failure?) {
      Log.e('steps', 'access unknown: ${failure.message}');
    }
    if (!isClosed) emit(result.valueOrNull);
  }

  /// Health Connect's settings or the app's iOS settings.
  Future<void> openSettings() async {
    final result = await _openSettings();
    if (result.failureOrNull case final failure?) {
      Log.e('steps', 'settings not opened: ${failure.message}');
    }
  }
}
