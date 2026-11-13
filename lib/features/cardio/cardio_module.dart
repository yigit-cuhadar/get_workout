import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../settings/presentation/first_weekday.dart';
import 'data/firestore_cardio_repository.dart';
import 'domain/cardio_repository.dart';
import 'domain/cardio_session.dart';
import 'domain/cardio_usecases.dart';
import 'presentation/cardio_form_cubit.dart';
import 'presentation/cardio_list_cubit.dart';

/// Registers the cardio feature. Needs `AuthModule` for the current user.
class CardioModule implements FeatureModule {
  const CardioModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<CardioRepository>(
        () => FirestoreCardioRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchCardioSessions(sl()))
      ..registerFactory(() => WatchCardioBetween(sl()))
      ..registerFactory(() => WatchRejectedCardioWrites(sl()))
      ..registerFactory(() => SaveCardioSession(sl()))
      ..registerFactory(() => DeleteCardioSession(sl()))
      // One list for the whole app: the list and the session pages share it.
      ..registerLazySingleton(
        () => CardioListCubit(
          firstWeekday: currentFirstWeekday(sl()),
          watchAuthUser: sl(),
          watchSessions: sl(),
          watchRejectedWrites: sl(),
        ),
      )
      ..registerFactoryParam<CardioFormCubit, CardioSession?, DistanceUnit>(
        (session, unit) => CardioFormCubit(
          saveSession: sl(),
          deleteSession: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          unit: unit,
          initial: session,
        ),
      );
  }
}
