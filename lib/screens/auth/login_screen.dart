import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import 'register_screen.dart';
import '../home/menu_screen.dart';
import '../admin/admin_main_screen.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../restaurant/restaurant_main_screen.dart';
import '../rider/rider_dashboard_screen.dart';
import '../rider/rider_profile_setup_screen.dart';
import '../../services/rider_service.dart';

class LoginScreen extends StatefulWidget {
  final String? initialEmail;
  const LoginScreen({super.key, this.initialEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper function to handle navigation after successful login
  void _navigateAfterLogin(String role, String userId, String name) {
    Widget nextScreen;

    switch (role) {
      case 'admin':
        nextScreen = const AdminMainScreen(initialTabIndex: 0);
        break;
      case 'rider':
        nextScreen = RiderDashboardScreen(userId: userId);
        break;
      case 'restaurant':
        nextScreen = RestaurantMainScreen(userId: userId);
        break;
      default:
        nextScreen = MenuScreen(userName: name, userId: userId);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
    );
  }

  Future<void> _login() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    if (!_formKey.currentState!.validate()) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final hashedPassword = sha256.convert(utf8.encode(password)).toString();

      // First, check if user exists in users table
      final userData = await Supabase.instance.client
          .from('users')
          .select('id, role, name, password')
          .eq('email', email)
          .maybeSingle();

      if (userData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not found.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final role = userData['role'] as String;
      final name = userData['name'] as String? ?? email;
      final userId = userData['id'] as String;

      // Verify password hash
      if (userData['password'] != hashedPassword) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid credentials.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      // For admin users, use Supabase auth
      if (role == 'admin') {
        try {
          final authResponse = await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (authResponse.user == null) {
            throw Exception('Failed to authenticate admin');
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Admin authentication failed.')),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      // For all users, navigate to the appropriate screen
      if (mounted) {
        _navigateAfterLogin(role, userId, name);
      }

      // Now that we're authenticated, determine where to navigate
      Widget nextScreen;

      if (role == 'admin') {
        nextScreen = const AdminMainScreen(initialTabIndex: 0);
      } else if (role == 'rider') {
        // Check if rider has a profile
        final riderService = RiderService();
        final riderProfile = await riderService.getRiderProfile(userId: userId);
        if (riderProfile != null) {
          nextScreen = RiderDashboardScreen(userId: userId);
        } else {
          nextScreen = RiderProfileSetupScreen(userId: userId);
        }
      } else if (role == 'restaurant') {
        nextScreen = RestaurantMainScreen(userId: userId);
      } else {
        nextScreen = MenuScreen(userName: name, userId: userId);
      }

      if (!mounted) return;

      // Wait a brief moment to ensure auth state is properly updated
      await Future.delayed(const Duration(milliseconds: 300));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => nextScreen),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.paddingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo/Title
                  Icon(
                    Icons.restaurant_menu,
                    size: 64,
                    color: AppConstants.primaryColor,
                  ),
                  const SizedBox(height: AppConstants.paddingMedium),
                  Text(
                    'Mappia',
                    style: AppConstants.headingStyle.copyWith(
                      fontSize: 32,
                      color: AppConstants.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppConstants.paddingSmall),
                  Text(
                    'Sign in to your account',
                    style: AppConstants.subheadingStyle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppConstants.paddingXLarge),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.paddingLarge),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppConstants.paddingMedium),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () {
                                    setState(() => _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppConstants.paddingLarge),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConstants.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: AppConstants.paddingMedium),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("Don't have an account? "),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const RegisterScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Register',
                                    style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}