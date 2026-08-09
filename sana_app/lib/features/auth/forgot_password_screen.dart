import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/error_display.dart';
import '../../core/utils/validators.dart';
import 'auth_provider.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/sana_brand_header.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await auth.sendPasswordReset(email: _email.text);
    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SanaBrandHeader(compact: true),
                const SizedBox(height: 28),
                Text('Reset your password', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  "Enter your email and we'll send you a reset link.",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                AuthTextField(
                  label: 'Email',
                  controller: _email,
                  validator: Validators.email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                ),
                if (auth.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(message: auth.errorMessage!),
                ],
                if (_sent) ...[
                  const SizedBox(height: 16),
                  Text(
                    'If an account exists for that email, a reset link has been sent.',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () => _submit(auth),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
