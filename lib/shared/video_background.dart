import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/video_service.dart';
import '../core/launcher_colors.dart';
import 'dart:developer' as developer;
import 'dart:async';

class VideoBackground extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;

  const VideoBackground({super.key, required this.videoUrl, this.fit = BoxFit.cover});

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> with WidgetsBindingObserver {
  String? _lastVideoUrl;
  static const bool _debugLogs = false;
  Timer? _ensureTimer;

  void _log(String message) {
    if (!_debugLogs) return;
    developer.log(message, name: 'VideoBackground');
  }

  @override
  void initState() {
    super.initState();
    _log('VIDEO_BACKGROUND: init url=${widget.videoUrl}');
    VideoService.instance.addListener(_onVideoServiceChanged);
    WidgetsBinding.instance.addObserver(this);
    _ensureTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      VideoService.instance.ensurePlaying();
    });
    _initializeVideo();
  }

  @override
  void didUpdateWidget(VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _log('VIDEO_BACKGROUND: url changed ${oldWidget.videoUrl} -> ${widget.videoUrl}');
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _log('VIDEO_BACKGROUND: dispose');
    _ensureTimer?.cancel();
    _ensureTimer = null;
    VideoService.instance.removeListener(_onVideoServiceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _log('VIDEO_BACKGROUND: lifecycle=$state');

    switch (state) {
      case AppLifecycleState.resumed:
        VideoService.instance.resumeVideo();
        break;
      case AppLifecycleState.paused:
        VideoService.instance.pauseVideo();
        break;
      default:
        break;
    }
  }

  void _onVideoServiceChanged() {
    if (mounted) {
      setState(() {});
      VideoService.instance.ensurePlaying();
    } else {
      _log('VIDEO_BACKGROUND: not mounted, skip setState');
    }
  }

  Future<void> _initializeVideo() async {
    if (_lastVideoUrl == widget.videoUrl) {
      return;
    }
    if (widget.videoUrl.isEmpty) {
      return;
    }
    _lastVideoUrl = widget.videoUrl;

    if (VideoService.instance.currentVideoUrl != widget.videoUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _log('VIDEO_BACKGROUND: initializing url=${widget.videoUrl}');
          await VideoService.instance.initializeVideo(widget.videoUrl).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              _log('VIDEO_BACKGROUND: init timed out');
              throw TimeoutException('Video loading timed out', const Duration(seconds: 10));
            },
          );
          _log('VIDEO_BACKGROUND: init completed');
        } catch (e) {
          _log('VIDEO_BACKGROUND: init error: $e');
        }
      });
    } else {
      VideoService.instance.resumeVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoService = VideoService.instance;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final hasSize = w.isFinite && h.isFinite && w > 0 && h > 0;
        if (!hasSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {});
          });
        }

        if (videoService.hasError) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [LauncherColors.darkGray, LauncherColors.black]),
            ),
          );
        }

        if (!videoService.isInitialized || videoService.videoController == null) {
          if (videoService.isLoading) {
            return Container(color: Colors.black);
          } else {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [LauncherColors.darkGray, LauncherColors.black]),
              ),
            );
          }
        }

        return SizedBox.expand(
          child: Video(
            controller: videoService.videoController!,
            fit: widget.fit,
          ),
        );
      },
    );
  }
}
