import 'dart:io';

import 'package:flutter/material.dart';
import '../shared/desktop_window_drag.dart';
import '../shared/platform_utils.dart';
import '../core/launcher_colors.dart';
import '../core/launcher_style.dart';
import '../features/launcher/launcher_screen.dart';
import '../features/auth/auth_controller.dart';
import '../shared/microsoft_login_button.dart';
import '../shared/custom_title_bar.dart';
import '../shared/app_version_corner.dart';
import 'settings_screen.dart';
import '../core/settings/launcher_settings_cache.dart';
import '../core/local_config/launcher_catalog_config.dart';
import '../core/config/app_config.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with TickerProviderStateMixin {
  int _currentPage = 0;
  late PageController _pageController;
  late AnimationController _transitionController;
  final AuthController _auth = AuthController();
  bool _bootDone = false;
  bool _launcherReady = false;
  String _updateAvailableVersion = '';
  String _updateDownloadUrl = '';

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _transitionController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _auth.setOnAuthenticated(() {});
    _auth.setOnSignedOut(() {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    });
    _boot();
  }

  Future<void> _boot() async {
    await LauncherSettingsCache.warmup();
    final cfg = await LauncherCatalogConfig.tryLoad();
    await _auth.initialize();
    final remote = cfg?.launcher.launcherVersion.trim() ?? '';
    final download = cfg?.launcher.launcherDownloadUrl.trim() ?? '';
    final local = AppConfig.version.trim();
    if (_isRemoteNewer(remote, local)) {
      _updateAvailableVersion = remote;
      _updateDownloadUrl = download;
    }
    if (!mounted) return;
    setState(() => _bootDone = true);
  }

  static Future<void> _openExternalUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    if (!PlatformUtils.isDesktop) return;
    if (Platform.isWindows) {
      final parsed = Uri.tryParse(u);
      if (parsed == null || !parsed.isAbsolute || parsed.scheme != 'https' || parsed.userInfo.isNotEmpty) return;
      await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', parsed.toString()]);
    }
  }

  static bool _isRemoteNewer(String remote, String local) {
    int parsePart(String v) {
      final cleaned = v.trim().toLowerCase().replaceAll('v', '');
      return int.tryParse(cleaned) ?? 0;
    }

    final r = remote.split('.').map(parsePart).toList(growable: false);
    final l = local.split('.').map(parsePart).toList(growable: false);
    final maxLen = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < maxLen; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    _transitionController.forward().then((_) {
      _transitionController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isWeb = PlatformUtils.isWeb;
    final bool isDesktop = !isWeb && PlatformUtils.isDesktop;
    final showSplash = !(_bootDone && _launcherReady);
    final topInset = MediaQuery.of(context).padding.top;

    final body = Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                LauncherScreen(onReady: () {
                  if (!mounted) return;
                  if (_launcherReady) return;
                  setState(() => _launcherReady = true);
                }),
                const _ProfilePage(),
                const SettingsScreen(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [LauncherColors.black, Colors.transparent],
                  stops: [0.3, 1],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: _TopBar(
                  currentIndex: _currentPage,
                  onSelect: (i) => _pageController.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic),
                  animationController: _transitionController,
                  showWindowButtons: isDesktop,
                ),
              ),
            ),
          ),
          const AppVersionCorner(),
          if (_updateAvailableVersion.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: topInset + LauncherStyle.chromeBarHeight + 14,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: LauncherColors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LauncherColors.accentGold.withOpacity(0.35), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update_alt, color: LauncherColors.accentGold, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Update available: v$_updateAvailableVersion (you have v${AppConfig.version})',
                          style: const TextStyle(color: LauncherColors.accentGold, fontSize: 13, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_updateDownloadUrl.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _TopBtn(
                          label: 'UPDATE',
                          selected: false,
                          onTap: () => _openExternalUrl(_updateDownloadUrl),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (showSplash)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: LauncherColors.black,
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 220,
                    height: 220,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.apps, size: 180, color: LauncherColors.accentGold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return body;
  }
}

class _TopBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final AnimationController animationController;
  final bool showWindowButtons;
  const _TopBar({
    required this.currentIndex,
    required this.onSelect,
    required this.animationController,
    required this.showWindowButtons,
  });

  @override
  Widget build(BuildContext context) {
    final auth = AuthController();
    return SizedBox(
      height: LauncherStyle.chromeBarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: showWindowButtons ? (_) => startDesktopWindowDrag() : null,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: animationController,
                  builder: (context, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 32,
                            height: 32,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: Icon(Icons.apps, size: 28, color: LauncherColors.accentGold),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'BARIS LAUNCHER',
                          style: TextStyle(
                            color: LauncherColors.accentGold,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            height: 1.0,
                            shadows: [
                              Shadow(color: LauncherColors.accentGold.withOpacity(0.8), blurRadius: 10, offset: const Offset(0, 0)),
                              Shadow(color: LauncherColors.accentGold.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 0)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Center(child: _TopBtn(label: 'PLAY', selected: currentIndex == 0, onTap: () => onSelect(0))),
          Center(child: MicrosoftLoginButton(selected: currentIndex == 1, onPressed: () => auth.isAuthenticated && auth.currentUser != null ? onSelect(1) : auth.signIn())),
          Center(child: _TopIconBtn(selected: currentIndex == 2, icon: Icons.settings, onTap: () => onSelect(2))),
          const SizedBox(width: 8),
          if (showWindowButtons) const Center(child: WindowButtons()),
        ],
      ),
    );
  }
}

class _TopIconBtn extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  const _TopIconBtn({required this.selected, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 36,
            alignment: Alignment.center,
            decoration: LauncherStyle.chromeToggleDecoration(selected: selected),
            child: Icon(icon, size: 18, color: selected ? LauncherColors.black : LauncherColors.white),
          ),
        ),
      ),
    );
  }
}

