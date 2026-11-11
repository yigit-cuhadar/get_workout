import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../features/settings/domain/user_settings.dart';
import '../features/settings/presentation/settings_cubit.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final _router = buildRouter(sl<AuthCubit>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider.value(value: sl<SettingsCubit>()),
      ],
      child: BlocSelector<SettingsCubit, SettingsState, ThemePreference>(
        selector: (state) => state.settings.themePreference,
        builder: (context, theme) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ForgeTheme.light(),
          darkTheme: ForgeTheme.dark(),
          themeMode: switch (theme) {
            ThemePreference.system => ThemeMode.system,
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
          },
          routerConfig: _router,
        ),
      ),
    );
  }
}
