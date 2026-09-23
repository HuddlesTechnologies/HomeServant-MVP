import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';

/// Plays a landlord-uploaded property walkthrough video inline, with a
/// tap-to-play/pause overlay. [path] follows the same convention as every
/// other upload in the app (see `imageProviderForPath`) — a local file
/// path on mobile/desktop, a blob URL on web.
class PropertyVideoPlayer extends StatefulWidget {
  const PropertyVideoPlayer({super.key, required this.path});

  final String path;

  @override
  State<PropertyVideoPlayer> createState() => _PropertyVideoPlayerState();
}

class _PropertyVideoPlayerState extends State<PropertyVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = kIsWeb || widget.path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));
    _controller.addListener(_onTick);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() => _failed = true);
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _placeholder(const Icon(Icons.videocam_off_rounded, color: AppColors.hintGrey, size: 32));
    }
    if (!_ready) {
      return _placeholder(const CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy));
    }

    final aspectRatio = _controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        onTap: _togglePlay,
        child: AspectRatio(
          aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              VideoPlayer(_controller),
              AnimatedOpacity(
                opacity: _controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(Widget child) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
