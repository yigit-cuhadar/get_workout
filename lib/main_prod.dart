import 'package:forge_core/forge_core.dart';

import 'app/bootstrap.dart';
import 'firebase_options_prod.dart';

void main() => bootstrap(AppEnv.prod, DefaultFirebaseOptions.currentPlatform);
