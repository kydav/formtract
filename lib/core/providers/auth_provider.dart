import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthNotifier extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _userEmail = '';
  String _userName = '';

  bool get isLoggedIn => _isLoggedIn;
  String get userEmail => _userEmail;
  String get userName => _userName;
  String get userInitials {
    final parts = _userName.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    if (_userName.isNotEmpty) return _userName[0].toUpperCase();
    if (_userEmail.isNotEmpty) return _userEmail[0].toUpperCase();
    return 'U';
  }

  void login({required String email, String name = ''}) {
    _isLoggedIn = true;
    _userEmail = email;
    _userName = name.isNotEmpty ? name : email.split('@').first;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _userEmail = '';
    _userName = '';
    notifyListeners();
  }
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>(
  (ref) => AuthNotifier(),
);
