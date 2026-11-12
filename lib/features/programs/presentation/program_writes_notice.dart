import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import 'program_list_cubit.dart';

/// Tells the user when the server refused a program write that already
/// looked done, e.g. a missed-day choice made on the Programs or the Today
/// tab. It sits in the shell around every tab, so it is the one place the
/// notice shows, whichever tab is open.
class ProgramWritesNotice extends StatelessWidget {
  const ProgramWritesNotice({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocListener<ProgramListCubit, ProgramListState>(
        listenWhen: (previous, current) =>
            current.writeRejected && !previous.writeRejected,
        listener: (context, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).programWritesRejected),
            ),
          );
          context.read<ProgramListCubit>().rejectionShown();
        },
        child: child,
      );
}
