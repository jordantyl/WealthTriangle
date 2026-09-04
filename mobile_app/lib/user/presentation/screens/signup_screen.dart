import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      // 1. Create User
      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim());

      // 2. Create Wealth Profile
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'email': _emailController.text.trim(),
        'salary': 0.0,
        'savings': 0.0,
        'expenses': 0.0,
        'RiskProfile': 'Unassigned', // Maps to ER Diagram
        'TotalXP': 0,                // Maps to ER Diagram
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Explicit navigation, matching how login_screen.dart's own
        // _signIn()/_loginWithGoogle() already get to HomeScreen from this
        // same file. This used to rely on main.dart's root
        // StreamBuilder(authStateChanges()) swapping route "/" underneath
        // once sign-in fired, with just a pop() to reveal it — but that
        // only works if route "/" still IS the StreamBuilder. It isn't
        // after a logout: profile_screen.dart's LOG OUT handler calls
        // Navigator.pushAndRemoveUntil(... LoginScreen() ..., (route) =>
        // false), which discards the StreamBuilder-based route entirely and
        // replaces it with a bare, non-reactive LoginScreen. Confirmed live,
        // on-device: logging out and signing up again left the app stuck on
        // this Create Account screen after a real, successful signup.
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Account created! Taking you to your dashboard...")));
        // pushAndRemoveUntil, not pushReplacement: this screen was reached
        // by pushing on top of LoginScreen, so a plain pushReplacement only
        // swaps the top entry and leaves LoginScreen underneath — confirmed
        // live, on-device, that leaves Home with a stray back button that
        // pops to a stale, already-signed-in login form. Clearing the whole
        // stack (same pattern profile_screen.dart's LOG OUT uses) avoids it.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "An error occurred")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon/logo_icon.png', height: 100),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
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
            ),
            const SizedBox(height: 30),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _signUp,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Sign Up"),
                  ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                // Go back to Login Page
                Navigator.pop(context);
              },
              child: const Text("Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }
}