import 'desktop_window_stub.dart' if (dart.library.io) 'desktop_window_io.dart' as impl;

Future<void> setupDesktopWindow() => impl.setupDesktopWindow();
