import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart';
import '../../data/models/item.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../payments/split_parts_editor.dart';
import 'pos_cubit.dart';

/// Counter billing: item tiles on one side, the running bill on the other.
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (ctx) => PosCubit(ctx.read(), ctx.read(), ctx.read(), ctx.read())..load(), child: const _PosView());
}

class _PosView extends StatelessWidget {
  const _PosView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosCubit, PosState>(
      listenWhen: (a, b) => a.submitStatus != b.submitStatus && (b.submitStatus == SubmitStatus.success || b.submitStatus == SubmitStatus.failure),
      listener: (context, s) {
        if (s.submitStatus == SubmitStatus.failure) {
          showError(context, s.error!);
          return;
        }
        showSuccess(context, 'Bill saved');
        if (s.printAfterSave) context.push('${InvoiceKind.sale.basePath}/${s.savedId}/preview?layout=thermal');
      },
      builder: (context, state) {
        if (state.loadStatus == LoadStatus.loading) return const LoadingView();
        if (state.loadStatus == LoadStatus.failure) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: context.read<PosCubit>().load);
        }
        if (state.items.isEmpty) {
          return EmptyState(
            icon: Icons.point_of_sale_outlined,
            title: 'Add items to start billing',
            message: 'The POS screen bills from your item list.',
            action: FilledButton(onPressed: () => context.go('/items'), child: const Text('Go to Items')),
          );
        }
        final wide = isWide(context);
        return Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _ItemPicker(state: state)),
                    const SizedBox(width: AppSpace.md),
                    SizedBox(width: AppSize.sidePanel, child: _Bill(state: state)),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 5, child: _ItemPicker(state: state)),
                    const SizedBox(height: AppSpace.md),
                    Expanded(flex: 6, child: _Bill(state: state)),
                  ],
                ),
        );
      },
    );
  }
}

class _ItemPicker extends StatelessWidget {
  const _ItemPicker({required this.state});
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PosCubit>();
    final items = state.visibleItems;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: TextField(
              autofocus: isWide(context),
              onChanged: cubit.searchChanged,
              // Enter adds the only match: quick for typing or scanning an item code.
              onSubmitted: (_) {
                if (items.length == 1) cubit.add(items.single);
              },
              decoration: const InputDecoration(hintText: 'Search item name or scan/type item code', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No matching items'))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisExtent: 96,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ItemTile(item: items[i], inCart: state.cart.where((l) => l.item.id == items[i].id).firstOrNull?.qty),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.inCart});
  final Item item;
  final num? inCart;

  @override
  Widget build(BuildContext context) {
    final selected = inCart != null;
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<PosCubit>().add(item),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      money(CartLine(item, 1).unitPrice),
                      style: const TextStyle(color: AppColors.successText, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (selected)
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.primary,
                      child: Text(qty(inCart), style: const TextStyle(color: AppColors.onPrimary, fontSize: AppFont.caption)),
                    )
                  else if (item.isProduct)
                    Text('Stock ${qty(item.stockQty)}', style: TextStyle(fontSize: AppFont.caption, color: item.stockQty <= 0 ? AppColors.moneyOut : AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bill extends StatelessWidget {
  const _Bill({required this.state});
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PosCubit>();
    final busy = state.submitStatus == SubmitStatus.submitting;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text('Bill · ${qty(state.itemCount)} items', style: AppText.subtitle),
                ),
                if (state.cart.isNotEmpty) TextButton(onPressed: cubit.clear, child: const Text('Clear')),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: state.cart.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(icon: Icons.shopping_basket_outlined, title: 'Tap items to add them to the bill'),
                  )
                : ListView.separated(
                    itemCount: state.cart.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) {
                      final l = state.cart[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.sm, AppSpace.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.item.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${money(l.unitPrice)}${l.discount > 0 ? '  −${money(l.discount)}' : ''}',
                                    style: AppText.helper,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Less',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => cubit.changeQty(l.item, -1),
                            ),
                            SizedBox(
                              width: 30,
                              child: Text(
                                qty(l.qty),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              tooltip: 'More',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.add_circle_outline, color: AppColors.primary),
                              onPressed: () => cubit.changeQty(l.item, 1),
                            ),
                            SizedBox(
                              width: 86,
                              child: Text(
                                money(l.amount),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          // The payment area scrolls when split payments make it taller than the screen can spare.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('customer-${state.billRev}'),
                            initialValue: state.customerName,
                            onChanged: cubit.customerNameChanged,
                            decoration: const InputDecoration(labelText: 'Customer (optional)'),
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        SizedBox(
                          width: AppSize.fieldXs,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('mode-${state.paymentMode}'),
                            initialValue: state.paymentMode,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Payment'),
                            items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                            onChanged: (v) => cubit.paymentModeChanged(v!),
                          ),
                        ),
                      ],
                    ),
                    if (modeUsesBank(state.paymentMode)) ...[
                      const SizedBox(height: AppSpace.md),
                      BankAccountField(
                        accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
                        value: state.bankAccountId,
                        onChanged: cubit.bankAccountChanged,
                      ),
                    ],
                    SplitPartsEditor(
                      parts: state.extraParts,
                      firstMode: state.paymentMode,
                      bankAccounts: state.bankAccounts,
                      symbol: '₹',
                      onAdd: cubit.addPart,
                      onRemove: cubit.removePart,
                      onMode: cubit.partModeChanged,
                      onBank: cubit.partBankAccountChanged,
                      onAmount: cubit.partAmountChanged,
                    ),
                    const SizedBox(height: AppSpace.md),
                    if (state.roundOff != 0)
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Round off', style: TextStyle(color: AppColors.textMuted)),
                          ),
                          Text(numText(state.roundOff), style: const TextStyle(color: AppColors.textMuted)),
                        ],
                      ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Total', style: AppText.title),
                        ),
                        Text(money(state.total), style: AppText.headline),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy ? null : () => cubit.save(print: false),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            child: const Text('Save Bill'),
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy ? null : () => cubit.save(print: true),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            icon: const Icon(Icons.print_outlined, size: AppIconSize.sm),
                            label: const Text('Save & Print'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
