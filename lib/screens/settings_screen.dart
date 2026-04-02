import 'package:flutter/material.dart';

import '../core/java/java_detector.dart';
import '../core/settings/launcher_settings.dart';
import '../core/settings/launcher_settings_cache.dart';
import '../core/launcher_colors.dart';
import '../core/launcher_style.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LauncherSettings _settings = LauncherSettings.defaults;
  List<JavaInstallation> _detected = const [];
  bool _loading = true;
  bool _javaMissing = false;

  late final TextEditingController _jvmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = LauncherSettingsCache.settings;
    _detected = LauncherSettingsCache.detectedJavas;
    _javaMissing = LauncherSettingsCache.javaMissing;
    _jvmController.text = _settings.jvmFlagsRaw;
    _loading = false;
  }

  @override
  void dispose() {
    _jvmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _settings.copyWith(jvmFlagsRaw: _jvmController.text);
    await next.save();
    if (!mounted) return;
    setState(() {
      _settings = next;
    });
    LauncherSettingsCache.updateSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const minMb = 512;
    const maxMb = 32768;
    const stepMb = 512;
    final ramMb = _settings.maxRamMb.clamp(minMb, maxMb);

    return Scaffold(
      backgroundColor: LauncherColors.black,
      body: Container(
        decoration: const BoxDecoration(gradient: LauncherStyle.profileScaffoldGradient),
        child: SafeArea(
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final topPad = LauncherStyle.chromeBarHeight + LauncherStyle.spacingL;
              return Padding(
                padding: EdgeInsets.fromLTRB(LauncherStyle.spacingL, topPad, LauncherStyle.spacingL, LauncherStyle.spacingL),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: LauncherColors.accentGold))
                    : SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight - topPad - LauncherStyle.spacingL),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 900),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('SETTINGS', style: LauncherStyle.titleTextStyle),
                                  const SizedBox(height: LauncherStyle.spacingL),
                                  Container(
                                    padding: const EdgeInsets.all(LauncherStyle.spacingL),
                                    decoration: BoxDecoration(
                                      color: LauncherColors.backgroundPanel,
                                      borderRadius: BorderRadius.circular(LauncherStyle.radiusL),
                                      border: Border.all(color: LauncherColors.borderDefault),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Java', style: TextStyle(color: cs.onSurface.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          value: _settings.javaExecutablePath,
                                          items: [
                                            const DropdownMenuItem<String>(
                                              value: null,
                                              child: Text('Auto (first detected)', overflow: TextOverflow.ellipsis),
                                            ),
                                            ..._detected.map(
                                              (j) => DropdownMenuItem<String>(
                                                value: j.executablePath,
                                                child: Text(j.toString(), overflow: TextOverflow.ellipsis),
                                              ),
                                            ),
                                          ],
                                          onChanged: (v) {
                                            setState(() {
                                              _settings = _settings.copyWith(javaExecutablePath: v);
                                              _javaMissing = false;
                                            });
                                          },
                                          dropdownColor: LauncherColors.darkGray,
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: LauncherColors.darkGray.withOpacity(0.2),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                              borderSide: const BorderSide(color: LauncherColors.borderDefault),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                              borderSide: const BorderSide(color: LauncherColors.accentGold),
                                            ),
                                          ),
                                        ),
                                        if (_javaMissing) ...[
                                          const SizedBox(height: 8),
                                          const Text('Selected Java is missing. Falling back to Auto.', style: TextStyle(color: LauncherColors.accentGold, fontSize: 12)),
                                        ],
                                        const SizedBox(height: LauncherStyle.spacingL),
                                        Text(
                                          'RAM (${ramMb >= 1024 ? '${(ramMb / 1024).toStringAsFixed((ramMb % 1024) == 0 ? 0 : 1)} GB' : '$ramMb MB'})',
                                          style: TextStyle(color: cs.onSurface.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w700),
                                        ),
                                        Slider(
                                          value: ramMb.toDouble(),
                                          min: minMb.toDouble(),
                                          max: maxMb.toDouble(),
                                          divisions: ((maxMb - minMb) ~/ stepMb),
                                          label: ramMb >= 1024 ? '${(ramMb / 1024).toStringAsFixed((ramMb % 1024) == 0 ? 0 : 1)} GB' : '$ramMb MB',
                                          activeColor: LauncherColors.accentGold,
                                          inactiveColor: LauncherColors.borderDefault,
                                          onChanged: (v) {
                                            final mb = ((v / stepMb).round() * stepMb).clamp(minMb, maxMb);
                                            setState(() {
                                              _settings = _settings.copyWith(maxRamMb: mb);
                                            });
                                          },
                                          onChangeEnd: (v) => _save(),
                                        ),
                                        const SizedBox(height: LauncherStyle.spacingL),
                                        Text('JVM flags', style: TextStyle(color: cs.onSurface.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _jvmController,
                                          maxLines: 6,
                                          style: const TextStyle(color: LauncherColors.white, fontSize: 13),
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: LauncherColors.darkGray.withOpacity(0.2),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(LauncherStyle.radiusM)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                              borderSide: const BorderSide(color: LauncherColors.borderDefault),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(LauncherStyle.radiusM),
                                              borderSide: const BorderSide(color: LauncherColors.accentGold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: LauncherStyle.spacingL),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: SizedBox(
                                            height: 40,
                                            child: ElevatedButton(
                                              onPressed: _save,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: LauncherColors.accentGold,
                                                foregroundColor: LauncherColors.black,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LauncherStyle.radiusM)),
                                              ),
                                              child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

