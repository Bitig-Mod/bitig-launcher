import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/launcher_colors.dart';
import '../../core/launcher_style.dart';
import '../../core/logging/logger.dart';
import '../../shared/platform_utils.dart';
import '../../shared/video_background.dart';
import '../../shared/fire_particles.dart';
import '../../services/video_service.dart';
import '../../core/local_config/launcher_catalog_config.dart';
import '../auth/auth_controller.dart';
import 'launcher_service.dart' as game_installer;

class ModpackInfo {
  final String name;
  final String iconPng;
  final String videoUrl;
  final String mcVersion;
  final String forgeVersion;
  final String zipUrl;
  final String modpackVersion;
  final bool live;

  ModpackInfo({
    required this.name,
    this.iconPng = '',
    required this.videoUrl,
    required this.mcVersion,
    required this.forgeVersion,
    required this.zipUrl,
    this.modpackVersion = '',
    this.live = false,
  });
}

class LauncherScreen extends StatefulWidget {
  final VoidCallback? onReady;
  const LauncherScreen({super.key, this.onReady});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isCheckingFiles = true;
  bool _isGameReady = false;
  bool _didNotifyReady = false;
  final bool _isPlaying = false;
  bool _isInstalling = false;
  bool _isLaunching = false;
  double _fileCheckProgress = 0.0;
  String _statusText = 'Loading launcher config...';
  String? _errorText;
  String? _selectedModpack;
  List<ModpackInfo> _modpacks = [];
  String _featuredVideoUrl = '';
  String _currentVideoUrl = '';

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;
  late final AnimationController _shineController;
  late final Animation<double> _shineAnimation;
  final AuthController _auth = AuthController();
  late final VoidCallback _authListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authListener = () {
      if (mounted) setState(() {});
    };
    _auth.addListener(_authListener);
    _initButtonEffects();
    _loadLauncherConfigFromDrive();
  }

  void _initButtonEffects() {
    _glowController = AnimationController(duration: const Duration(seconds: 3), vsync: this);
    _glowAnimation = Tween<double>(begin: 0.15, end: 1.0).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _glowController.repeat(reverse: true);

    _shineController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _shineAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(CurvedAnimation(parent: _shineController, curve: Curves.linear));
    _shineController.repeat();
  }

  Future<void> _loadLauncherConfigFromDrive() async {
    final cfg = await LauncherCatalogConfig.tryLoad();
    if (!mounted) return;
    setState(() {
      _featuredVideoUrl = cfg?.launcher.featuredVideoUrl ?? '';
      _modpacks = cfg?.modpacks
              .where((m) => m.name.isNotEmpty)
              .map(
                (m) => ModpackInfo(
                  name: m.name,
                  iconPng: m.iconPng,
                  videoUrl: m.videoUrl,
                  mcVersion: m.mcVersion,
                  forgeVersion: m.forgeVersion,
                  zipUrl: m.zipUrl,
                  modpackVersion: m.modpackVersion,
                  live: m.live,
                ),
              )
              .toList() ??
          <ModpackInfo>[];
      _selectedModpack = _modpacks.isNotEmpty ? _modpacks.first.name : null;
      _currentVideoUrl = _resolveCurrentVideoUrl();
      _isCheckingFiles = true;
      _statusText = 'Checking game files...';
    });
    Logger.debug('Video startup featured=$_featuredVideoUrl current=$_currentVideoUrl modpacks=${_modpacks.length}', tag: 'LauncherScreen');
    VideoService.instance.initializeVideo(PlatformUtils.isDesktop ? _currentVideoUrl : _featuredVideoUrl);

    try {
      await game_installer.GameInstaller.loadLauncherConfig();
      final selected = _modpacks.isNotEmpty ? _modpacks.first : null;
      if (selected != null) {
        await game_installer.GameInstaller.setSelectedModpack(
          name: selected.name,
          mcVersion: selected.mcVersion,
          forgeVersion: selected.forgeVersion,
          zipUrl: selected.zipUrl,
          modpackVersion: selected.modpackVersion,
        );
      }
    } catch (e) {
      Logger.error('Failed to apply drive config: $e', tag: 'LauncherScreen');
    }

    await _checkGameFiles();
  }

  @override
  void dispose() {
    _auth.removeListener(_authListener);
    WidgetsBinding.instance.removeObserver(this);
    _glowController.dispose();
    _shineController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      VideoService.instance.resumeVideo();
    } else if (state == AppLifecycleState.paused) {
      VideoService.instance.pauseVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = PlatformUtils.isWeb;
    final bool isDesktop = !isWeb && PlatformUtils.isDesktop;

    return Scaffold(
      backgroundColor: LauncherColors.black,
      body: Stack(
        children: [
          Positioned.fill(
              child: VideoBackground(
            key: ValueKey(PlatformUtils.isDesktop ? _currentVideoUrl : _featuredVideoUrl),
            videoUrl: PlatformUtils.isDesktop ? _currentVideoUrl : _featuredVideoUrl,
          )),
          Positioned.fill(child: const FireParticles()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.fromRGBO(0, 0, 0, 0.0), Color.fromRGBO(0, 0, 0, 0.0), Color.fromRGBO(0, 0, 0, 1.0)],
                  stops: [0.0, 0.4, 0.7],
                ),
              ),
              alignment: Alignment.bottomCenter,
              child: SafeArea(child: _buildBottomBar(isWeb, isDesktop)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideActionButton() {
    final isBusy = _isPlaying || _isCheckingFiles || _isInstalling || _isLaunching;
    final buttonText = _isGameReady ? (_isLaunching ? 'LAUNCHING...' : 'PLAY') : (_isInstalling ? 'INSTALLING...' : 'INSTALL');
    final buttonIcon = _isGameReady ? Icons.play_arrow : Icons.download;

    return AnimatedBuilder(
      animation: Listenable.merge([_glowController, _shineController, _auth]),
      builder: (context, child) {
        return Stack(
          children: [
            Container(
              width: 300,
              height: 72,
              decoration: BoxDecoration(
                color: isBusy ? LauncherColors.lightGray.withOpacity(0.5) : LauncherColors.accentGold,
                borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(255, 220, 70, _glowAnimation.value),
                    blurRadius: 14 + (42 * _glowAnimation.value),
                    spreadRadius: 2 + (14 * _glowAnimation.value),
                  ),
                  BoxShadow(
                    color: Color.fromRGBO(255, 200, 40, _glowAnimation.value * 0.55),
                    blurRadius: 6 + (18 * _glowAnimation.value),
                    spreadRadius: 1 + (4 * _glowAnimation.value),
                  ),
                ],
                border: isBusy ? Border.all(color: LauncherColors.accentGold.withOpacity(0.6), width: 1.0) : null,
              ),
            ),
            if (isBusy)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ShimmerPainter(progress: _shineAnimation.value),
                  ),
                ),
              ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isBusy ? null : _playGame,
                  borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isBusy) Icon(buttonIcon, size: 24, color: LauncherColors.black),
                      if (!isBusy) const SizedBox(width: 8),
                      Text(
                        buttonText,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: LauncherColors.black),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(bool isWeb, bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isDesktop) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildModpackSelector(),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildWideActionButton(),
                      const SizedBox(height: 32),
                      Text(
                        _statusText,
                        style: const TextStyle(
                          color: LauncherColors.accentGold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Text(
                            _errorText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: LauncherColors.errorText.withOpacity(0.95), fontSize: 12, height: 1.25),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        width: 300,
                        decoration: BoxDecoration(
                          boxShadow: [
                            if (_fileCheckProgress >= 1.0) ...[
                              BoxShadow(color: LauncherColors.accentGold.withOpacity(0.95), blurRadius: 24, spreadRadius: 8),
                              BoxShadow(color: LauncherColors.accentGold.withOpacity(0.55), blurRadius: 10, spreadRadius: 2),
                            ] else if (_fileCheckProgress > 0) ...[
                              BoxShadow(color: LauncherColors.accentGold.withOpacity(0.62), blurRadius: 14, spreadRadius: 3),
                            ],
                          ],
                          borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                          child: LinearProgressIndicator(
                            value: _fileCheckProgress,
                            minHeight: 4,
                            backgroundColor: LauncherColors.darkGray,
                            valueColor: const AlwaysStoppedAnimation<Color>(LauncherColors.accentGold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 300,
                ),
              ],
            ),
          ] else ...[
            Center(
              child: _DownloadBtn(icon: 'icons/os/windows.png', label: 'DOWNLOAD FOR WINDOWS'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkGameFiles() async {
    if (!mounted) return;
    setState(() {
      _isCheckingFiles = true;
      _statusText = 'Checking game files...';
      _errorText = null;
      _fileCheckProgress = 0.0;
    });

    final integrity = await game_installer.GameInstaller.calculateIntegrity();

    if (!mounted) return;
    setState(() {
      _isCheckingFiles = false;
      _isGameReady = integrity.missing == 0;
      _fileCheckProgress = integrity.progress;
      _statusText = integrity.missing == 0 ? 'Ready to play' : 'Missing: ${integrity.summary()}';
    });
    if (!_didNotifyReady) {
      _didNotifyReady = true;
      widget.onReady?.call();
    }
  }

  Future<bool> _ensurePlayIdentity() async {
    if (_auth.canPlay) return true;
    if (!mounted) return false;
    final ctrl = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: LauncherColors.backgroundPanel,
          title: const Text('Play offline', style: TextStyle(color: LauncherColors.accentGold)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: LauncherColors.white),
            decoration: const InputDecoration(
              labelText: 'Username (3–16 characters)',
              labelStyle: TextStyle(color: LauncherColors.whiteMuted),
            ),
            maxLength: 16,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (go != true) return false;
      await _auth.playOffline(ctrl.text);
      if (!_auth.canPlay) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_auth.errorMessage ?? 'Could not start offline profile')),
          );
        }
        return false;
      }
      return true;
    } finally {
      ctrl.dispose();
    }
  }

  void _playGame() async {
    HapticFeedback.lightImpact();
    if (!await _ensurePlayIdentity()) return;

    if (!_isGameReady) {
      if (!mounted) return;
      setState(() {
        _isInstalling = true;
        _statusText = 'Preparing installation...';
        _errorText = null;
        _fileCheckProgress = 0.0;
      });

      try {
        await game_installer.GameInstaller.installAll(reportProgress: (p, msg) {
          if (!mounted) return;
          setState(() {
            _fileCheckProgress = p;
            _statusText = msg;
          });
        });

        if (!mounted) return;
        setState(() {
          _isInstalling = false;
          _isGameReady = true;
          _fileCheckProgress = 1.0;
          _statusText = 'Ready to play';
        });
      } catch (e) {
        if (!mounted) return;
        Logger.error('Install failed: $e', tag: 'LauncherScreen');
        setState(() {
          _isInstalling = false;
          _statusText = 'Install failed';
          _errorText = e.toString();
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isLaunching = true;
        _statusText = 'Launching...';
        _errorText = null;
      });

      final access = _auth.isOffline ? 'offline' : (_auth.mcAccessToken ?? 'offline');
      final ok = await game_installer.GameInstaller.play(
        username: _auth.mcName ?? 'Player',
        uuid: _auth.mcUuid,
        accessToken: access,
        reportStatus: (s) {
          if (!mounted) return;
          setState(() {
            _statusText = s;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isLaunching = false;
        _statusText = ok ? 'Game launched successfully' : 'Game failed to launch';
        _errorText = ok ? null : 'Launch failed. Check logs for details.';
      });
    }
  }

  String _resolveCurrentVideoUrl() {
    if (_modpacks.isEmpty) return _featuredVideoUrl;
    final modpack = _modpacks.firstWhere((m) => m.name == _selectedModpack, orElse: () => _modpacks.first);
    return modpack.videoUrl.isNotEmpty ? modpack.videoUrl : _featuredVideoUrl;
  }

  Widget _modpackLiveDot(bool live) {
    final offlineColor = LauncherColors.darkGray;
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? LauncherColors.serverLive : offlineColor,
        boxShadow: [
          if (live)
            BoxShadow(color: LauncherColors.serverLive.withOpacity(0.85), blurRadius: 6, spreadRadius: 1)
          else
            BoxShadow(color: LauncherColors.black.withOpacity(0.65), blurRadius: 4, spreadRadius: 0),
        ],
      ),
    );
  }

  Widget _modpackRow(ModpackInfo modpack, {bool dense = false}) {
    final icon = modpack.iconPng.trim();
    final bool hasIcon = icon.isNotEmpty;
    final bool isUrl = hasIcon && (icon.startsWith('http://') || icon.startsWith('https://'));
    final double s = dense ? 18 : 22;
    final statusStyle = TextStyle(color: LauncherColors.accentGold.withOpacity(dense ? 0.85 : 0.95), fontSize: dense ? 10 : 11, fontWeight: FontWeight.w600);
    return Row(
      children: [
        _modpackLiveDot(modpack.live),
        if (hasIcon)
          ClipRRect(
            borderRadius: BorderRadius.circular(LauncherStyle.radiusS),
            child: SizedBox(
              width: s,
              height: s,
              child: isUrl
                  ? Image.network(icon, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  : Image.asset(icon, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ),
        if (hasIcon) SizedBox(width: dense ? 6 : 8),
        Expanded(child: Text(modpack.name, style: const TextStyle(color: LauncherColors.accentGold, fontSize: 12), overflow: TextOverflow.ellipsis)),
        Text(modpack.live ? 'Live Server' : 'Offline', style: statusStyle),
      ],
    );
  }

  Widget _buildModpackSelector() {
    final disabled = _isCheckingFiles || _isInstalling || _isLaunching;
    return Container(
      decoration: BoxDecoration(
        color: LauncherColors.darkGray.withOpacity(disabled ? 0.12 : 0.2),
        borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
        border: Border.all(color: LauncherColors.borderDefault, width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: IgnorePointer(
              ignoring: disabled,
              child: DropdownButton<String>(
              value: _selectedModpack,
              icon: const Icon(Icons.arrow_drop_down, color: LauncherColors.accentGold),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              isExpanded: true,
              underline: Container(),
              style: const TextStyle(color: LauncherColors.accentGold, fontSize: 12),
              dropdownColor: LauncherColors.darkGray,
              selectedItemBuilder: (context) {
                return _modpacks.map((m) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: _modpackRow(m, dense: true))).toList();
              },
              items: _modpacks.map((modpack) {
                return DropdownMenuItem<String>(
                  value: modpack.name,
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _modpackRow(modpack)),
                );
              }).toList(),
              onChanged: _onModpackChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onModpackChanged(String? newValue) async {
    if (newValue != null && newValue != _selectedModpack) {
      setState(() {
        _selectedModpack = newValue;
        _currentVideoUrl = _resolveCurrentVideoUrl();
        _isGameReady = false;
        _isCheckingFiles = true;
        _statusText = 'Checking game files...';
        _errorText = null;
        _fileCheckProgress = 0.0;
      });
      VideoService.instance.initializeVideo(_currentVideoUrl);
      try {
        final match = _modpacks.firstWhere((m) => m.name == _selectedModpack, orElse: () => _modpacks.first);
        await game_installer.GameInstaller.setSelectedModpack(
          name: match.name,
          mcVersion: match.mcVersion,
          forgeVersion: match.forgeVersion,
          zipUrl: match.zipUrl,
          modpackVersion: match.modpackVersion,
        );
        await _checkGameFiles();
      } catch (e) {
        Logger.error('Failed to update modpack selection: $e', tag: 'LauncherScreen');
      }
    }
  }
}

class _DownloadBtn extends StatelessWidget {
  final String icon;
  final String label;
  const _DownloadBtn({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      height: 104,
      decoration: BoxDecoration(
        color: LauncherColors.accentGold,
        borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
        boxShadow: [BoxShadow(color: LauncherColors.accentGold.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(icon, width: 42, height: 42, errorBuilder: (context, error, stackTrace) => Icon(Icons.computer, size: 42, color: LauncherColors.black)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: LauncherColors.black),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  _ShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1.0 + progress, 0),
        end: Alignment(0.0 + progress, 0),
        colors: [
          Colors.transparent,
          LauncherColors.accentGold.withOpacity(0.35),
          Colors.transparent,
        ],
        stops: const [0.1, 0.5, 0.9],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(LauncherStyle.radiusM)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) => oldDelegate.progress != progress;
}
