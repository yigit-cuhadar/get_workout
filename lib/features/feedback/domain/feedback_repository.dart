import 'package:forge_core/forge_core.dart';

import 'feedback.dart';

abstract interface class FeedbackRepository {
  /// Stores [draft], trimmed and checked, as an open message of user [uid],
  /// with the app version, device and locale it was sent from.
  ///
  /// The result only covers starting the write: Firestore keeps it on the
  /// device and sends it whenever the device is online.
  Future<Result<void>> send(String uid, FeedbackDraft draft);
}
