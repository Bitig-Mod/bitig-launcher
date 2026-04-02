// Flutter Web popup launcher for Microsoft OAuth (PKCE) using postMessage.
import 'dart:async';
import 'dart:convert';
// ignore: deprecated_member_use
import 'dart:html' as html;

Future<String?> launchPopupAndWaitWebImpl(
  Uri authUrl, {
  required String expectedState,
  required String expectedOrigin, // e.g. origin of https://api.example.com
}) async {
  final c = Completer<String?>();

  Map<String, dynamic>? coerce(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      try {
        return json.decode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  late final StreamSubscription<html.MessageEvent> sub;
  late final Timer poll;

  sub = html.window.onMessage.listen((event) {
    if (c.isCompleted) return; // guard
    // Accept messages from the backend callback origin
    if (event.origin != expectedOrigin) return;
    final msg = coerce(event.data);
    if (msg == null) return;
    if ((msg['type'] ?? '') != 'ms-auth') return;
    if (msg['code'] != null && msg['code'] is! String) return;

    final state = (msg['state'] ?? '') as String;
    if (state != expectedState) {
      if (!c.isCompleted) c.completeError(StateError('STATE_MISMATCH'));
      return;
    }

    final err = (msg['error'] ?? '') as String;
    if (err.isNotEmpty) {
      if (!c.isCompleted) c.completeError(StateError(err));
    } else {
      if (!c.isCompleted) c.complete((msg['code'] ?? '') as String);
    }
  });

  final popup = html.window.open(
    authUrl.toString(),
    'ms_login_${DateTime.now().millisecondsSinceEpoch}',
    'width=520,height=720,noopener',
  );

  poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (popup.closed == true && !c.isCompleted) c.complete(null);
  });

  // Extra safety: if parent unloads, close popup
  html.window.onBeforeUnload.first.then((_) {
    try {
      popup.close();
    } catch (_) {}
  });

  return c.future.timeout(const Duration(minutes: 5), onTimeout: () {
    try {
      popup.close();
    } catch (_) {}
    throw TimeoutException('OAUTH_TIMEOUT');
  }).whenComplete(() async {
    await sub.cancel();
    poll.cancel();
    try {
      popup.close();
    } catch (_) {}
  });
}
