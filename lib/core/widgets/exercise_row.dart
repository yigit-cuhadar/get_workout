import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// An exercise in the library, a picker or a Similar list: its [name] with
/// a Custom tag when [custom], its [detail] ("muscle · equipment") under
/// it, a [relation] tag (Alternative, Variation) and a chevron. [onTap]
/// opens it. With [onFavorite] a star at its end, filled when a
/// [favorite], toggles the favourite.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    super.key,
    required this.name,
    required this.detail,
    this.favorite = false,
    this.onFavorite,
    this.custom = false,
    this.relation,
    required this.onTap,
  }) : selected = null,
       enabled = true;

  /// The picker's row: a square checkbox in front, tinted when [selected];
  /// [onTap] toggles it. Not [enabled] (the picker is full), it is drawn in
  /// line-strong and takes no taps.
  const ExerciseRow.pick({
    super.key,
    required this.name,
    required this.detail,
    this.custom = false,
    required bool this.selected,
    this.enabled = true,
    required this.onTap,
  }) : relation = null,
       favorite = false,
       onFavorite = null;

  final String name;
  final String detail;
  final bool favorite;
  final VoidCallback? onFavorite;
  final bool custom;
  final String? relation;
  final bool? selected;
  final bool enabled;
  final VoidCallback onTap;

  static const double _minHeight = 60;
  static const double _inset = 14;

  @override
  Widget build(BuildContext context) {
    final p = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    final selected = this.selected;
    final on = selected ?? false;
    final relation = this.relation;
    final onTap = enabled ? this.onTap : null;
    final row = Row(
      spacing: 12,
      children: [
        if (selected != null)
          ExcludeSemantics(
            child: IgnorePointer(
              ignoring: onTap == null,
              child: ForgeCheckbox(value: on, onChanged: (_) => onTap?.call()),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Row(
                spacing: 6,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w500,
                        color: on
                            ? p.onAccentSoft
                            : enabled
                            ? p.ink
                            : p.lineStrong,
                      ),
                    ),
                  ),
                  if (custom)
                    ForgeTag(AppLocalizations.of(context).customLabel),
                ],
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: enabled
                    ? text.bodySmall
                    : text.bodySmall!.copyWith(color: p.lineStrong),
              ),
            ],
          ),
        ),
        if (relation != null) ForgeTag(relation),
        if (onFavorite case final onFavorite?)
          ForgeIconButton(
            icon: ForgeIcons.star,
            label: favorite
                ? AppLocalizations.of(context).favoriteRemove
                : AppLocalizations.of(context).favoriteAdd,
            toggled: favorite,
            onPressed: onFavorite,
          ),
        if (selected == null)
          ForgeIcon(ForgeIcons.chevronRight, size: 18, color: p.inkMuted),
      ],
    );
    Widget result = Material(
      type: on ? MaterialType.canvas : MaterialType.transparency,
      color: on ? p.accentSoft : null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _inset,
              vertical: Gap.sm,
            ),
            child: row,
          ),
        ),
      ),
    );
    if (selected != null) {
      result = MergeSemantics(
        child: Semantics(checked: on, enabled: enabled, child: result),
      );
    }
    return result;
  }
}
