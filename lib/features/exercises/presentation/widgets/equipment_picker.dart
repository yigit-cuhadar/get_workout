import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../equipment_cubit.dart';
import '../vocabulary_labels.dart';

/// Lets the user tick the equipment they own. Completes with true once they
/// saved. Bodyweight is always owned, so it is not offered. Opened from the
/// filters sheet, it stacks over it and returns to it.
Future<bool> showEquipmentPicker(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<EquipmentCubit>();
  final owned = await showForgeCheckSheet<Equipment>(
    context: context,
    title: l10n.equipmentTitle,
    subtitle: l10n.equipmentInfo,
    values: [
      for (final item in Equipment.values)
        if (item != Equipment.bodyweight) item,
    ],
    selected: cubit.state.owned ?? const {},
    labelOf: l10n.equipmentName,
    saveLabel: l10n.equipmentSave,
  );
  if (owned == null) return false;
  // Not awaited: offline, a write completes only once it reaches the
  // server, but the cubit sees it from the local cache at once.
  unawaited(cubit.save(owned));
  return true;
}
