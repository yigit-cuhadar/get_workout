import 'package:forge_core/forge_core.dart';

import 'app/bootstrap.dart';
import 'firebase_options_dev.dart';

void main() => bootstrap(AppEnv.dev, DefaultFirebaseOptions.currentPlatform);
