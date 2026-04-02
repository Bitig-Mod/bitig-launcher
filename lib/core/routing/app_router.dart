import 'package:go_router/go_router.dart';

import '../../screens/shell_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'shell',
        builder: (context, state) => const ShellScreen(),
      ),
    ],
  );
}
