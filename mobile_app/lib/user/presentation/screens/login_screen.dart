import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'forget_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // 🔐 SECURITY NFR from the report:
  // "User login with an incorrect password must be temporarily locked
  //  out after 5 failed attempts to prevent brute-force attacks."
  static const int _maxAttempts = 5;
  static const int _lockoutMinutes = 5;

  // Keys are scoped by email so one account's failed attempts can't lock
  // another account out on a shared device.
  String get _attemptsKey => 'failedAttempts_${_emailController.text.trim().toLowerCase()}';
  String get _lockoutKey => 'lockoutUntil_${_emailController.text.trim().toLowerCase()}';

  Future<bool> _isLockedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_lockoutKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < lockoutUntil;
  }

  Future<int> _lockoutSecondsRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_lockoutKey) ?? 0;
    final remaining =
        lockoutUntil - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  Future<void> _recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
    await prefs.setInt(_attemptsKey, attempts);

    if (attempts >= _maxAttempts) {
      final lockoutUntil = DateTime.now()
          .add(const Duration(minutes: _lockoutMinutes))
          .millisecondsSinceEpoch;
      await prefs.setInt(_lockoutKey, lockoutUntil);
      await prefs.setInt(_attemptsKey, 0);
    }
  }

  Future<void> _clearFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptsKey);
    await prefs.remove(_lockoutKey);
  }

  Future<void> _login() async {
    // Check lockout BEFORE contacting Firebase
    if (await _isLockedOut()) {
      final secs = await _lockoutSecondsRemaining();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "🔒 Too many failed attempts. Try again in ${(secs / 60).ceil()} minute(s)."),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim())
          .timeout(const Duration(seconds: 15));

      await _clearFailedAttempts();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Connection timed out. Check your internet connection and try again."),
          backgroundColor: Colors.redAccent,
        ));
      }
    } on FirebaseAuthException catch (e) {
      // Count wrong-credential failures toward the lockout
      if (e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential') {
        await _recordFailedAttempt();
      }
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final attempts = prefs.getInt(_attemptsKey) ?? 0;
        final remaining = _maxAttempts - attempts;
        String msg = e.message ?? "Login Failed";
        if (await _isLockedOut()) {
          msg =
              "🔒 Account temporarily locked for $_lockoutMinutes minutes after $_maxAttempts failed attempts.";
        } else if (remaining > 0 && remaining < _maxAttempts) {
          msg = "$msg ($remaining attempt(s) remaining)";
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Fulfills report requirement 1.1 ("...via email or SOCIAL platforms")
  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Google's native layer caches the last-picked account independently
      // of Firebase's own session, so without this, signIn() silently
      // re-resolves to whoever last signed in instead of showing the
      // account picker. signOut() (not disconnect()) just clears that
      // cached pick — it doesn't revoke the app's consent.
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser =
          await googleSignIn.signIn().timeout(const Duration(seconds: 30));
      if (googleUser == null) {
        // User cancelled the picker
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 15));

      // First-time Google users need a wealth profile document too
      // (same one signup_screen.dart creates for email users). This
      // Firestore round-trip is where a flaky network shows up as an
      // endless spinner without a timeout — cloud_firestore's own default
      // deadline is much longer than a user will wait.
      final uid = userCredential.user!.uid;
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await docRef.get().timeout(const Duration(seconds: 15));
      if (!doc.exists) {
        await docRef.set({
          'email': userCredential.user!.email,
          'salary': 0.0,
          'savings': 0.0,
          'expenses': 0.0,
          'RiskProfile': 'Unassigned',
          'TotalXP': 0,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 15));
      }

      await _clearFailedAttempts();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Connection timed out. Check your internet connection and try again."),
          backgroundColor: Colors.redAccent,
        ));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Google Sign-In failed")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Google Sign-In failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WealthTriangle Login")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Image.asset('assets/icon/logo_icon.png', height: 100),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: "Password",
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),

            // ✅ Forgot Password link (requirement 1.3)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen()),
                ),
                child: const Text("Forgot Password?"),
              ),
            ),
            const SizedBox(height: 10),

            _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text("Login"),
                      ),
                      const SizedBox(height: 15),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text("OR",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 15),

                      // ✅ Google Sign-In (requirement 1.1: social platforms)
                      OutlinedButton.icon(
                        onPressed: _loginWithGoogle,
                        icon: const Icon(Icons.g_mobiledata,
                            size: 32, color: Colors.redAccent),
                        label: const Text("Continue with Google"),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SignupScreen()),
                );
              },
              child: const Text("Don't have an account? Sign Up"),
            ),
          ],
        ),
      ),
    );
  }
}