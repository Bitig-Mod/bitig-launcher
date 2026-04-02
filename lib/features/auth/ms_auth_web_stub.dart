import 'dart:async';

Future<String?> launchPopupAndWaitWebImpl(
  Uri authUrl, {
  required String expectedState,
  required String expectedOrigin,
}) async {
  throw UnsupportedError('Web authentication is not available on desktop platforms');
}
