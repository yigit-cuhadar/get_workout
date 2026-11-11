import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import 'access/presentation/access_cubit.dart';
import 'admin_router.dart';
import 'shell/env_banner.dart';

class AdminApp extends StatefulWidget {
  const AdminApp({super.key, required this.env, required this.projectId});

  final AppEnv env;
  final String projectId;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final _router = buildAdminRouter(sl<AccessCubit>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<AccessCubit>(),
      child: MaterialApp.router(
        title: 'GetWorkout admin (${widget.projectId})',
        theme: ForgeTheme.light(),
        darkTheme: ForgeTheme.dark(),
        routerConfig: _router,
        builder: (context, child) => Column(
          children: [
            EnvBanner(env: widget.env, projectId: widget.projectId),
            Expanded(child: child!),
          ],
        ),
      ),
    );
  }
}
