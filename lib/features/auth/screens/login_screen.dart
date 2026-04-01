import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _message;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(email: email, password: password);
        if (mounted) {
          setState(() {
            _isLoading = false;
            _message = 'Check your email to confirm sign up';
          });
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _isLoading = false; _message = e.message; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _message = 'Something went wrong'; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _message = null; });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google);
    } on AuthException catch (e) {
      if (mounted) setState(() { _isLoading = false; _message = e.message; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _message = 'Google sign-in failed. Enable Google in Supabase Dashboard.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/branding/billy_logo.png',
                    height: 96,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_wallet_rounded, size: 72, color: BillyTheme.emerald600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Billy',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.02, color: BillyTheme.gray800),
              ),
              const SizedBox(height: 8),
              const Text(
                'AI Financial OS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: BillyTheme.gray500),
              ),
              const SizedBox(height: 40),
              _buildField(_emailController, 'Email', hint: 'you@example.com', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _buildField(_passwordController, 'Password', obscure: true),
              const SizedBox(height: 20),
              if (_message != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _message!.contains('failed') || _message!.contains('wrong')
                        ? BillyTheme.red400.withValues(alpha: 0.15)
                        : BillyTheme.emerald50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _message!.contains('failed') || _message!.contains('wrong')
                          ? BillyTheme.red500
                          : BillyTheme.gray800,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              GestureDetector(
                onTap: _isLoading ? null : _signInWithEmail,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _isLoading ? BillyTheme.gray300 : BillyTheme.emerald600,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _isLoading ? null : [
                      BoxShadow(color: BillyTheme.emerald600.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : Text(
                          _isSignUp ? 'Sign Up' : 'Sign In',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _isLoading ? null : () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp ? 'Already have an account? Sign In' : 'Create account',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray500),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(child: Divider(color: BillyTheme.gray200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray400)),
                  ),
                  Expanded(child: Divider(color: BillyTheme.gray200)),
                ],
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: _isLoading ? null : _signInWithGoogle,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: BillyTheme.gray200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.g_mobiledata_rounded, size: 28, color: BillyTheme.gray800),
                      const SizedBox(width: 10),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, {String? hint, TextInputType? keyboard, bool obscure = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint ?? label,
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.emerald600, width: 2)),
      ),
    );
  }
}
