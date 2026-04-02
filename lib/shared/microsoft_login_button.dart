import 'package:flutter/material.dart';
import '../core/launcher_colors.dart';
import '../core/launcher_style.dart';
import '../features/auth/auth_controller.dart';

class MicrosoftLoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool selected;

  const MicrosoftLoginButton({super.key, required this.onPressed, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController();
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final isAuthed = auth.isAuthenticated && auth.currentUser != null;
        if (isAuthed) {
          final name = auth.mcName ?? '';
          final uuid = auth.mcUuid ?? '';
          final primaryUrl = uuid.isEmpty ? '' : 'https://crafatar.com/avatars/$uuid?size=32&overlay&default=MHF_Steve';
          final fallbackUrl = uuid.isEmpty ? '' : 'https://mc-heads.net/avatar/$uuid/32.png';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                height: 38,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: LauncherStyle.chromeToggleDecoration(selected: selected),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(color: LauncherColors.black, borderRadius: BorderRadius.circular(LauncherStyle.radiusS)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(LauncherStyle.radiusS),
                          child: primaryUrl.isEmpty
                              ? const Icon(Icons.person, size: 16, color: LauncherColors.whiteMuted)
                              : Image.network(
                                  primaryUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    if (fallbackUrl.isEmpty) {
                                      return const Icon(Icons.person, size: 16, color: LauncherColors.whiteMuted);
                                    }
                                    return Image.network(
                                      fallbackUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 16, color: LauncherColors.whiteMuted),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(name, style: TextStyle(color: selected ? LauncherColors.black : LauncherColors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final isLoading = auth.isAuthorizing;
        return SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(side: const BorderSide(color: LauncherColors.black, width: 1)),
            ),
            child: Column(
              children: [
                Container(height: 8, width: 200, color: LauncherColors.msSignInGreenLight),
                Expanded(
                  child: Container(
                    width: 200,
                    color: LauncherColors.msSignInGreenMid,
                    child: Center(
                      child: isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: LauncherColors.white))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('SIGN IN WITH ', style: TextStyle(color: LauncherColors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(width: 8, height: 8, color: LauncherColors.msLogoRed),
                                        Container(width: 8, height: 8, color: LauncherColors.msLogoGreen),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Container(width: 8, height: 8, color: LauncherColors.msLogoBlue),
                                        Container(width: 8, height: 8, color: LauncherColors.msLogoYellow),
                                      ],
                                    ),
                                  ],
                                ),
                                const Text(' Microsoft', style: TextStyle(color: LauncherColors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                    ),
                  ),
                ),
                Container(height: 8, width: 200, color: LauncherColors.msSignInGreenDark),
              ],
            ),
          ),
        );
      },
    );
  }
}
