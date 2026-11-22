import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../unload_guard.dart';

UnloadGuard createUnloadGuard() => _BrowserGuard();

/// One `beforeunload` listener, added the first time it is needed, that
/// asks the browser's own "Leave site?" question while active.
class _BrowserGuard implements UnloadGuard {
  bool _active = false;
  bool _listening = false;

  @override
  set active(bool value) {
    _active = value;
    if (!value || _listening) return;
    _listening = true;
    globalContext.callMethod(
      'addEventListener'.toJS,
      'beforeunload'.toJS,
      ((JSObject event) {
        if (!_active) return;
        event.callMethod('preventDefault'.toJS);
        // Older browsers ask only when it is set.
        event['returnValue'] = ''.toJS;
      }).toJS,
    );
  }
}
