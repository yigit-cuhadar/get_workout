import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/widgets/settings_group.dart';
import 'swipe_back_route.dart';

/// The developer entry to the [GestureLabPage] at the end of Profile, or
/// null in a [release] build.
Widget? gestureLabEntry({required bool release}) => release
    ? null
    : SettingsGroup(
        title: 'Developer',
        rows: [
          Builder(
            builder: (context) => ListRow(
              title: 'Gesture lab',
              detail: 'Try back-swipe and scroll alternatives',
              end: ListRowEnd.chevron,
              onTap: () => context.push(Routes.gestureLab),
            ),
          ),
        ],
      );

/// Ways of leaving a pushed page and of scrolling, to try on a phone.
/// Developer tooling, so its text is not localized. It pushes its test
/// pages itself: the kind of route is what each one tries.
class GestureLabPage extends StatelessWidget {
  const GestureLabPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ForgeAppBar(title: 'Gesture lab'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      children: [
        SettingsColumn(
          children: [
            SettingsGroup(
              title: 'Back swipe',
              rows: [
                for (final option in BackOption.values)
                  ListRow(
                    title: option.title,
                    detail: option.detail,
                    end: ListRowEnd.chevron,
                    onTap: () => option.open(context),
                  ),
              ],
            ),
            SettingsGroup(
              title: 'Scroll',
              rows: [
                ListRow(
                  title: 'Scroll physics',
                  detail: 'A long list that switches physics live',
                  end: ListRowEnd.chevron,
                  onTap: () => context.push(Routes.gestureLabScroll),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

/// One way a pushed page can be left.
enum BackOption {
  flutterDefault(
    'A',
    'Flutter default',
    'The app today: an iOS slide, swiped back from the left edge only',
  ),
  fullWidth(
    'B',
    'Full-width swipe',
    'Swipe right from anywhere on the page, as in native iOS apps',
  ),
  fullscreenDialog(
    'C',
    'Full-screen dialog',
    'Slides up; only the close button leaves, no swipe',
  ),
  sheet('D', 'iOS sheet', 'A card over the page; drag it down to close'),
  blocked(
    'E',
    'Unsaved changes, swipe blocked',
    'The app today: PopScope(canPop: false) turns the swipe off',
  ),
  edgeConfirm(
    'F',
    'Unsaved changes, edge swipe asks',
    'Swipe from the left edge; letting go asks to discard',
  ),
  fullWidthConfirm(
    'G',
    'Unsaved changes, full-width swipe asks',
    'Swipe from anywhere; letting go asks to discard',
  );

  const BackOption(this.code, this.label, this.detail);

  final String code;
  final String label;
  final String detail;

  String get title => '$code · $label';

  /// Whether the page acts as one with unsaved changes.
  bool get guarded =>
      this == blocked || this == edgeConfirm || this == fullWidthConfirm;

  PageRoute<void> get route {
    Widget page(BuildContext _) => LabTestPage(option: this);
    return switch (this) {
      flutterDefault || blocked => MaterialPageRoute(builder: page),
      fullWidth ||
      fullWidthConfirm => SwipeBackRoute(builder: page, fullWidth: true),
      edgeConfirm => SwipeBackRoute(builder: page, fullWidth: false),
      fullscreenDialog => MaterialPageRoute(
        builder: page,
        fullscreenDialog: true,
      ),
      sheet => CupertinoSheetRoute(
        scrollableBuilder: (_, controller) =>
            LabTestPage(option: this, controller: controller),
      ),
    };
  }

  // A sheet covers the tab bar too, as `showCupertinoSheet` puts it.
  void open(BuildContext context) =>
      Navigator.of(context, rootNavigator: this == sheet).push(route);
}

/// The page each [BackOption] opens: a field and a long list. A guarded
/// option's page acts as if it had unsaved changes.
class LabTestPage extends StatelessWidget {
  const LabTestPage({super.key, required this.option, this.controller});

  final BackOption option;

  /// The sheet's, so dragging down at the top of the list closes it.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: ForgeAppBar(title: option.code),
      body: ListView(
        controller: controller,
        padding: const EdgeInsets.all(Gap.md),
        children: [
          Text(option.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Gap.xs),
          Text(option.detail),
          const SizedBox(height: Gap.md),
          const ForgeTextField(label: 'Note', hint: 'Type to try the keyboard'),
          const SizedBox(height: Gap.md),
          ListRowCard(
            children: [for (var i = 1; i <= 40; i++) ListRow(title: 'Row $i')],
          ),
        ],
      ),
    );
    if (!option.guarded) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: page,
    );
  }
}

Future<bool> _confirmDiscard(BuildContext context) async =>
    await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: 'Discard changes?',
        message: 'This page acts as if it had unsaved changes.',
        action: ForgeButton(
          label: 'Discard',
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: 'Keep editing',
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
    ) ??
    false;
