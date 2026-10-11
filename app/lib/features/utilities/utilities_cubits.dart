import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/csv.dart';
import '../../shared/format.dart';
import 'import_spec.dart';

// ---------------------------------------------------------------- CSV import

class ImportState extends Equatable {
  const ImportState({this.rows = const [], this.fileError, this.status = SubmitStatus.idle, this.created, this.serverErrors = const [], this.error});

  /// Parsed rows of the chosen file (empty until a file is chosen).
  final List<ImportRow> rows;

  /// Why the file as a whole could not be read.
  final String? fileError;
  final SubmitStatus status;

  /// After importing: how many records were created, and the rows the server rejected.
  final int? created;
  final List<(int, String, String)> serverErrors; // (file line, name, message)
  final String? error;

  List<ImportRow> get valid => rows.where((r) => r.error == null).toList();
  List<ImportRow> get invalid => rows.where((r) => r.error != null).toList();
  bool get done => created != null;

  @override
  List<Object?> get props => [rows, fileError, status, created, serverErrors, error];
}

/// Reads a CSV, shows what will be imported, and sends the valid rows.
class ImportCubit extends Cubit<ImportState> {
  ImportCubit(this._api, this._bus, this.spec) : super(const ImportState());

  final ApiClient _api;
  final ChangeBus _bus;
  final ImportSpec spec;

  String get sampleCsv => toCsv([spec.headers, ...spec.sample]);

  void fileChosen(String text) {
    try {
      final rows = spec.read(parseCsv(text));
      emit(rows.isEmpty ? const ImportState(fileError: 'The file has no data rows.') : ImportState(rows: rows));
    } on FormatException catch (e) {
      emit(ImportState(fileError: e.message));
    }
  }

  void reset() => emit(const ImportState());

