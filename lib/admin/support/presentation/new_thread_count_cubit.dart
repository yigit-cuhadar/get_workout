import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shell/retrying_listener.dart';
import '../domain/support_inbox_usecases.dart';

/// How many threads are New, live, for the menu; null until known. A
/// failed stream keeps the last count and retries.
class NewThreadCountCubit extends Cubit<int?> {
  NewThreadCountCubit({
    required WatchNewThreadCount watchNewThreadCount,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(null) {
    _listener = RetryingListener(
      watch: watchNewThreadCount.call,
      onData: emit,
      onFailure: (_) {},
      firstRetryDelay: firstRetryDelay,
    );
  }

  late final RetryingListener<int> _listener;

  @override
  Future<void> close() async {
    await _listener.cancel();
    return super.close();
  }
}
