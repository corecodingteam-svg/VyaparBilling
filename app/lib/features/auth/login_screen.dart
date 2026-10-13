import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import 'auth_layout.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_form_cubit.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => AuthFormCubit(ctx.read(), ctx.read<AuthBloc>()),
        child: const _LoginForm(),
      );
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

/// Stateful only to own the text controllers; all UI state lives in [AuthFormCubit].
class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!validateForm(context, _formKey, report: showError)) return;
    context.read<AuthFormCubit>().login(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<AuthFormCubit>().state;
    final loading = form.status == SubmitStatus.submitting;
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Log in with your email and password',
      child: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                controller: _password,
                obscureText: form.obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: form.obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(form.obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: context.read<AuthFormCubit>().togglePasswordVisibility,
                  ),
                ),
                validator: Validators.required('Password'),
              ),
              const SizedBox(height: AppSpace.xxl),
              if (form.status == SubmitStatus.failure && form.error != null) AuthErrorBanner(form.error!),
              FilledButton(
                onPressed: loading ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: loading
                    ? InlineSpinner(color: AppColors.onPrimary)
                    : const Text('Log in', style: TextStyle(fontSize: AppFont.subtitle)),
              ),
              const SizedBox(height: AppSpace.xl),
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text("Don't have an account?"),
                TextButton(onPressed: () => context.go('/register'), child: const Text('Create one')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
