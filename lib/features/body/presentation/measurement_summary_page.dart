import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';
import 'measurement_comparison.dart';
import 'measurement_summary_cubit.dart';

/// A measurement day just saved, next to the one before; see
/// [MeasurementComparison].
class MeasurementSummaryPage extends StatelessWidget {
  const MeasurementSummaryPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<MeasurementSummaryCubit>(param1: id),
    child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).bodySummaryTitle),
      ),
      body: const MeasurementComparison(compare: false),
    ),
  );
}
