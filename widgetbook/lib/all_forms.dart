import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:widgetbook/widgetbook.dart';

/// [directories] with an "All forms" use case first in every component of
/// more than one use case: each of its use cases framed under its name, on
/// one scrolling page.
List<WidgetbookNode> withAllForms(List<WidgetbookNode> directories) => [
  for (final node in directories) _withAllForms(node),
];

WidgetbookNode _withAllForms(WidgetbookNode node) => switch (node) {
  WidgetbookComponent(:final useCases) when useCases.length > 1 =>
    WidgetbookComponent(
      name: node.name,
      isInitiallyExpanded: node.isInitiallyExpanded,
      useCases: [
        WidgetbookUseCase(
          name: 'All forms',
          builder: (_) => _AllForms(useCases),
        ),
        ...useCases,
      ],
    ),
  WidgetbookComponent() || WidgetbookUseCase() => node,
  _ => node.copyWith(children: node.children?.map(_withAllForms).toList()),
};

/// [useCases] side by side, wrapping, each at its natural size.
class _AllForms extends StatefulWidget {
  const _AllForms(this.useCases);

  final List<WidgetbookUseCase> useCases;

  @override
  State<_AllForms> createState() => _AllFormsState();
}

class _AllFormsState extends State<_AllForms> {
  // The tiles register their knobs here instead of in the knobs panel, so
  // each shows its own defaults and shared labels do not collide.
  final _knobs = WidgetbookState(
    root: WidgetbookRoot(children: []),
    previewMode: true,
  );

  @override
  void dispose() {
    _knobs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WidgetbookScope(
      state: _knobs,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.md),
        child: Wrap(
          spacing: Gap.lg,
          runSpacing: Gap.lg,
          children: [
            for (final useCase in widget.useCases)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(useCase.name, style: theme.textTheme.labelMedium),
                  const SizedBox(height: Gap.xs),
                  DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: ClipRect(
                      child: _NaturalSize(
                        child: Builder(builder: useCase.builder),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Sizes its child to its intrinsic size, or to a phone screen when it has
/// none, as pages that fill the screen (scaffolds, scroll views) do.
class _NaturalSize extends SingleChildRenderObjectWidget {
  const _NaturalSize({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNaturalSize();
}

class _RenderNaturalSize extends RenderProxyBox {
  static const _phone = Size(390, 844);

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final maxWidth = math.min(_phone.width, constraints.maxWidth);
    try {
      final natural = child!.getMaxIntrinsicWidth(double.infinity);
      final width = natural > 0 ? math.min(natural, maxWidth) : maxWidth;
      final height = child!.getMaxIntrinsicHeight(width);
      if (height > 0 && height.isFinite) {
        return BoxConstraints.loose(Size(width, height));
      }
    } on AssertionError {
      // Viewports and layout builders refuse intrinsic sizes in debug mode.
    }
    return BoxConstraints.tight(Size(maxWidth, _phone.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    child!.getDryLayout(_childConstraints(constraints)),
  );

  @override
  void performLayout() {
    child!.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child!.size);
  }
}
