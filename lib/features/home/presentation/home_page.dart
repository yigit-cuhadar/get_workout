import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';

/// Placeholder landing screen; replaced by the app's first real feature.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(onPressed: auth.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: EmptyView(message: auth.user?.email ?? ''),
    );
  }
}
