import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'license_checker.dart';
import 'license_cubit.dart';

final _stamp = DateFormat('d MMM y, h:mm a');

/// "3 days left", "expires today", "expired 2 days ago", or "no end date". Whole days between the trusted now and the end.
String licenseTimeLeft(DateTime? end, DateTime now) {
  if (end == null) return 'No end date';
  final left = end.difference(now);
  if (left.isNegative || left == Duration.zero) {
    final ago = now.difference(end).inDays;
    return ago == 0 ? 'Expired today' : 'Expired $ago ${ago == 1 ? 'day' : 'days'} ago';
  }
  final days = left.inDays;
  if (days == 0) return 'Ends today';
  return '$days ${days == 1 ? 'day' : 'days'} left';
}

String _statusText(LicenseStatus s) => switch (s) {
  LicenseStatus.valid => 'Active',
  LicenseStatus.expired => 'Expired',
  LicenseStatus.suspended => 'Suspended',
  LicenseStatus.revoked => 'Revoked',
  LicenseStatus.clockTamper => 'Date/time check failed',
  LicenseStatus.requiresOnlineValidation => 'Needs online validation',
  LicenseStatus.notYetValid => 'Not active yet',
  LicenseStatus.notActivated => 'Not activated',
  LicenseStatus.deviceLimit => 'Device limit reached',
  LicenseStatus.invalid => 'Not valid',
  LicenseStatus.checking => 'Checking…',
};

/// Settings → License: what this device's licence says, read from the certificate kept on the device (works offline).
class LicenseInfo extends StatelessWidget {
  const LicenseInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LicenseCubit, LicenseState>(
      builder: (context, s) {
        final c = s.certificate;
        final now = s.trustedNow ?? DateTime.now().toUtc();
        final bad = s.status != LicenseStatus.valid;
        Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: Text(label, style: AppText.helper)),
              Expanded(child: SelectableText(value, style: color == null ? AppText.body : AppText.bodyStrong.copyWith(color: color))),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Status', _statusText(s.status), color: bad ? AppColors.dangerText : AppColors.successText),
            if (c == null) row('Certificate', 'None on this device. Connect to the internet to activate.')
            else ...[
              row('Plan', c.plan),
              row('Valid from', displayDate(isoDate(c.validFrom.toLocal()))),
              row('Valid until', c.expiresOn == null ? 'No end date' : displayDate(c.expiresOn)),
              row('Time left', licenseTimeLeft(c.expiresAt, now), color: c.expiresAt != null && c.expiresAt!.difference(now).inDays < 15 ? AppColors.dangerText : null),
              row('Devices allowed', '${c.maxDevices}'),
              row('License ID', c.licenseId),
              row('Version', '${c.version}'),
              if (c.supportContact != null && c.supportContact!.isNotEmpty) row('Support', c.supportContact!),
            ],
            row('This device', s.installationId ?? '-'),
            row('Last server check', s.lastServerSync == null ? 'Never' : _stamp.format(s.lastServerSync!.toLocal())),
            if (c?.checkinBy != null) row('Must connect by', _stamp.format(c!.checkinBy!.toLocal())),
            if (s.warning != null) row('Notice', s.warning!, color: AppColors.warningText),
            if (s.notice != null) row('Last check', s.notice!, color: AppColors.dangerText),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: s.busy ? null : () => context.read<LicenseCubit>().validateOnline(),
                icon: s.busy ? const SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                label: const Text('Check with server now'),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text('The licence is checked on this device, so it works without internet. To renew or change it, contact your provider.', style: AppText.helper),
          ],
        );
      },
    );
  }
}
