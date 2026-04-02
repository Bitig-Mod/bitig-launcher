import 'dart:async';
import 'ms_auth_web_impl.dart' if (dart.library.io) 'ms_auth_web_stub.dart';

/// Opens a popup to the given authUrl and waits for a postMessage with the auth code.
///
/// Listens for a message of the shape { type: 'ms-auth', code: '...' } from the
/// callback window, validates origin against the expected origin, and resolves.
Future<String?> launchPopupAndWaitWeb(Uri authUrl, {required String expectedState, required String expectedOrigin}) async {
  return await launchPopupAndWaitWebImpl(authUrl, expectedState: expectedState, expectedOrigin: expectedOrigin);
}
