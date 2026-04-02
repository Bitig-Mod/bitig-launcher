import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' as wm;
import '../core/launcher_colors.dart';

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(icon: Icons.minimize, onPressed: () => wm.windowManager.minimize()),
        _WindowButton(
          icon: Icons.crop_square,
          onPressed: () async {
            bool isMaximized = await wm.windowManager.isMaximized();
            if (isMaximized) {
              wm.windowManager.unmaximize();
            } else {
              wm.windowManager.maximize();
            }
          },
        ),
        _WindowButton(icon: Icons.close, onPressed: () => wm.windowManager.close()),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _WindowButton({required this.icon, required this.onPressed});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(widget.icon, color: isHovered ? LauncherColors.accentGold : LauncherColors.lightGray, size: 16),
          ),
        ),
      ),
    );
  }
}
