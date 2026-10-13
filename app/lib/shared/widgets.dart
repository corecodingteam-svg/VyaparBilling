import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'format.dart';
import 'theme.dart';

/// True when there is room for list + detail side by side.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= AppSize.wide;

/// Success, error and information messages. Every screen reports results through these, never through its own SnackBar.
void _snack(BuildContext context, String message, Color background) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: background));
}

void showSuccess(BuildContext context, String message) => _snack(context, message, AppColors.successText);

void showError(BuildContext context, Object error) => _snack(context, error is ApiException ? error.message : ApiException.from(error).message, AppColors.dangerText);

void showInfo(BuildContext context, String message) => _snack(context, message, AppColors.text);

Future<bool> confirmDelete(BuildContext context, {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: AppButtons.destructive, onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------- states: loading, empty, error

/// A loading state. By default it shows grey placeholder rows that shimmer, shaped like the list that is about to appear;
/// [LoadingView.spinner] is a plain spinner for a place with no shape to imitate (a chart, a map).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key}) : spinner = false;
  const LoadingView.spinner({super.key}) : spinner = true;
  final bool spinner;

  @override
  Widget build(BuildContext context) => spinner ? const Center(child: CircularProgressIndicator()) : const SkeletonList();
}

/// A small spinner for inside a button while it works.
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: AppIconSize.xs, height: AppIconSize.xs, child: CircularProgressIndicator(strokeWidth: 2, color: color));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: AppIconSize.hero / 2, backgroundColor: AppColors.primarySoft, child: Icon(icon, size: AppIconSize.xl, color: AppColors.primary)),
          const SizedBox(height: AppSpace.lg),
          Text(title, style: AppText.subtitle, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(message!, style: AppText.helper.copyWith(fontSize: AppFont.body), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
        ],
      ),
    ),
  );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'Could not load',
    message: ApiException.from(error).message,
    action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
  );
}

// ---------------------------------------------------------------- text and badges

/// Small grey explanatory text under a field or heading.
class HelperText extends StatelessWidget {
  const HelperText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.helper);
}

/// A problem shown inline, in red.
class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.error);
}

/// The status colours of a badge, as in the admin panel: a tint behind darker text of the same family.
enum BadgeTone {
  success,
  danger,
  warning,
  info,
  brand,
  neutral;

  Color get background => switch (this) {
        success => AppColors.successSoft,
        danger => AppColors.dangerSoft,
        warning => AppColors.warningSoft,
        info => AppColors.infoSoft,
        brand => AppColors.primarySoft,
        neutral => AppColors.neutralSoft,
      };

  Color get foreground => switch (this) {
        success => AppColors.successOnSoft,
        danger => AppColors.dangerOnSoft,
        warning => AppColors.warningText,
        info => AppColors.info,
        brand => AppColors.primaryDark,
        neutral => AppColors.neutralText,
      };
}

/// A small rounded status label ("Connected", "Paid", "Low stock").
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = BadgeTone.neutral});
  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
    decoration: BoxDecoration(color: tone.background, borderRadius: AppRadius.lgAll),
    child: Text(label, style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: tone.foreground)),
  );
}

// ---------------------------------------------------------------- cards

/// A card with a heading, optional description and actions, and its content: the building block of settings and form pages.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.actions = const [], required this.children, this.padding = const EdgeInsets.all(AppSpace.lg)});

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || actions.isNotEmpty)
            Row(
              children: [
                if (title != null) Expanded(child: Text(title!, style: AppText.subtitle)) else const Spacer(),
                if (actions.isNotEmpty) Wrap(spacing: AppSpace.sm, children: actions),
              ],
            ),
          if (subtitle != null) ...[const SizedBox(height: AppSpace.xs), HelperText(subtitle!)],
          if (title != null || subtitle != null) const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    ),
  );
}

/// Read-only label/value pair used in detail headers.
class InfoField extends StatelessWidget {
  const InfoField(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AppText.helper),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor)),
    ],
  );
}

// ---------------------------------------------------------------- fields

/// Text field that opens a date picker; value is an ISO 'YYYY-MM-DD' string.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.parse(value),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(isoDate(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined, size: AppIconSize.sm)),
        child: Text(displayDate(value)),
      ),
    );
  }
}

/// Positive balances are receivable (green), negative are payable (red).
Color balanceColor(num v) => v > 0 ? AppColors.moneyIn : (v < 0 ? AppColors.moneyOut : AppColors.textMuted);

/// Dropdown list shown under an autocomplete field.
class AutocompleteOptions<T extends Object> extends StatelessWidget {
  const AutocompleteOptions({super.key, required this.width, required this.options, required this.onSelected, required this.title, this.subtitle, required this.trailing});

  final double width;
  final Iterable<T> options;
  final AutocompleteOnSelected<T> onSelected;
  final String Function(T) title;
  final String Function(T)? subtitle;
  final Widget Function(T) trailing;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 6,
      shadowColor: AppColors.scrim,
      borderRadius: AppRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 260, maxWidth: width),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final o in options)
              ListTile(
                dense: true,
                title: Text(title(o), overflow: TextOverflow.ellipsis),
                subtitle: subtitle == null ? null : Text(subtitle!(o), overflow: TextOverflow.ellipsis),
                trailing: trailing(o),
                onTap: () => onSelected(o),
              ),
          ],
        ),
      ),
    ),
  );
}

/// "Bank Account" picker shown next to Payment Type when the money goes through a bank.
/// [accounts] are (id, name) pairs so this file stays free of feature models.
class BankAccountField extends StatelessWidget {
  const BankAccountField({super.key, required this.accounts, required this.value, required this.onChanged});
  final List<(String, String)> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) return const HelperText('Add a bank account under Cash & Bank to track this money.');
    return DropdownButtonFormField<String?>(
      key: ValueKey('bank-$value-${accounts.length}'),
      initialValue: accounts.any((a) => a.$1 == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Bank Account *'),
      items: [for (final a in accounts) DropdownMenuItem(value: a.$1, child: Text(a.$2, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------- list rows

/// A row in a list: a title and subtitle, an amount or status on the right, and action buttons. On a narrow screen the
/// actions wrap onto a line of their own beneath the text so nothing is squeezed or overflows.
class ListRow extends StatelessWidget {
  const ListRow({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.actions = const [], this.onTap, this.dense = false});

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  /// The figure or status shown on the right.
  final Widget? trailing;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < AppSize.phone + 120;
    if (!narrow || actions.isEmpty) {
      return ListTile(
        dense: dense,
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: trailing == null && actions.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: [?trailing, if (trailing != null && actions.isNotEmpty) const SizedBox(width: AppSpace.xs), ...actions]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(dense: dense, leading: leading, title: title, subtitle: subtitle, trailing: trailing, onTap: onTap),
        Padding(
          padding: const EdgeInsets.only(left: AppSpace.lg, right: AppSpace.sm, bottom: AppSpace.xs),
          child: Wrap(alignment: WrapAlignment.end, children: actions),
        ),
      ],
    );
  }
}

/// A table that is as wide as the card it is in (so the header row reaches both edges) and scrolls sideways when its columns need more room.
class FullWidthTable extends StatelessWidget {
  const FullWidthTable({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: child),
        ),
      );
}
