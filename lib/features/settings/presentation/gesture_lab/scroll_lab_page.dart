import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Scroll physics a list can have.
enum ScrollOption {
  flutterDefault(
    'Default',
    "The app today: iOS bouncing, Flutter's normal deceleration",
    null,
  ),
  fast(
    'Fast',
    'Bouncing that slows sooner, closer to a native iOS list',
    BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
      parent: RangeMaintainingScrollPhysics(),
    ),
  ),
  clamping(
    'Clamp',
    'Android-like: stops at the ends with no bounce',
    ClampingScrollPhysics(),
  ),
  always(
    'Always',
    'Bouncing that also pulls when the content is shorter than the screen',
    BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
  );

  const ScrollOption(this.label, this.detail, this.physics);

  final String label;
  final String detail;

  /// Null: the platform's own.
  final ScrollPhysics? physics;
}

/// A long list whose physics and scrollbar switch live. Developer tooling,
/// so its text is not localized.
class ScrollLabPage extends StatefulWidget {
  const ScrollLabPage({super.key});

  @override
  State<ScrollLabPage> createState() => _ScrollLabPageState();
}

class _ScrollLabPageState extends State<ScrollLabPage> {
  final _controller = ScrollController();
  var _option = ScrollOption.flutterDefault;
  var _scrollbar = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: _controller,
      physics: _option.physics,
      padding: const EdgeInsets.all(Gap.md),
      itemCount: 100,
      itemBuilder: (_, i) => ListRow(title: 'Row ${i + 1}'),
    );
    return Scaffold(
      appBar: const ForgeAppBar(title: 'Scroll physics'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ForgeSegmentedControl<ScrollOption>(
                  segments: [
                    for (final option in ScrollOption.values)
                      ForgeSegment(value: option, label: option.label),
                  ],
                  selected: _option,
                  onChanged: (option) => setState(() => _option = option),
                ),
                ListRowCard(
                  children: [
                    ListRow(
                      title: 'Active: ${_option.label}',
                      detail: _option.detail,
                    ),
                    ListRow(
                      title: 'Scrollbar',
                      trailing: ForgeSwitch(
                        value: _scrollbar,
                        onChanged: (on) => setState(() => _scrollbar = on),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _scrollbar
                ? Scrollbar(controller: _controller, child: list)
                : list,
          ),
        ],
      ),
    );
  }
}
