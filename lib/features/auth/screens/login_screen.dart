import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  String? _message;
  bool _messageIsError = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
      _messageIsError = false;
    });
  }

  void _showMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageIsError = error;
      _isLoading = false;
    });
  }

  // ─── Email + Password Sign In ──────────────────────────────────

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _message = null; });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } on AuthException catch (e) {
      _showMsg(e.message, error: true);
    } catch (_) {
      _showMsg('Something went wrong. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Email + Password Sign Up ──────────────────────────────────

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _message = null; });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
        data: {
          'full_name': _fullNameCtrl.text.trim(),
          if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        },
      );
      if (!mounted) return;

      // ─── Email already registered? ─────────────────────────────────
      // Supabase's anti-enumeration guard: when the email is already taken
      // it returns a synthetic `user` with an empty `identities` array
      // (and no session). If we do not catch this here, the caller thinks
      // the account was created and (worse) may end up signed back into
      // the *existing* account on a subsequent refresh — which is how a
      // "brand-new user" ends up seeing somebody else's lend/borrow data.
      //
      // Ref: https://supabase.com/docs/guides/auth/auth-identity-linking
      final u = response.user;
      final identitiesEmpty = (u?.identities?.isEmpty ?? false);
      if (u != null && identitiesEmpty && response.session == null) {
        // Defensive: force-clear any residual client session so the caller
        // cannot remain authenticated as a previously-active account.
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        _showMsg(
          'This email is already registered. Sign in instead, or tap '
          '"Forgot password" to reset it.',
          error: true,
        );
        return;
      }

      if (response.session != null) {
        // Signed in — [BillyApp] switches to [LayoutShell] via [authStateProvider].
        setState(() {
          _isLoading = false;
          _message = null;
          _messageIsError = false;
        });
      } else if (u != null) {
        _showMsg('Account created! Check your email to verify, then sign in.');
      } else {
        _showMsg('Account could not be created.', error: true);
      }
    } on AuthException catch (e) {
      _showMsg(e.message, error: true);
    } catch (_) {
      _showMsg('Something went wrong. Please try again.', error: true);
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  // ─── Forgot Password ──────────────────────────────────────────

  Future<void> _resetPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _message = null; });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailCtrl.text.trim(),
      );
      _showMsg('Password reset email sent. Check your inbox.');
    } on AuthException catch (e) {
      _showMsg(e.message, error: true);
    } catch (_) {
      _showMsg('Something went wrong. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── OAuth Providers ───────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _message = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.origin : 'io.supabase.billy://login-callback/',
      );
    } on AuthException catch (e) {
      _showMsg(_googleAuthHint(e.message), error: true);
    } catch (_) {
      _showMsg(_googleAuthHint(null), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Supabase returns e.g. "Unsupported provider: missing Google client secret" when the provider is off or secret is empty.
  String _googleAuthHint(String? apiMessage) {
    final base = apiMessage?.trim();
    final head = (base != null && base.isNotEmpty) ? base : 'Google sign-in failed.';
    return '$head\n\nEnable Google under Supabase → Authentication → Providers and add the '
        'Google OAuth Client ID and Client Secret from Google Cloud Console (not your Supabase CLI token). '
        'See docs/AUTH_GOOGLE_SETUP.md.';
  }

  Future<void> _signInWithApple() async {
    setState(() { _isLoading = true; _message = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? Uri.base.origin : 'io.supabase.billy://login-callback/',
      );
    } on AuthException catch (e) {
      _showMsg(e.message, error: true);
    } catch (_) {
      _showMsg('Apple sign-in failed. Make sure Apple is enabled in your Supabase dashboard.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _showApple {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 36),
                  _buildOAuthButtons(),
                  const SizedBox(height: 24),
                  _buildDivider(),
                  const SizedBox(height: 24),
                  _buildForm(),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    _buildMessage(),
                  ],
                  const SizedBox(height: 20),
                  _buildSubmitButton(),
                  const SizedBox(height: 12),
                  _buildModeToggle(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/branding/billy_logo.png',
            height: 80,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: BillyTheme.emerald600,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Billy',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: BillyTheme.gray800),
        ),
        const SizedBox(height: 4),
        Text(
          _mode == _AuthMode.signUp
              ? 'Create your account'
              : _mode == _AuthMode.forgotPassword
                  ? 'Reset your password'
                  : 'Welcome back',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BillyTheme.gray500),
        ),
      ],
    );
  }

  Widget _buildOAuthButtons() {
    if (_mode == _AuthMode.forgotPassword) return const SizedBox.shrink();

    return Column(
      children: [
        _OAuthButton(
          onTap: _isLoading ? null : _signInWithGoogle,
          icon: Icons.g_mobiledata_rounded,
          label: 'Continue with Google',
          iconSize: 28,
        ),
        if (_showApple) ...[
          const SizedBox(height: 10),
          _OAuthButton(
            onTap: _isLoading ? null : _signInWithApple,
            icon: Icons.apple_rounded,
            label: 'Continue with Apple',
            iconSize: 24,
          ),
        ],
      ],
    );
  }

  Widget _buildDivider() {
    if (_mode == _AuthMode.forgotPassword) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(child: Divider(color: BillyTheme.gray200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or continue with email',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BillyTheme.gray400),
          ),
        ),
        Expanded(child: Divider(color: BillyTheme.gray200)),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          if (_mode == _AuthMode.signUp) ...[
            _InputField(
              controller: _fullNameCtrl,
              label: 'Full Name',
              hint: 'John Doe',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your name';
                if (v.trim().length < 2) return 'Name too short';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _InputField(
              controller: _phoneCtrl,
              label: 'Phone (optional)',
              hint: '+91 98765 43210',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
          ],
          _InputField(
            controller: _emailCtrl,
            label: 'Email',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter your email';
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) return 'Enter a valid email';
              return null;
            },
          ),
          if (_mode != _AuthMode.forgotPassword) ...[
            const SizedBox(height: 12),
            _InputField(
              controller: _passwordCtrl,
              label: 'Password',
              hint: _mode == _AuthMode.signUp ? 'Min 8 characters' : 'Your password',
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: BillyTheme.gray400,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a password';
                if (_mode == _AuthMode.signUp && v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
            ),
          ],
          if (_mode == _AuthMode.signUp) ...[
            const SizedBox(height: 12),
            _InputField(
              controller: _confirmPasswordCtrl,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              icon: Icons.lock_outline_rounded,
              obscure: _obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: BillyTheme.gray400,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirm your password';
                if (v != _passwordCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
          ],
          if (_mode == _AuthMode.signIn) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _setMode(_AuthMode.forgotPassword),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BillyTheme.emerald600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _messageIsError
            ? BillyTheme.red400.withValues(alpha: 0.12)
            : BillyTheme.emerald50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _messageIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 20,
            color: _messageIsError ? BillyTheme.red500 : BillyTheme.emerald600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _messageIsError ? BillyTheme.red500 : BillyTheme.gray800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final label = switch (_mode) {
      _AuthMode.signIn => 'Sign In',
      _AuthMode.signUp => 'Create Account',
      _AuthMode.forgotPassword => 'Send Reset Link',
    };

    return GestureDetector(
      onTap: _isLoading
          ? null
          : switch (_mode) {
              _AuthMode.signIn => _signIn,
              _AuthMode.signUp => _signUp,
              _AuthMode.forgotPassword => _resetPassword,
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _isLoading ? BillyTheme.gray300 : BillyTheme.emerald600,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isLoading
              ? null
              : [BoxShadow(color: BillyTheme.emerald600.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        alignment: Alignment.center,
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }

  Widget _buildModeToggle() {
    if (_mode == _AuthMode.forgotPassword) {
      return TextButton(
        onPressed: () => _setMode(_AuthMode.signIn),
        child: const Text(
          'Back to Sign In',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray500),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _mode == _AuthMode.signIn ? "Don't have an account? " : 'Already have an account? ',
          style: const TextStyle(fontSize: 14, color: BillyTheme.gray500),
        ),
        GestureDetector(
          onTap: () => _setMode(_mode == _AuthMode.signIn ? _AuthMode.signUp : _AuthMode.signIn),
          child: Text(
            _mode == _AuthMode.signIn ? 'Sign Up' : 'Sign In',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.emerald600),
          ),
        ),
      ],
    );
  }
}

// ─── Helper Types ──────────────────────────────────────────────────

enum _AuthMode { signIn, signUp, forgotPassword }

// ─── Reusable Widgets ──────────────────────────────────────────────

class _OAuthButton extends StatelessWidget {
  const _OAuthButton({required this.onTap, required this.icon, required this.label, this.iconSize = 24});
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BillyTheme.gray200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: BillyTheme.gray800),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          ],
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
      decoration: InputDecoration(
        hintText: hint ?? label,
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20, color: BillyTheme.gray400) : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.emerald600, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.red400)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.red500, width: 2)),
        hintStyle: TextStyle(color: BillyTheme.gray400, fontWeight: FontWeight.w400),
        labelStyle: TextStyle(color: BillyTheme.gray500, fontWeight: FontWeight.w500),
        errorStyle: TextStyle(color: BillyTheme.red500, fontSize: 12),
      ),
    );
  }
}
