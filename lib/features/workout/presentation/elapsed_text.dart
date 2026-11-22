import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import 'workout_text.dart';

/// The time since [since], counting every second.
class ElapsedText extends StatelessWidget {
  const ElapsedText({super.key, required this.since, this.style});

  final DateTime since;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => EverySecond(
    builder: (context) => Text(
      AppLocalizations.of(context)
          .elapsedText(DateTime.now().difference(since)),
      style: style,
    ),
  );
}

/// Builds with [builder] again every second.
class EverySecond extends StatefulWidget {
  const EverySecond({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<EverySecond> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Builds with [builder] again each time another whole minute since
/// [since] passes.
class EveryMinute extends StatefulWidget {
  const EveryMinute({super.key, required this.since, required this.builder});

  final DateTime since;
  final WidgetBuilder builder;

  @override
  State<EveryMinute> createState() => _EveryMinuteState();
}

class _EveryMinuteState extends State<EveryMinute> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(EveryMinute old) {
    super.didUpdateWidget(old);
    if (old.since != widget.since) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    const minute = Duration.millisecondsPerMinute;
    final into =
        DateTime.now().difference(widget.since).inMilliseconds % minute;
    _timer = Timer(Duration(milliseconds: minute - into), () {
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
