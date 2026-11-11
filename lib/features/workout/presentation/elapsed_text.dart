import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'workout_text.dart';

/// The time since [since], counting every second.
class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, required this.since, this.style});

  final DateTime since;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
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
  Widget build(BuildContext context) => Text(
    AppLocalizations.of(context)
        .elapsedText(DateTime.now().difference(widget.since)),
    style: widget.style,
  );
}
