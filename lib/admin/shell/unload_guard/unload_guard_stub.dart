import '../unload_guard.dart';

UnloadGuard createUnloadGuard() => _NoGuard();

class _NoGuard implements UnloadGuard {
  @override
  set active(bool value) {}
}
