import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Sign-in, with an optional sign-up mode for provisioning new admin/dev
/// accounts without going through the consumer mobile app or the Firebase
/// Console by hand. Creating an account here never grants admin access by
/// itself — it only proves the credentials are valid. Real admin access is
/// allowlisted server-side via the backend's ADMIN_UIDS env var (see
/// backend/app.py:_require_admin_user); AdminHomeScreen checks that
/// separately via /api/admin/status, so a freshly signed-up account just
/// lands on the "not on the admin allowlist" screen until someone adds its
/// UID there.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? (_isSignUp ? 'Sign-up failed.' : 'Sign-in failed.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/icon/logo_icon.png', height: 72),
                const SizedBox(height: 12),
                const Text(
                  'WealthTriangle Admin',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Creating an account here does not grant admin access on its own — '
                    'its Firebase UID still has to be added to ADMIN_UIDS on the backend.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                          }),
                  child: Text(_isSignUp
                      ? 'Already have an account? Sign In'
                      : "Don't have an account? Create one"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