class _TopBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TopBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: LauncherStyle.chromeToggleDecoration(selected: selected),
            child: Text(label, style: TextStyle(color: selected ? LauncherColors.black : LauncherColors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ),
      ),
    );
  }
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  final AuthController _auth = AuthController();
  Map<String, num>? _balances;
  late final TextEditingController _offlineNameField;

  @override
  void initState() {
    super.initState();
    _offlineNameField = TextEditingController();
    _auth.addListener(_onAuthChanged);
    _fetchProfile();
  }

  @override
  void dispose() {
    _offlineNameField.dispose();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    _fetchProfile();
    setState(() {});
  }

  Future<void> _fetchProfile() async {
    if (!_auth.isAuthenticated) return;
    setState(() {
      _balances = const {
        'coins': 0,
        'aircraftXp': 0,
        'infantryXp': 0,
        'vehicleXp': 0,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: LauncherColors.black,
      body: Stack(children: [
        Container(
          decoration: const BoxDecoration(gradient: LauncherStyle.profileScaffoldGradient),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              LauncherStyle.spacingL,
              MediaQuery.paddingOf(context).top + LauncherStyle.chromeBarHeight + LauncherStyle.spacingL,
              LauncherStyle.spacingL,
              LauncherStyle.spacingL,
            ),
            child: (_auth.isAuthenticated || _auth.isOffline) && _auth.currentUser != null
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(LauncherStyle.spacingL),
                          decoration: BoxDecoration(
                            color: LauncherColors.backgroundPanel,
                            borderRadius: BorderRadius.circular(LauncherStyle.radiusL),
                            border: Border.all(color: LauncherColors.borderDefault),
                            boxShadow: [BoxShadow(color: LauncherColors.black.withOpacity(0.3), blurRadius: LauncherStyle.radiusM, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: LauncherColors.darkGray,
                                  borderRadius: BorderRadius.circular(LauncherStyle.radiusL),
                                  border: Border.all(color: LauncherColors.accentGold, width: 3),
                                  boxShadow: [BoxShadow(color: LauncherColors.accentGold.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(LauncherStyle.radiusL - 3),
                                  child: _auth.isOffline || _auth.mcUuid == null || _auth.mcUuid!.isEmpty
                                      ? Icon(Icons.person, size: 60, color: LauncherColors.gray)
                                      : Image.network(
                                          'https://crafatar.com/avatars/${_auth.mcUuid}?size=128&overlay&default=MHF_Steve',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            final uuid = _auth.mcUuid ?? '';
                                            if (uuid.isEmpty) return Icon(Icons.person, size: 60, color: LauncherColors.gray);
                                            return Image.network(
                                              'https://mc-heads.net/avatar/$uuid/128.png',
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Icon(Icons.person, size: 60, color: LauncherColors.gray),
                                            );
                                          },
                                        ),
                                ),
                              ),
                              const SizedBox(width: LauncherStyle.spacingL),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _auth.mcName ?? 'Unknown Player',
                                      style: const TextStyle(color: LauncherColors.accentGold, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: (_auth.isOffline ? LauncherColors.gray : LauncherColors.infantryXP).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: _auth.isOffline ? LauncherColors.gray : LauncherColors.infantryXP, width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.circle, color: _auth.isOffline ? LauncherColors.gray : LauncherColors.infantryXP, size: 8),
                                          const SizedBox(width: 6),
                                          Text(
                                            _auth.isOffline ? 'OFFLINE' : 'ONLINE',
                                            style: TextStyle(
                                              color: _auth.isOffline ? LauncherColors.gray : LauncherColors.infantryXP,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'UUID: ${_auth.mcUuid}',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 14, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: _onSignOut,
                                borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: LauncherColors.airXP.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                    border: Border.all(color: LauncherColors.airXP, width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.logout, color: LauncherColors.airXP, size: 18),
                                      const SizedBox(width: 8),
                                      Text('SIGN OUT', style: TextStyle(color: LauncherColors.airXP, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: LauncherStyle.spacingL),
                        Text('STATISTICS', style: TextStyle(color: LauncherColors.accentGold, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                        const SizedBox(height: LauncherStyle.spacingM),
                        Stack(
                          children: [
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: screenSize.width > 800 ? 4 : 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 2.5,
                              children: [
                                _StatCard(
                                  icon: Icons.monetization_on,
                                  label: 'Coins',
                                  value: _balances?['coins']?.toInt() ?? 0,
                                  color: LauncherColors.accentGold,
                                  gradient: [LauncherColors.accentGold, LauncherColors.accentGold.withOpacity(0.7)],
                                ),
                                _StatCard(
                                  icon: Icons.flight,
                                  label: 'Aircraft XP',
                                  value: _balances?['aircraftXp']?.toInt() ?? 0,
                                  color: LauncherColors.airXP,
                                  gradient: [LauncherColors.airXP, LauncherColors.airXP.withOpacity(0.7)],
                                ),
                                _StatCard(
                                  icon: Icons.groups,
                                  label: 'Infantry XP',
                                  value: _balances?['infantryXp']?.toInt() ?? 0,
                                  color: LauncherColors.infantryXP,
                                  gradient: [LauncherColors.infantryXP, LauncherColors.infantryXP.withOpacity(0.7)],
                                ),
                                _StatCard(
                                  icon: Icons.directions_car,
                                  label: 'Vehicle XP',
                                  value: _balances?['vehicleXp']?.toInt() ?? 0,
                                  color: LauncherColors.vehicleXP,
                                  gradient: [LauncherColors.vehicleXP, LauncherColors.vehicleXP.withOpacity(0.7)],
                                ),
                              ],
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: const [0.2, 0.6],
                                      colors: [
                                        LauncherColors.black.withOpacity(0.0),
                                        LauncherColors.black,
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'later',
                                      style: TextStyle(color: LauncherColors.whiteMuted, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline, size: 80, color: LauncherColors.gray),
                        const SizedBox(height: 24),
                        Text('Sign in to view your profile', style: TextStyle(color: LauncherColors.gray, fontSize: 18, fontWeight: FontWeight.w600)),
                        if (_auth.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              _auth.errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: LauncherColors.errorText, fontSize: 12, height: 1.3),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: TextField(
                            controller: _offlineNameField,
                            style: const TextStyle(color: LauncherColors.white),
                            decoration: const InputDecoration(
                              labelText: 'Offline username (3–16)',
                              labelStyle: TextStyle(color: LauncherColors.whiteMuted),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: LauncherColors.borderDefault)),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: LauncherColors.accentGold)),
                            ),
                            maxLength: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            _auth.clearError();
                            _auth.playOffline(_offlineNameField.text);
                          },
                          child: const Text('Play offline'),
                        ),
                        const SizedBox(height: 24),
                        MicrosoftLoginButton(
                          onPressed: () {
                            _auth.clearError();
                            _auth.signIn();
                          },
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _onSignOut() async {
    if (_auth.isOffline) {
      _auth.exitOffline();
    } else {
      await _auth.signOut();
    }
    if (mounted) {
      final shell = context.findAncestorStateOfType<_ShellScreenState>();
      shell?._pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final List<Color> gradient;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LauncherColors.backgroundPanel, LauncherColors.backgroundPanel.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(LauncherStyle.radiusL),
        border: Border.all(color: LauncherColors.borderDefault),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: LauncherStyle.radiusM, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(LauncherStyle.radiusM)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), borderRadius: BorderRadius.circular(LauncherStyle.radiusL)),
                child: Text(value.toString(), style: const TextStyle(color: LauncherColors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: LauncherColors.whiteMuted, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
