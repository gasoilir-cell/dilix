import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// نمایشگرِ تمام‌صفحهٔ رسانهٔ گفتگو: تصویر (زوم‌شدنی)، ویدیو و صوت.
/// صوت هم با `video_player` پخش می‌شود (ExoPlayer/AVPlayer صوت را پشتیبانی
/// می‌کنند) تا وابستگیِ اضافه لازم نشود.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.url,
    this.isVideo = false,
    this.isAudio = false,
    this.title,
  });

  final String url;
  final bool isVideo;
  final bool isAudio;
  final String? title;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  String? _error;

  bool get _isPlayable => widget.isVideo || widget.isAudio;

  @override
  void initState() {
    super.initState();
    if (_isPlayable) _initPlayer();
  }

  Future<void> _initPlayer() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
      c.addListener(_onTick);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'پخشِ این فایل ممکن نبود.');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isAudio ? null : Colors.black,
      appBar: AppBar(
        backgroundColor: widget.isAudio ? null : Colors.black,
        foregroundColor: widget.isAudio ? null : Colors.white,
        title: Text(
          widget.title?.trim().isNotEmpty == true
              ? widget.title!
              : widget.isVideo
                  ? 'ویدیو'
                  : widget.isAudio
                      ? 'پیامِ صوتی'
                      : 'تصویر',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (widget.isAudio) return _audio(context);
    if (widget.isVideo) return _video();
    return _image();
  }

  Widget _image() {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Image.network(
        widget.url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: Colors.white70),
              ),
        errorBuilder: (_, __, ___) => const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined, size: 44, color: Colors.white70),
              SizedBox(height: 12),
              Text('تصویر بارگذاری نشد.',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _video() {
    final c = _ctrl;
    if (!_ready || c == null) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: GestureDetector(
            onTap: _togglePlay,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                if (!c.value.isPlaying)
                  const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white70),
              ],
            ),
          ),
        ),
        VideoProgressIndicator(c, allowScrubbing: true),
      ],
    );
  }

  Widget _audio(BuildContext context) {
    final c = _ctrl;
    if (!_ready || c == null) return const CircularProgressIndicator();
    final pos = c.value.position;
    final total = c.value.duration;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.graphic_eq, size: 72),
          const SizedBox(height: 24),
          Slider(
            value: pos.inMilliseconds
                .clamp(0, total.inMilliseconds == 0 ? 1 : total.inMilliseconds)
                .toDouble(),
            max: (total.inMilliseconds == 0 ? 1 : total.inMilliseconds)
                .toDouble(),
            onChanged: (v) =>
                c.seekTo(Duration(milliseconds: v.round())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos)),
              Text(_fmt(total)),
            ],
          ),
          const SizedBox(height: 16),
          IconButton.filled(
            iconSize: 40,
            onPressed: _togglePlay,
            icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
