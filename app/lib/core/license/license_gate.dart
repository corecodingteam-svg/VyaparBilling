import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/auth/bloc/auth_bloc.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'license_checker.dart';
import 'license_cubit.dart';

/// Keeps the app behind the licence: only a valid licence gets through to [child]; everything else gets the screen that says why.
class LicenseGate extends StatelessWidget {
  const LicenseGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LicenseCubit, LicenseState>(
      builder: (context, s) {
        if (s.status == LicenseStatus.checking) return const Scaffold(body: Align(alignment: Alignment.topCenter, child: GradientProgressBar()));
        if (!s.allowed) return LicenseBlockedView(state: s);
        final warning = s.warning;
        if (warning == null) return child;
        return Column(
          children: [
            Material(
              color: AppColors.warningSoft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                child: Row(children: [const Icon(Icons.schedule, size: AppIconSize.sm), const SizedBox(width: AppSpace.sm), Expanded(child: Text(warning))]),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

String _title(LicenseStatus s) => switch (s) {
  LicenseStatus.expired => 'License Expired',
  LicenseStatus.clockTamper => 'Date and Time Check Failed',
  LicenseStatus.requiresOnlineValidation => 'License Validation Required',
  LicenseStatus.notActivated => 'Activate This Device',
  LicenseStatus.invalid => 'License Not Valid',
  LicenseStatus.notYetValid => 'License Not Active Yet',
  LicenseStatus.suspended => 'License Suspended',
  LicenseStatus.revoked => 'License Revoked',
  LicenseStatus.deviceLimit => 'Device Limit Reached',
  _ => 'License',
};

IconData _icon(LicenseStatus s) => switch (s) {
  LicenseStatus.expired => Icons.event_busy_outlined,
  LicenseStatus.clockTamper => Icons.schedule,
  LicenseStatus.notActivated => Icons.vpn_key_outlined,
  _ => Icons.lock_outline,
};

/// Shown instead of the app when the licence does not allow it.
class LicenseBlockedView extends StatelessWidget {
  const LicenseBlockedView({super.key, required this.state});
  final LicenseState state;

  String get _instructions => switch (state.status) {
    LicenseStatus.expired => 'To keep using the app, renew your license with your provider. Once it is renewed, connect to the internet and tap "Check again".',
    LicenseStatus.clockTamper => 'Set the correct date and time on this device, connect to the internet and tap "Check again".',
    LicenseStatus.requiresOnlineValidation || LicenseStatus.notActivated => 'Connect this device to the internet and tap "Check again".',
    LicenseStatus.deviceLimit => 'Ask your provider to free a device or raise the limit, then tap "Check again".',
    _ => 'Contact your provider. Once it is sorted out, connect to the internet and tap "Check again".',
  };

  @override
  Widget build(BuildContext context) {
    final cert = state.certificate;
    final s = state.status;
    final expiry = s == LicenseStatus.expired && cert?.expiresOn != null ? displayDate(cert!.expiresOn) : null;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.dialogMd),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(s), size: AppIconSize.xl, color: AppColors.danger),
                const SizedBox(height: AppSpace.md),
                Text(_title(s), style: AppText.headline),
                const SizedBox(height: AppSpace.sm),
                if (expiry != null) Text('Expired on $expiry', style: AppText.subtitle),
                if (state.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(state.message)),
                const SizedBox(height: AppSpace.md),
                Text(_instructions, style: AppText.helper),
                if ((cert?.supportContact ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text('Contact: ${cert!.supportContact}', style: AppText.bodyStrong)),
                if (state.notice != null) Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: Text(state.notice!, style: AppText.error)),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: state.busy ? null : () => context.read<LicenseCubit>().validateOnline(),
                      icon: state.busy ? const SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                      label: const Text('Check again'),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    OutlinedButton(onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()), child: const Text('Sign out')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
