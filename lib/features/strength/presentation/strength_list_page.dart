import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'strength_list_cubit.dart';
import 'widgets/strength_exercises.dart';

/// The exercises the user has done, most recently trained first, each
/// opening its records and e1RM chart.
class StrengthListPage extends StatelessWidget {
  const StrengthListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<StrengthListCubit>(),
    child: Scaffold(
      appBar: ForgeAppBar(title: AppLocalizations.of(context).strengthTitle),
      body: StrengthSearch(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
        onPick: (context, id) => context.go(Routes.strengthExercise(id)),
      ),
    ),
  );
}

/// [StrengthExercises] scrolling inside [padding], searched in the app's
/// language; [onPick] gets a row's exercise.
class StrengthSearch extends StatefulWidget {
  const StrengthSearch({
    super.key,
    required this.padding,
    required this.onPick,
    this.selected,
  });

  final EdgeInsets padding;
  final void Function(BuildContext context, String exerciseId) onPick;
  final String? selected;

  @override
  State<StrengthSearch> createState() => _StrengthSearchState();
}

class _StrengthSearchState extends State<StrengthSearch> {
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<StrengthListCubit>().setLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: widget.padding,
    children: [
      StrengthExercises(
        search: _search,
        selected: widget.selected,
        onPick: (id) => widget.onPick(context, id),
      ),
    ],
  );
}
