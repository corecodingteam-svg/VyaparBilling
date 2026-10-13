import 'package:flutter/material.dart';

import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../shared/widgets.dart';
import '../invoices/bloc/invoice_form_cubit.dart' show PartDraft;

/// The payment types after the first when something is paid in several (e.g. part cash, part UPI),
/// each with its own bank account and amount, and the button to add one.
class SplitPartsEditor extends StatelessWidget {
  const SplitPartsEditor({
    super.key,
    required this.parts,
    required this.firstMode,
    required this.bankAccounts,
    required this.symbol,
    required this.onAdd,
    required this.onRemove,
    required this.onMode,
    required this.onBank,
    required this.onAmount,
  });

  final List<PartDraft> parts;

  /// The mode of the first part, so a new one starts with a mode not used yet.
  final String firstMode;
  final List<BankAccount> bankAccounts;
  final String symbol;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int uid, String mode) onMode;
  final void Function(int uid, String? bankAccountId) onBank;
  final void Function(int uid, String amount) onAmount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parts)
          Padding(
            key: ValueKey('split-${p.uid}'),
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('split-mode-${p.uid}-${p.mode}'),
                    initialValue: p.mode,
                    decoration: const InputDecoration(labelText: 'Payment Type'),
                    items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => onMode(p.uid, v!),
                  ),
                ),
                if (modeUsesBank(p.mode))
                  SizedBox(
                    width: 190,
                    child: BankAccountField(
                      accounts: [for (final a in bankAccounts) (a.id, a.name)],
                      value: p.bankAccountId,
                      onChanged: (v) => onBank(p.uid, v),
                    ),
                  ),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    initialValue: p.amount,
                    onChanged: (v) => onAmount(p.uid, v),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(labelText: 'Amount', prefixText: '$symbol '),
                  ),
                ),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => onRemove(p.uid)),
              ],
            ),
          ),
        if (parts.length < paymentModes.length - 1)
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(parts.isEmpty ? 'Add another payment type (split payment)' : 'Add another payment type'),
          ),
      ],
    );
  }
}
