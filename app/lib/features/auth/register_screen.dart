import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import 'auth_layout.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_form_cubit.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => AuthFormCubit(ctx.read(), ctx.read<AuthBloc>()),
        child: const _RegisterForm(),
      );
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm();

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

/// Stateful only to own the text controllers; all UI state lives in [AuthFormCubit].
class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _firm = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_firm, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthFormCubit>().register(
          firmName: _firm.text,
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
        );
  }

  String? _required(String? v, String label) => (v == null || v.trim().length < 2) ? 'Enter $label' : null;

  @override
  Widget build(BuildContext context) {
    final form = context.watch<AuthFormCubit>().state;
    final loading = form.status == SubmitStatus.submitting;
    return AuthLayout(
      title: 'Create your account',
      subtitle: 'Set up your business to start billing',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _firm,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Business name', prefixIcon: Icon(Icons.storefront_outlined)),
              validator: (v) => _required(v, 'your business name'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: form.stateCode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.place_outlined)),
              items: [
                for (final e in gstStates.entries)
                  DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: context.read<AuthFormCubit>().stateCodeChanged,
              validator: (v) => v == null ? 'Select your state' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => _required(v, 'your name'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: form.obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: form.obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(form.obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: context.read<AuthFormCubit>().togglePasswordVisibility,
                ),
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 24),
            if (form.status == SubmitStatus.failure && form.error != null) AuthErrorBanner(form.error!),
            FilledButton(
              onPressed: loading ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Create account', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 20),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Already have an account?'),
              TextButton(onPressed: () => context.go('/login'), child: const Text('Log in')),
            ]),
          ],
        ),
      ),
    );
  }
}
