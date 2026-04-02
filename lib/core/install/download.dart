import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'verifiers.dart';

class DownloadFileTask {
  final Uri url;
  final File outFile;
  final FileVerifier? verifier;
  final Duration timeout;
  final int maxRedirects;

  const DownloadFileTask({
    required this.url,
    required this.outFile,
    this.verifier,
    this.timeout = const Duration(minutes: 10),
    this.maxRedirects = 5,
  });

  Future<void> run(void Function(double, String) progress) async {
    final tmp = File('${outFile.path}.part');
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
    await tmp.parent.create(recursive: true);
    final client = http.Client();
    try {
      final streamed = await _sendWithRedirects(client, url, maxRedirects: maxRedirects).timeout(timeout);
      if (streamed.statusCode != 200) throw Exception('download failed: ${streamed.statusCode}');
      final total = streamed.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in streamed.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total != null && total > 0) {
            progress((received / total).clamp(0.0, 1.0), '${received}_of_$total');
          } else {
            progress(0.0, '${received}_bytes');
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close();
    }

    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }
    await tmp.rename(outFile.path);

    final v = verifier;
    if (v != null) await v.verify(outFile);
  }
}

Future<http.StreamedResponse> _sendWithRedirects(http.Client client, Uri uri, {required int maxRedirects}) async {
  Uri current = uri;
  for (int i = 0; i < maxRedirects; i++) {
    final req = http.Request('GET', current);
    final resp = await client.send(req);
    if (resp.isRedirect) {
      final loc = resp.headers['location'];
      if (loc == null || loc.trim().isEmpty) return resp;
      final next = Uri.tryParse(loc);
      if (next == null) return resp;
      current = next.isAbsolute ? next : current.resolveUri(next);
      continue;
    }
    return resp;
  }
  return client.send(http.Request('GET', current));
}

