import 'package:audioplayers/audioplayers.dart';

/// Plays a short alert sound for admin console chat events (a new queue
/// message, a transfer handed to you, a resolution) while the app is open
/// — foreground-only, no OS-level push. A single shared `AudioPlayer`
/// instance and a short throttle keep a burst of near-simultaneous socket
/// events (e.g. several admins' notifications landing at once) from
/// stacking overlapping sounds.
class ChatSoundService {
  ChatSoundService._();

  static final ChatSoundService instance = ChatSoundService._();

  final AudioPlayer _player = AudioPlayer();
  DateTime? _lastPlayedAt;

  static const _minInterval = Duration(seconds: 2);

  Future<void> play() async {
    final now = DateTime.now();
    final lastPlayedAt = _lastPlayedAt;
    if (lastPlayedAt != null && now.difference(lastPlayedAt) < _minInterval) return;
    _lastPlayedAt = now;
    try {
      await _player.play(AssetSource('sounds/notification.wav'));
    } catch (_) {
      // Best-effort — a missing audio device/asset shouldn't ever crash a
      // notification banner over a sound failing to play.
    }
  }
}
