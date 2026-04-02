import 'package:flutter/foundation.dart';
import '../../core/auth/minecraft_offline_uuid.dart';
import 'ms_auth.dart';
import '../../domain/entities/entities.dart';

enum AuthState { unauthenticated, authorizing, authenticated, offline, error }

final RegExp _offlineMcName = RegExp(r'^[a-zA-Z0-9_]{3,16}$');

class AuthController extends ChangeNotifier {
  AuthState _state = AuthState.unauthenticated;
  String? _errorMessage;
  User? _currentUser;
  VoidCallback? _onAuthenticated;
  VoidCallback? _onSignedOut;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  User? get currentUser => _currentUser;
  String? get mcUuid => _currentUser?.uuid;
  String? get mcName => _currentUser?.id; // Using ID as fallback for name
  String? get mcAccessToken => MsAuth.mcAccessToken;

  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isOffline => _state == AuthState.offline;
  bool get isAuthorizing => _state == AuthState.authorizing;
  bool get canPlay => isAuthenticated || isOffline;

  Stream<bool> get isLoggedInStream async* {
    yield isAuthenticated;
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      yield isAuthenticated;
    }
  }

  static final AuthController _instance = AuthController._internal();
  factory AuthController() => _instance;
  AuthController._internal();

  void setOnAuthenticated(VoidCallback callback) {
    _onAuthenticated = callback;
  }

  void setOnSignedOut(VoidCallback callback) {
    _onSignedOut = callback;
  }

  Future<void> initialize() async {
    _setState(AuthState.authorizing);

    try {
      final success = await MsAuth.trySilentSignIn();
      if (!success) {
        _currentUser = null;
        _setState(AuthState.unauthenticated);
        return;
      }

      _currentUser = await MsAuth.getCurrentUser();
      if (_currentUser == null) {
        _setState(AuthState.unauthenticated);
        return;
      }

      _setState(AuthState.authenticated);
    } catch (e) {
      _setError('Initialization failed: $e');
    }
  }

  Future<void> signIn() async {
    _setState(AuthState.authorizing);

    try {
      await MsAuth.interactiveSignIn();
      _currentUser = await MsAuth.getCurrentUser();
      if (_currentUser == null) {
        throw Exception('No Minecraft profile returned (currentUser is null).');
      }
      _setState(AuthState.authenticated);
      _onAuthenticated?.call();
    } catch (e) {
      _setError('Sign in failed: $e');
    }
  }

  Future<void> signOut() async {
    _setState(AuthState.authorizing);

    try {
      await MsAuth.signOut();
      _currentUser = null;
      _setState(AuthState.unauthenticated);
      _onSignedOut?.call();
    } catch (e) {
      _setError('Sign out failed: $e');
    }
  }

  Future<void> refreshToken() async {
    if (_state != AuthState.authenticated) return;

    _setState(AuthState.authorizing);

    try {
      final success = await MsAuth.trySilentSignIn();
      if (success) {
        _currentUser = await MsAuth.getCurrentUser();
        _setState(AuthState.authenticated);
      } else {
        _setState(AuthState.unauthenticated);
      }
    } catch (e) {
      _setError('Token refresh failed: $e');
    }
  }

  Future<void> playOffline(String username) async {
    final name = username.trim();
    if (!_offlineMcName.hasMatch(name)) {
      _setError('Offline name must be 3–16 characters: letters, digits, underscore.');
      return;
    }
    _setState(AuthState.authorizing);
    try {
      final uuid = minecraftOfflineUuidForName(name);
      _currentUser = User(id: name, uuid: uuid, username: name);
      _setState(AuthState.offline);
    } catch (e) {
      _setError('Offline mode failed: $e');
    }
  }

  void exitOffline() {
    if (_state != AuthState.offline) return;
    _currentUser = null;
    _setState(AuthState.unauthenticated);
  }

  void _setState(AuthState state) {
    _state = state;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _state = AuthState.error;
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    if (_state == AuthState.error) {
      _setState(AuthState.unauthenticated);
    }
  }
}
