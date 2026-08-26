import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/errors/error_display.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/max_width_box.dart';
import 'auth_provider.dart';
import 'widgets/auth_tab_toggle.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/sana_brand_header.dart';

/// SANA's combined Log In / Sign Up screen — one screen with a tab
/// toggle switching the form beneath it, rather than two separate
/// routes. Reachable at both [AppRoutes.login] and [AppRoutes.signup]
/// (which just set a different [initialTab]); Forgot Password stays
/// its own screen.
///
/// Deliberately minimal: no decorative art, one accent color used only
/// for the active tab and the primary button, left-aligned typography.
/// Wrapped in [MaxWidthBox] so it doesn't stretch edge-to-edge on a
/// wide desktop browser window.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.initialTab = WelcomeTab.logIn});

  final WelcomeTab initialTab;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late WelcomeTab _tab = widget.initialTab;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _switchTab(WelcomeTab tab) {
    if (_tab == tab) return;
    context.read<AuthProvider>().clearError();
    setState(() => _tab = tab);
  }

  Future<void> _submit(AuthProvider auth) async {
    if (!_formKey.currentState!.validate()) return;
    if (_tab == WelcomeTab.logIn) {
      await auth.login(email: _email.text, password: _password.text);
    } else {
      await auth.signUp(email: _email.text, password: _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final isLogIn = _tab == WelcomeTab.logIn;

    return Scaffold(
      body: SafeArea(
        child: MaxWidthBox(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SanaBrandHeader(compact: true),
                  const SizedBox(height: 36),
                  Center(child: AuthTabToggle(tab: _tab, onChanged: _switchTab)),
                  const SizedBox(height: 36),
                  Text(isLogIn ? 'Welcome back!' : 'Welcome!', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    isLogIn
                        ? 'Log in to continue your conversations with SANA.'
                        : 'Create an account to start talking with SANA — your AI debate, brainstorm, and build partner.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  AuthTextField(
                    label: 'Email',
                    controller: _email,
                    validator: Validators.email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    label: 'Password',
                    controller: _password,
                    validator: Validators.password,
                    obscureText: true,
                    textInputAction: isLogIn ? TextInputAction.done : TextInputAction.next,
                  ),
                  if (!isLogIn) ...[
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: 'Confirm password',
                      controller: _confirmPassword,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: (value) => value != _password.text ? 'Passwords do not match' : null,
                    ),
                  ],
                  if (isLogIn)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push(AppRoutes.forgotPassword),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    ErrorBanner(message: auth.errorMessage!),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: auth.isLoading ? null : () => _submit(auth),
                    child: auth.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Development mode: any email + a new-or-existing 6+ character password works.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
