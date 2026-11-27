import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';

/// [message] as a first-use tip until it is dismissed: then [tip] is seen
/// for good and nothing shows. Nothing shows while the settings load.
class OnceTip extends StatelessWidget {
  const OnceTip(this.tip, this.message, {super.key});

  final Tip tip;
  final String message;

  @override
  Widget build(BuildContext context) {
    final seen = context.select(
      (SettingsCubit cubit) =>
          cubit.state.loaded ? cubit.state.settings.seenTips : null,
    );
    if (seen == null || seen.contains(tip)) return const SizedBox.shrink();
    return TipBanner(
      message: message,
      dismissLabel: AppLocalizations.of(context).tipDismiss,
      onDismiss: () => context.read<SettingsCubit>().tipSeen(tip),
    );
  }
}
