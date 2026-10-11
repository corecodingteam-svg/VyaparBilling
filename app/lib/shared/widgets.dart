import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'format.dart';
import 'theme.dart';

/// True when there is room for list + detail side by side.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000;

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: receiveGreen, behavior: SnackBarBehavior.floating));
}

void showError(BuildContext context, Object error) {
  final message = error is ApiException ? error.message : ApiException.from(error).message;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: payRed, behavior: SnackBarBehavior.floating));
}

Future<bool> confirmDelete(BuildContext context, {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: payRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 36, backgroundColor: brandBlue.withValues(alpha: 0.08), child: Icon(icon, size: 34, color: brandBlue)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: TextStyle(color: muted), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
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
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: valueColor)),
        ],
      );
}

/// Text field that opens a date picker; value is an ISO 'YYYY-MM-DD' string.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
        child: Text(displayDate(value)),
      ),
    );
  }
}

/// Positive balances are receivable (green), negative are payable (red).
Color balanceColor(num v) => v > 0 ? receiveGreen : (v < 0 ? payRed : Colors.black54);

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
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(8),
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
    if (accounts.isEmpty) {
      return Text('Add a bank account under Cash & Bank to track this money.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
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