  Future<void> import() async {
    final valid = state.valid;
    if (valid.isEmpty || state.status == SubmitStatus.submitting) return;
    emit(ImportState(rows: state.rows, status: SubmitStatus.submitting));
    try {
      final res = await _api.post<Map<String, dynamic>>(spec.endpoint, {spec.bodyKey: [for (final r in valid) r.body]});
      _bus
        ..publish(DataTopic.items)
        ..publish(DataTopic.catalog)
        ..publish(DataTopic.parties);
      emit(ImportState(
        rows: state.rows,
        status: SubmitStatus.success,
        created: res['created'] as int,
        // The server numbers rows within what was sent; map them back to lines of the file.
        serverErrors: [
          for (final e in res['errors'] as List) (valid[(e['row'] as int) - 1].line, e['name'] as String, e['message'] as String),
        ],
      ));
    } catch (e) {
      emit(ImportState(rows: state.rows, status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}

// ---------------------------------------------------------------- bulk update items

/// The editable figures of one item, as typed.
class ItemEdit extends Equatable {
  const ItemEdit({required this.salePrice, required this.purchasePrice, required this.gstRate, required this.minStock});

  factory ItemEdit.of(Item i) =>
      ItemEdit(salePrice: numText(i.salePrice), purchasePrice: numText(i.purchasePrice), gstRate: i.gstRate, minStock: numText(i.minStock));

  final String salePrice;
  final String purchasePrice;
  final num? gstRate;
  final String minStock;

  ItemEdit copyWith({String? salePrice, String? purchasePrice, num? Function()? gstRate, String? minStock}) => ItemEdit(
        salePrice: salePrice ?? this.salePrice,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        gstRate: gstRate != null ? gstRate() : this.gstRate,
        minStock: minStock ?? this.minStock,
      );

  /// Null when everything typed is a valid, non-negative number.
  String? get problem {
    for (final (label, text, required) in [('Sale price', salePrice, true), ('Purchase price', purchasePrice, true), ('Min stock', minStock, false)]) {
      final n = parseNum(text);
      if (text.trim().isEmpty ? required : (n == null || n < 0)) return '$label is not a valid number';
    }
    return null;
  }

  @override
  List<Object?> get props => [salePrice, purchasePrice, gstRate, minStock];
}

class BulkUpdateState extends Equatable {
  const BulkUpdateState({
    this.loadStatus = LoadStatus.loading,
    this.items = const [],
    this.edits = const {},
    this.search = '',
    this.rev = 0,
    this.status = SubmitStatus.idle,
    this.updated,
    this.error,
  });

  final LoadStatus loadStatus;
  final List<Item> items;

  /// Edited rows only, by item id.
  final Map<String, ItemEdit> edits;
  final String search;

  /// Bumped when the table is reloaded so inputs show the saved values.
  final int rev;
  final SubmitStatus status;
  final int? updated;
  final String? error;

  ItemEdit editOf(Item i) => edits[i.id] ?? ItemEdit.of(i);

  List<Item> get visible {
    final term = search.trim().toLowerCase();
    return term.isEmpty ? items : items.where((i) => i.name.toLowerCase().contains(term) || (i.itemCode ?? '').toLowerCase().contains(term)).toList();
  }

  /// Items whose edited values differ from what is saved.
  List<Item> get changed => items.where((i) => edits.containsKey(i.id) && edits[i.id] != ItemEdit.of(i)).toList();

  BulkUpdateState copyWith({
    LoadStatus? loadStatus,
    List<Item>? items,
    Map<String, ItemEdit>? edits,
    String? search,
    int? rev,
    SubmitStatus? status,
    int? updated,
    String? error,
  }) =>
      BulkUpdateState(
        loadStatus: loadStatus ?? this.loadStatus,
        items: items ?? this.items,
        edits: edits ?? this.edits,
        search: search ?? this.search,
        rev: rev ?? this.rev,
        status: status ?? this.status,
        updated: updated ?? this.updated,
        error: error,
      );

  @override
  List<Object?> get props => [loadStatus, items, edits, search, rev, status, updated, error];
}

/// Edit prices, tax rate and minimum stock of many items in one table.
class BulkUpdateCubit extends Cubit<BulkUpdateState> {
  BulkUpdateCubit(this._items, this._api, this._bus) : super(const BulkUpdateState());

  final ItemsRepository _items;
  final ApiClient _api;
  final ChangeBus _bus;

  Future<void> load() async {
    try {
      final items = await _items.list('all');
      emit(BulkUpdateState(loadStatus: LoadStatus.success, items: items, search: state.search, rev: state.rev + 1, updated: state.updated, status: state.status));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void searchChanged(String v) => emit(state.copyWith(search: v));

  void edit(Item item, ItemEdit Function(ItemEdit) change) =>
      emit(state.copyWith(edits: {...state.edits, item.id: change(state.editOf(item))}, status: SubmitStatus.idle));

  void discard() => emit(state.copyWith(edits: const {}, rev: state.rev + 1, status: SubmitStatus.idle));

  Future<void> save() async {
    final changed = state.changed;
    if (changed.isEmpty || state.status == SubmitStatus.submitting) return;
    for (final i in changed) {
      final problem = state.edits[i.id]!.problem;
      if (problem != null) {
        emit(state.copyWith(status: SubmitStatus.failure, error: '${i.name}: $problem'));
        return;
      }
    }
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      await _api.patch<dynamic>('/items/bulk', {
        'items': [
          for (final i in changed)
            {
              'id': i.id,
              'salePrice': parseNum(state.edits[i.id]!.salePrice),
              'purchasePrice': parseNum(state.edits[i.id]!.purchasePrice),
              'gstRate': state.edits[i.id]!.gstRate,
              'minStock': parseNum(state.edits[i.id]!.minStock),
            },
        ],
      });
      _bus.publish(DataTopic.items);
      emit(state.copyWith(status: SubmitStatus.success, updated: changed.length));
      await load();
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}

// ---------------------------------------------------------------- barcode labels

class BarcodeState extends Equatable {
  const BarcodeState({this.loadStatus = LoadStatus.loading, this.items = const [], this.labels = const {}, this.showPrice = true, this.error});

  final LoadStatus loadStatus;

  /// Items that have an item code (the barcode's content).
  final List<Item> items;

  /// Number of labels to print per item id.
  final Map<String, int> labels;
  final bool showPrice;
  final String? error;

  int get total => labels.values.fold(0, (s, n) => s + n);

  BarcodeState copyWith({LoadStatus? loadStatus, List<Item>? items, Map<String, int>? labels, bool? showPrice, String? error}) => BarcodeState(
        loadStatus: loadStatus ?? this.loadStatus,
        items: items ?? this.items,
        labels: labels ?? this.labels,
        showPrice: showPrice ?? this.showPrice,
        error: error,
      );

  @override
  List<Object?> get props => [loadStatus, items, labels, showPrice, error];
}

/// Chooses how many barcode labels to print for which items.
class BarcodeCubit extends Cubit<BarcodeState> {
  BarcodeCubit(this._items) : super(const BarcodeState());
  final ItemsRepository _items;

  Future<void> load() async {
    try {
      final items = (await _items.list('product')).where((i) => (i.itemCode ?? '').isNotEmpty).toList();
      emit(state.copyWith(loadStatus: LoadStatus.success, items: items));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void setLabels(String itemId, int count) {
    final labels = {...state.labels};
    if (count <= 0) {
      labels.remove(itemId);
    } else {
      labels[itemId] = count.clamp(1, 500);
    }
    emit(state.copyWith(labels: labels));
  }

  void showPriceChanged(bool v) => emit(state.copyWith(showPrice: v));
}
