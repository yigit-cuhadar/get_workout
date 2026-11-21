import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Holds a menu section's place until its page is built.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const EmptyView(message: 'Coming soon'),
  );
}
