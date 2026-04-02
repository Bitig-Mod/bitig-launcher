import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/core/auth/minecraft_offline_uuid.dart';

void main() {
  test('matches Java nameUUIDFromBytes(OfflinePlayer:name)', () {
    expect(minecraftOfflineUuidForName('Notch'), 'b50ad385-829d-3141-a216-7e7d7539ba7f');
  });
}
