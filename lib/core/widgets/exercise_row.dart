import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// An exercise in the library, a picker or a Similar list: its [name] with
/// a star when a [favorite] and a Custom tag when [custom], its [detail]
/// ("muscle · equipment") under it, a [relation] tag (Alternative,
/// Variation) and a chevron. [onTap] opens it.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    super.key,
    required this.name,
    required this.detail,
    this.favorite = false,
    this.custom = false,
    this.relation,
    required this.onTap,
  }) : selected = null;

  /// The picker's row: a square checkbox in front, tinted when [selected];
  /// [onTap] toggles it.
  const ExerciseRow.pick({
    super.key,
    required this.name,
    required this.detail,
    this.favorite = false,
    this.custom = false,
    required bool this.selected,
    required this.onTap,
  }) : relation = null;

  final String name;
  final String detail;
  final bool favorite;
  final bool custom;
  final String? relation;
  final bool? selected;
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
    final row = Row(
      spacing: 12,
      children: [
        if (selected != null)
          ExcludeSemantics(
            child: ForgeCheckbox(value: on, onChanged: (_) => onTap()),
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
                        color: on ? p.onAccentSoft : p.ink,
                      ),
                    ),
                  ),
                  if (favorite)
                    ForgeIcon(
                      ForgeIcons.star,
                      size: 14,
                      filled: true,
                      color: p.accent,
                      semanticLabel: AppLocalizations.of(context)
                          .exerciseRowFavorite,
                    ),
                  if (custom)
                    ForgeTag(AppLocalizations.of(context).customLabel),
                ],
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        if (relation != null) ForgeTag(relation),
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
        child: Semantics(checked: on, child: result),
      );
    }
    return result;
  }
}
