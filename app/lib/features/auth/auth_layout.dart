import 'package:flutter/material.dart';
import '../../shared/theme.dart';

/// Two-pane layout on wide screens (brand panel + form), single column on phones.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: AppSpace.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.dialogMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpace.sm),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpace.xxl),
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 900) return SafeArea(child: form);
        return Row(children: [
          const Expanded(child: _BrandPanel()),
          Expanded(child: form),
        ]);
      }),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onPrimary = scheme.onPrimary;
    return Container(
      color: scheme.primary,
      padding: const EdgeInsets.all(AppSpace.huge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: AppIconSize.hero, color: onPrimary),
          const SizedBox(height: AppSpace.xxl),
          Text('Billing', style: TextStyle(color: onPrimary, fontSize: AppFont.hero, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.md),
          Text(
            'Invoices, parties, stock and payments for your business — in one place.',
            style: TextStyle(color: onPrimary.withValues(alpha: 0.85), fontSize: AppFont.title, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Inline error banner shown above the submit button.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      margin: const EdgeInsets.only(bottom: AppSpace.lg),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: AppRadius.mdAll),
      child: Row(children: [
        Icon(Icons.error_outline, color: scheme.onErrorContainer, size: AppIconSize.md),
        const SizedBox(width: AppSpace.md),
        Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Email is required';
  if (!_emailPattern.hasMatch(v.trim())) return 'Email must be a valid address, like name@example.com';
  return null;
}
