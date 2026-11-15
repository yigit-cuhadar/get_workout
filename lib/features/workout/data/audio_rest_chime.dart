import 'package:audioplayers/audioplayers.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/rest_chime.dart';

/// [RestChime] as the bundled `assets/sounds/rest_chime.wav`, mixed with
/// whatever else plays (music keeps going) and silent when the phone is.
class AudioRestChime implements RestChime {
  AudioRestChime();

  static const asset = 'sounds/rest_chime.wav';

  late final Future<AudioPlayer> _player = () async {
    final player = AudioPlayer();
    await player.setAudioContext(
      AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
        respectSilence: true,
      ).build(),
    );
    await player.setReleaseMode(ReleaseMode.stop);
    return player;
  }();

  @override
  Future<Result<void>> play() => guard(() async {
    final player = await _player;
    await player.stop();
    await player.play(AssetSource(asset));
  });
}
