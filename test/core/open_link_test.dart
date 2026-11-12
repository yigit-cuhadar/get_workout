import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/open_link.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Answers every launch with [answer], recording the options asked for.
class FakeLauncher extends UrlLauncherPlatform {
  FakeLauncher(this.answer);

  final Future<bool> Function() answer;
  final launched = <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    launched.add((url, options.mode));
    return answer();
  }
}

void main() {
  final uri = Uri.parse('https://example.com/privacy');
  late UrlLauncherPlatform original;

  setUp(() => original = UrlLauncherPlatform.instance);
  tearDown(() => UrlLauncherPlatform.instance = original);

  FakeLauncher install(Future<bool> Function() answer) =>
      UrlLauncherPlatform.instance = FakeLauncher(answer);

  test('opens in the browser app, not the in-app browser', () async {
    final launcher = install(() async => true);
    expect(await openLink(uri), isTrue);
    expect(launcher.launched, [
      (uri.toString(), PreferredLaunchMode.externalApplication),
    ]);
  });

  test('a link nothing can open is not opened', () async {
    install(() async => false);
    expect(await openLink(uri), isFalse);
  });

  test('a launch that throws is not opened', () async {
    install(() => Future.error(PlatformException(code: 'ACTIVITY_NOT_FOUND')));
    expect(await openLink(uri), isFalse);
  });
}
