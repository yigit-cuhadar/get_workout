import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in the browser app; false when it could not be opened.
///
/// Not in the in-app browser: on iOS its result is the page's first load,
/// only known once it finishes or the user closes it, so a page shown and
/// closed early (or one that loaded with an error) reads as not opened.
Future<bool> openLink(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
).catchError((_) => false);
