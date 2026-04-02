import 'dart:convert';

import 'package:crypto/crypto.dart';

String minecraftOfflineUuidForName(String name) {
  final bytes = List<int>.from(md5.convert(utf8.encode('OfflinePlayer:$name')).bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String h(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}
