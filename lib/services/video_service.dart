import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoService extends ChangeNotifier {
  static final VideoService instance = VideoService._internal();
  VideoService._internal();

  Player? _player;
  VideoController? _controller;
  String? _currentUrl;
  bool _isLoading = false;
  bool _hasError = false;
  Future<void> _queue = Future<void>.value();

  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get isInitialized => _controller != null;
  String? get currentVideoUrl => _currentUrl;
  VideoController? get videoController => _controller;

  Future<void> initializeVideo(String url) async {
    _queue = _queue.then((_) => _initializeSerial(url)).catchError((_) {});
    return _queue;
  }

  void _ensureInit() {
    _player ??= Player();
    _controller ??= VideoController(_player!);
  }

  Future<void> _initializeSerial(String url) async {
    if (url.isEmpty) {
      _setError('Empty URL provided');
      return;
    }

    if (kDebugMode) {
      debugPrint('VideoService: initializeVideo url=$url');
    }

    if (_currentUrl == url && _player != null && _controller != null) {
      _setLoading(false);
      _setError(null);
      return;
    }

    _setLoading(true);

    try {
      _ensureInit();

      if (kDebugMode) {
        debugPrint('VideoService: opening media');
      }
      final player = _player!;
      await player.open(Playlist(<Media>[Media(url)]), play: false).timeout(const Duration(seconds: 12));
      await player.setVolume(0.0);
      await player.setPlaylistMode(PlaylistMode.loop);

      _currentUrl = url;

      if (kDebugMode) {
        debugPrint('VideoService: play()');
      }
      await player.play().timeout(const Duration(seconds: 6));

      _setLoading(false);
      _setError(null);

      if (kDebugMode) {
        debugPrint('VideoService: playing=${player.state.playing} position=${player.state.position}');
      }
    } catch (e) {
      _setError('Failed to initialize video: $e');
      _setLoading(false);
    }
  }

  void ensurePlaying() {
    final player = _player;
    if (player == null) return;

    final state = player.state;
    if (!state.playing) {
      player.play();
    }
  }

  void pauseVideo() {
    _player?.pause();
  }

  void resumeVideo() {
    _player?.play();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _hasError = error != null;
    if (error != null && kDebugMode) {
      debugPrint('VideoService Error: $error');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    _controller = null;
    super.dispose();
  }
}
