import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';

import '../domain/subscription_usecases.dart';

/// The free trial a free user's Premium card names; null while it is not
/// known, when the store cannot be reached and when there is none.
class PremiumTrialCubit extends Cubit<OfferPeriod?> {
  PremiumTrialCubit(this._getTrial) : super(null);

  final GetPremiumTrial _getTrial;

  Future<void> load() async {
    final trial = (await _getTrial()).valueOrNull;
    if (trial != null && !isClosed) emit(trial);
  }
}
