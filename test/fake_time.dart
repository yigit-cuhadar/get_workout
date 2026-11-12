import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Runs [act] against the cubit [build] makes on fake time, so its timers
/// fire exactly when [act] elapses them however loaded the machine is;
/// returns the states it emitted.
List<S> onFakeTime<C extends BlocBase<S>, S>(
  C Function() build,
  void Function(FakeAsync async, C cubit) act,
) {
  final states = <S>[];
  fakeAsync((async) {
    final cubit = build();
    final subscription = cubit.stream.listen(states.add);
    act(async, cubit);
    async.flushMicrotasks();
    unawaited(subscription.cancel());
    unawaited(cubit.close());
    async.flushMicrotasks();
  });
  return states;
}
