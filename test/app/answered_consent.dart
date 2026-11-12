import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _AnsweredConsentCubit extends MockCubit<ConsentState>
    implements ConsentCubit {}

/// A consent cubit whose user has answered, for the shell's consent prompt
/// and the Profile tab's privacy section.
BlocProvider<ConsentCubit> answeredConsent() {
  final cubit = _AnsweredConsentCubit();
  when(
    () => cubit.state,
  ).thenReturn(const ConsentState(stored: (consent: false, fromServer: true)));
  return BlocProvider<ConsentCubit>.value(value: cubit);
}
