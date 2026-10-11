import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
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
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: 56, color: onPrimary),
          const SizedBox(height: 24),
          Text('Billing', style: TextStyle(color: onPrimary, fontSize: 40, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            'Invoices, parties, stock and payments for your business — in one place.',
            style: TextStyle(color: onPrimary.withValues(alpha: 0.85), fontSize: 18, height: 1.4),
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
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(v.trim())) return 'Enter a valid email address';
  return null;
}
