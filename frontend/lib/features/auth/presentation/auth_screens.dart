import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../logic/auth_controller.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4866F1), Color(0xFF3955E7)],
          ),
        ),
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SplashLogo(),
                SizedBox(height: 28),
                Text(
                  'Smartify',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 120),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _rememberMe = ref.read(authControllerProvider).rememberMe;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final success = await ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text,
          password: _passwordController.text,
          rememberMe: _rememberMe,
        );
    if (!mounted) {
      return;
    }

    if (!success) {
      final message =
          ref.read(authControllerProvider).errorMessage ?? 'Sign in failed.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome Back!',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your Smart Home, Your Rules.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 34),
                Text('Email', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                    hintText: 'Email',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email.';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text('Password', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() => _rememberMe = value ?? true);
                      },
                    ),
                    Text(
                      'Remember me',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: null,
                      child: const Text('Forgot Password?'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'or',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 22),
                const SocialButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata_rounded,
                ),
                const SizedBox(height: 14),
                const SocialButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple_rounded,
                ),
                const SizedBox(height: 14),
                const SocialButton(
                  label: 'Continue with Facebook',
                  icon: Icons.facebook_rounded,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Sign in',
                  loading: authState.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                const DisabledFeatureBanner(
                  title: 'Social login is coming later',
                  subtitle:
                      'The backend currently supports email and password sign-in only.',
                ),
                const SizedBox(height: 18),
                Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Sign up'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _rememberMe = ref.read(authControllerProvider).rememberMe;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final success = await ref
        .read(authControllerProvider.notifier)
        .register(
          fullName: _fullNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          rememberMe: _rememberMe,
        );
    if (!mounted) {
      return;
    }

    if (!success) {
      final message =
          ref.read(authControllerProvider).errorMessage ?? 'Sign up failed.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create Account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Set up your Smartify account to manage devices, automation, and realtime energy data.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 34),
                Text('Full Name', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    hintText: 'Full name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your full name.';
                    }
                    if (value.trim().length > 120) {
                      return 'Full name must be 120 characters or fewer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text('Email', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                    hintText: 'Email',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email.';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text('Password', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password.';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Confirm Password',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    hintText: 'Confirm password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password.';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() => _rememberMe = value ?? true);
                      },
                    ),
                    Text(
                      'Keep me signed in',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Create Account',
                  loading: authState.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                const DisabledFeatureBanner(
                  title: 'Account registration is live',
                  subtitle:
                      'Your account will be created through /api/auth/register and signed in immediately on success.',
                  icon: Icons.verified_user_outlined,
                ),
                const SizedBox(height: 18),
                Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        'Already have an account?',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
      ),
      child: const Center(
        child: Icon(Icons.wifi_rounded, color: AppColors.primary, size: 58),
      ),
    );
  }
}
