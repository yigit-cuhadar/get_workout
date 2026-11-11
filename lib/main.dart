import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';

import 'app/bootstrap.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

/// Release builds talk to the prod Firebase project; debug and profile builds
/// talk to dev. The native Firebase config files follow the same split.
void main() => kReleaseMode
    ? bootstrap(AppEnv.prod, prod.DefaultFirebaseOptions.currentPlatform)
    : bootstrap(AppEnv.dev, dev.DefaultFirebaseOptions.currentPlatform);
