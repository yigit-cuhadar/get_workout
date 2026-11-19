import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/vocabulary.dart';
import 'library_cubit.dart';
import 'widgets/library_list_view.dart';

/// The exercise list: search, filters, sort, favourites and the + for a
/// custom exercise, on the browsing state the Exercises tab shares.
///
/// Opened for a [muscle] picked on the model (the location's `muscle`), it
/// browses that muscle for this visit: the muscle becomes the filter (a
/// removable chip), the list switches between its main and secondary
/// exercises while it stays the only muscle filtered, and leaving (or a
/// link to another muscle) takes it away again. Otherwise the search
/// starts empty and takes focus once the page is in.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.muscle});

  final Muscle? muscle;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _library = sl<LibraryCubit>();

  @override
  void initState() {
    super.initState();
    switch (widget.muscle) {
      case final muscle?:
        _library.openMuscle(muscle);
      // From the search pill the list opens on an empty search.
      case null:
        _library.setQuery('');
    }
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page stays when only its `muscle` changes.
    if (widget.muscle == oldWidget.muscle) return;
    if (oldWidget.muscle case final muscle?) _library.leaveMuscle(muscle);
    if (widget.muscle case final muscle?) _library.openMuscle(muscle);
  }

  @override
  void dispose() {
    if (widget.muscle case final muscle?) _library.leaveMuscle(muscle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: _library,
      child: Scaffold(
        appBar: ForgeAppBar(
          title: l10n.libraryTitle,
          actions: [
            ForgeAppBarAction.icon(
              icon: ForgeIcons.add,
              label: l10n.customNew,
              onPressed: () => context.push(Routes.customExerciseNew),
            ),
          ],
        ),
        body: LibraryListView(
          focusSearch: widget.muscle == null,
          searchHero: true,
          searchWhileLoading: true,
          sectionsFor: widget.muscle,
          onCreate: (name) => context.push(Routes.customExerciseNamed(name)),
        ),
      ),
    );
  }
}
