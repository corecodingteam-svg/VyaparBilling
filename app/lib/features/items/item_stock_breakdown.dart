import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/format.dart';
import '../../shared/widgets.dart';
import '../company/firm_cubit.dart';

class StockBreakdown extends Equatable {
  const StockBreakdown({this.stores = const [], this.batches = const [], this.serials = const []});
  final List<GodownStock> stores;
  final List<ItemBatch> batches;
  final List<String> serials;

  @override
  List<Object?> get props => [stores, batches, serials];
}

/// Where an item's stock sits: per store, per batch and by serial number. Each part is only
/// fetched when its feature is switched on, and a part that cannot be fetched is simply left out.
class StockBreakdownCubit extends Cubit<StockBreakdown> {
  StockBreakdownCubit(this._items, this.itemId, {required bool stores, required bool batches, required bool serials})
    : super(const StockBreakdown()) {
    _load(stores, batches, serials);
  }

  final ItemsRepository _items;
  final String itemId;

  Future<T> _try<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _load(bool stores, bool batches, bool serials) async {
    final result = await (
      stores ? _try(() => _items.stockByGodown(itemId), const <GodownStock>[]) : Future.value(const <GodownStock>[]),
      batches ? _try(() => _items.batches(itemId), const <ItemBatch>[]) : Future.value(const <ItemBatch>[]),
      serials ? _try(() => _items.serials(itemId), const <String>[]) : Future.value(const <String>[]),
    ).wait;
    if (!isClosed) emit(StockBreakdown(stores: result.$1, batches: result.$2, serials: result.$3));
  }
}

class ItemStockBreakdown extends StatelessWidget {
  const ItemStockBreakdown({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final s = settingsOf(context, listen: true);
    if (!item.isProduct || !(s.godownsEnabled || s.batchTrackingEnabled || s.serialTrackingEnabled)) return const SizedBox.shrink();
    return BlocProvider(
      key: ValueKey('breakdown-${item.id}-${item.stockQty}'),
      create: (ctx) =>
          StockBreakdownCubit(ctx.read(), item.id, stores: s.godownsEnabled, batches: s.batchTrackingEnabled, serials: s.serialTrackingEnabled),
      child: BlocBuilder<StockBreakdownCubit, StockBreakdown>(
        builder: (context, b) {
          if (b.stores.isEmpty && b.batches.isEmpty && b.serials.isEmpty) return const SizedBox.shrink();
          Widget heading(String text) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          );
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.stores.isNotEmpty) ...[
                  heading('In stores'),
                  Wrap(spacing: 24, runSpacing: 8, children: [for (final g in b.stores) InfoField(g.name, '${qty(g.quantity)} ${item.unit ?? ''}')]),
                ],
                if (b.batches.isNotEmpty) ...[
                  heading('Batches'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final x in b.batches)
                        Chip(
                          label: Text('${x.batchNo} · ${qty(x.quantity)}${x.expiryDate == null ? '' : ' · exp ${displayDate(x.expiryDate)}'}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                if (b.serials.isNotEmpty) ...[
                  heading('Serial numbers in stock (${b.serials.length})'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [for (final sn in b.serials.take(60)) Chip(label: Text(sn), visualDensity: VisualDensity.compact)],
                  ),
                  if (b.serials.length > 60) Text('…and ${b.serials.length - 60} more', style: const TextStyle(color: Colors.black54)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
