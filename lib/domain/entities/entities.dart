import 'package:flutter/foundation.dart';

class User {  final String id;
  final String uuid;
  final String? username;
  final String? email;
  final List<String> roles;
  final Map<String, int> currencies;

  const User({
    required this.id,
    required this.uuid,
    this.username,
    this.email,
    this.roles = const [],
    this.currencies = const {},
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.id == id &&
        other.uuid == uuid &&
        other.username == username &&
        other.email == email &&
        listEquals(other.roles, roles) &&
        mapEquals(other.currencies, currencies);
  }

  @override
  int get hashCode => Object.hash(id, uuid, username, email, roles, currencies);

  @override
  String toString() {
    return 'User(id: $id, uuid: $uuid, username: $username, email: $email, roles: $roles, currencies: $currencies)';
  }
}