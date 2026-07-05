import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formtract/core/providers/auth_provider.dart';
import 'package:formtract/core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _isSignUp = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authNotifierProvider);
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (_isSignUp) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signIn(email: email, password: password);
      }
      TextInput.finishAutofillContext();
      // GoRouter redirect handles navigation automatically via authStateChanges
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e.code));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address above first.');
      return;
    }
    try {
      await ref.read(authNotifierProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e.code));
    }
  }

  String _friendlyError(String code) => switch (code) {
    'user-not-found' => 'No account found with that email.',
    'wrong-password' => 'Incorrect password.',
    'invalid-credential' => 'Incorrect email or password.',
    'email-already-in-use' => 'An account already exists with that email.',
    'invalid-email' => 'Enter a valid email address.',
    'weak-password' => 'Password must be at least 6 characters.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'network-request-failed' => 'Network error. Check your connection.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDark,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Logo(),
                    const SizedBox(height: 40),
                    _FormCard(
                      emailCtrl: _emailCtrl,
                      passwordCtrl: _passwordCtrl,
                      obscure: _obscure,
                      isSignUp: _isSignUp,
                      loading: _loading,
                      error: _error,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onToggleMode: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _error = null;
                      }),
                      onSubmit: _submit,
                      onForgotPassword: _forgotPassword,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Logo ─────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: kBlueAccent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icon/icon.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Text(
                  'F',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'formtract',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Form management for real estate pros',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─── Form card ────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final bool isSignUp;
  final bool loading;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  const _FormCard({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.isSignUp,
    required this.loading,
    required this.error,
    required this.onToggleObscure,
    required this.onToggleMode,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kNavyMed,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isSignUp ? 'Create your account' : 'Sign in to your account',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _DarkField(
            controller: emailCtrl,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 14),
          _DarkField(
            controller: passwordCtrl,
            label: 'Password',
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            autofillHints: isSignUp
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            onFieldSubmitted: (_) => onSubmit(),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              onPressed: onToggleObscure,
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: kBlueAccent,
              disabledBackgroundColor: kBlueAccent.withValues(alpha: 0.5),
            ),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isSignUp ? 'Create account' : 'Sign in'),
          ),
          if (!isSignUp) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.55),
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            onPressed: onToggleMode,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.55),
            ),
            child: Text(
              isSignUp
                  ? 'Already have an account? Sign in'
                  : "Don't have an account? Sign up",
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable dark-themed text field ──────────────────────────────────────────

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _DarkField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      autocorrect: false,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        fillColor: Colors.white.withValues(alpha: 0.07),
        enabledBorder: _border(Colors.white.withValues(alpha: 0.15)),
        focusedBorder: _border(kBlueAccent, width: 2),
        errorBorder: _border(Colors.redAccent),
        focusedErrorBorder: _border(Colors.redAccent, width: 2),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }
}
