import 'package:intl/intl.dart';

import '../domain/announcement.dart';

/// "Everyone", "Free", "Premium".
String audienceLabel(AnnouncementAudience audience) => switch (audience) {
  AnnouncementAudience.everyone => 'Everyone',
  AnnouncementAudience.free => 'Free',
  AnnouncementAudience.premium => 'Premium',
};

/// Who an audience is in a sentence: "every user", "free users", "Premium
/// users".
String audiencePhrase(AnnouncementAudience audience) => switch (audience) {
  AnnouncementAudience.everyone => 'every user',
  AnnouncementAudience.free => 'free users',
  AnnouncementAudience.premium => 'Premium users',
};

/// "on Wed, Nov 25 at 09:00 (GMT+3)", in the admin's own time.
String scheduleLabel(DateTime at) {
  final local = at.toLocal();
  return 'on ${DateFormat('EEE, MMM d').format(local)} at '
      '${DateFormat('HH:mm').format(local)} (${local.timeZoneName})';
}
