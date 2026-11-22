import 'unload_guard/unload_guard_stub.dart'
    if (dart.library.js_interop) 'unload_guard/unload_guard_web.dart';

/// Asks the browser to warn before the tab is closed or reloaded while
/// [active]; does nothing off the web.
abstract interface class UnloadGuard {
  set active(bool value);
}

/// The guard of the platform the panel runs on.
UnloadGuard platformUnloadGuard() => createUnloadGuard();
