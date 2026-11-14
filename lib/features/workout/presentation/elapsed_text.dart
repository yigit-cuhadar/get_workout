import 'dart:async';

import 'package:flutter/material.dart';

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
