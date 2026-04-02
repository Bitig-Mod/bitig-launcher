import 'dart:io';

import 'package:crypto/crypto.dart';

abstract class FileVerifier {
  Future<void> verify(File file);
}

class Sha256Verifier implements FileVerifier {
  final String expectedHex;
  Sha256Verifier(this.expectedHex);

  @override
  Future<void> verify(File file) async {
    final exp = expectedHex.trim().toLowerCase();
    if (exp.isEmpty) throw Exception('sha256 missing');
    final digest = await _sha256OfFile(file);
    if (digest != exp) throw Exception('sha256 mismatch');
  }
}

class Sha1Verifier implements FileVerifier {
  final String expectedHex;
  Sha1Verifier(this.expectedHex);

  @override
  Future<void> verify(File file) async {
    final exp = expectedHex.trim().toLowerCase();
    if (exp.isEmpty) throw Exception('sha1 missing');
    final digest = await _sha1OfFile(file);
    if (digest != exp) throw Exception('sha1 mismatch');
  }
}

class SizeVerifier implements FileVerifier {
  final int expectedBytes;
  SizeVerifier(this.expectedBytes);

  @override
  Future<void> verify(File file) async {
    final len = await file.length();
    if (len != expectedBytes) throw Exception('size mismatch');
  }
}

class CompositeVerifier implements FileVerifier {
  final List<FileVerifier> verifiers;
  CompositeVerifier(this.verifiers);

  @override
  Future<void> verify(File file) async {
    for (final v in verifiers) {
      await v.verify(file);
    }
  }
}

Future<String> _sha256OfFile(File file) async {
  final sink = _DigestCollector();
  final conv = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    conv.add(chunk);
  }
  conv.close();
  return sink.value!.toString();
}

Future<String> _sha1OfFile(File file) async {
  final sink = _DigestCollector();
  final conv = sha1.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    conv.add(chunk);
  }
  conv.close();
  return sink.value!.toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

