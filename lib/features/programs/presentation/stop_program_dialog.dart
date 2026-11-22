import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';

/// Asks before program [name] stops; true once confirmed.
Future<bool> confirmStopProgram(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showForgeDialog<bool>(
    context: context,
    builder: (context) => ForgeDialog(
      title: l10n.programStopTitle,
      message: l10n.programStopBody(name),
      action: ForgeButton(
        label: l10n.programStopConfirm,
        variant: ForgeButtonVariant.danger,
        onPressed: () => Navigator.pop(context, true),
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context, false),
      ),
    ),
  );
  return confirmed ?? false;
}
