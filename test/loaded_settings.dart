import 'package:bloc_test/bloc_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

/// A settings cubit holding loaded defaults with [seenTips], for screens
/// that show first-use tips.
SettingsCubit loadedSettings({Set<Tip> seenTips = const {}}) {
  final cubit = _SettingsCubit();
  when(() => cubit.state).thenReturn(
    SettingsState(
      UserSettings.defaultsFor(null).copyWith(seenTips: seenTips),
      loaded: true,
    ),
  );
  registerFallbackValue(Tip.effort);
  when(() => cubit.tipSeen(any())).thenAnswer((_) async {});
  return cubit;
}
