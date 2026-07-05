import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthNotifier extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;

  AuthNotifier() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  bool get isLoggedIn => _auth.currentUser != null;
  User? get currentUser => _auth.currentUser;
  String get userEmail => _auth.currentUser?.email ?? '';

  String get userName {
    final user = _auth.currentUser;
    if (user?.displayName?.isNotEmpty ?? false) return user!.displayName!;
    final email = user?.email ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }

  String get userInitials {
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    if (userName.isNotEmpty) return userName[0].toUpperCase();
    return 'U';
  }

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signUp({required String email, required String password}) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>(
  (ref) => AuthNotifier(),
);
