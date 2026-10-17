import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../data/models/item.dart';
import '../../data/repositories/cash_bank_repository.dart';
import '../../data/repositories/invoices_repository.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/format.dart';
import '../invoices/bloc/invoice_form_cubit.dart' show PartDraft;

num _r2(num v) => (v * 100).round() / 100;

/// One item in the bill. Counter prices are tax-inclusive (what the customer pays per unit).
class CartLine extends Equatable {
  const CartLine(this.item, this.qty);
  final Item item;
  final num qty;

  /// Shelf price including GST, whichever way the item's price is stored.
  num get unitPrice => item.salePriceIncludesTax ? item.salePrice : _r2(item.salePrice * (1 + (item.gstRate ?? 0) / 100));

  num get gross => _r2(unitPrice * qty);
  num get discount => item.saleDiscountType == 'percent' ? _r2(gross * item.saleDiscount / 100) : (item.saleDiscount * qty).clamp(0, gross);
  num get amount => _r2(gross - discount);

  @override
  List<Object?> get props => [item, qty];
}

class PosState extends Equatable {
  const PosState({
    this.loadStatus = LoadStatus.loading,
    this.items = const [],
    this.bankAccounts = const [],
    this.search = '',
    this.cart = const [],
    this.customerName = '',
    this.paymentMode = 'cash',
    this.bankAccountId,
    this.extraParts = const [],
    this.billRev = 0,
    this.submitStatus = SubmitStatus.idle,
    this.savedId,
    this.printAfterSave = false,
    this.queued = false,
    this.error,
  });

  final LoadStatus loadStatus;
  final List<Item> items;
  final List<BankAccount> bankAccounts;
  final String search;
  final List<CartLine> cart;
  final String customerName;
  final String paymentMode;
  final String? bankAccountId;

  /// More payment types after the first (split payment).
  final List<PartDraft> extraParts;
  num get extraPartsTotal => (extraParts.fold<num>(0, (s, p) => s + p.value) * 100).round() / 100;

  /// Bumped after each saved bill so the customer input starts empty again.
  final int billRev;
  final SubmitStatus submitStatus;
  final String? savedId;
  final bool printAfterSave;

  /// The last bill could not be sent (no connection) and is kept on this device until the next sync.
  final bool queued;
  final String? error;

  List<Item> get visibleItems {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return items;
    return items.where((i) => i.name.toLowerCase().contains(term) || (i.itemCode ?? '').toLowerCase().contains(term)).toList();
  }

  num get itemCount => cart.fold<num>(0, (s, l) => s + l.qty);
  num get subtotal => _r2(cart.fold<num>(0, (s, l) => s + l.amount));
  num get total => subtotal.round();
  num get roundOff => _r2(total - subtotal);

  PosState copyWith({
    LoadStatus? loadStatus,
    List<Item>? items,
    List<BankAccount>? bankAccounts,
    String? search,
    List<CartLine>? cart,
    String? customerName,
    String? paymentMode,
    String? Function()? bankAccountId,
    List<PartDraft>? extraParts,
    int? billRev,
    SubmitStatus? submitStatus,
    String? savedId,
    bool? printAfterSave,
    bool? queued,
    String? error,
  }) => PosState(
    loadStatus: loadStatus ?? this.loadStatus,
    items: items ?? this.items,
    bankAccounts: bankAccounts ?? this.bankAccounts,
    search: search ?? this.search,
    cart: cart ?? this.cart,
    customerName: customerName ?? this.customerName,
    paymentMode: paymentMode ?? this.paymentMode,
    bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
    extraParts: extraParts ?? this.extraParts,
    billRev: billRev ?? this.billRev,
    submitStatus: submitStatus ?? this.submitStatus,
    savedId: savedId ?? this.savedId,
    printAfterSave: printAfterSave ?? this.printAfterSave,
    queued: queued ?? this.queued,
    error: error,
  );

  @override
  List<Object?> get props => [
    loadStatus,
    items,
    bankAccounts,
    search,
    cart,
    customerName,
    paymentMode,
    bankAccountId,
    extraParts,
    billRev,
    submitStatus,
    savedId,
    printAfterSave,
    queued,
    error,
  ];
}

/// Counter billing: tap items into a cart and save each bill as a fully-paid cash sale.
class PosCubit extends Cubit<PosState> {
  PosCubit(this._invoices, this._items, this._accounts, ChangeBus bus) : super(const PosState()) {
    // Stock shown on the tiles changes with every bill.
    _sub = bus.on({DataTopic.items, DataTopic.accounts}).listen((_) => load());
  }

  final InvoicesRepository _invoices;
  final ItemsRepository _items;
  final CashBankRepository _accounts;
  late final StreamSubscription<void> _sub;

  Future<void> load() async {
    try {
      final (items, accounts, _) = await (_items.list('all'), _accounts.accounts(), _warmNumber()).wait;
      if (isClosed) return;
      emit(state.copyWith(loadStatus: LoadStatus.success, items: items, bankAccounts: accounts));
    } catch (e) {
      if (!isClosed && state.items.isEmpty) emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  /// Reading the next bill number now keeps a copy on the device, so billing can start while offline.
  Future<void> _warmNumber() async {
    try {
      await _invoices.nextNumber('sale');
    } catch (_) {
      // Only a head start; saving asks again.
    }
  }

  void searchChanged(String v) => emit(state.copyWith(search: v));
  void customerNameChanged(String v) => emit(state.copyWith(customerName: v));
  void paymentModeChanged(String v) =>
      emit(state.copyWith(paymentMode: v, bankAccountId: () => bankAccountForMode(v, state.bankAccountId, state.bankAccounts)));
  void bankAccountChanged(String? id) => emit(state.copyWith(bankAccountId: () => id));

  int _nextPart = 0;

  // Split payment: further payment types after the first; the first takes the rest of the bill.
  void addPart() {
    final used = {state.paymentMode, for (final p in state.extraParts) p.mode};
    final mode = paymentModes.keys.firstWhere((m) => !used.contains(m), orElse: () => 'cash');
    emit(
      state.copyWith(
        extraParts: [
          ...state.extraParts,
          PartDraft(uid: _nextPart++, mode: mode, bankAccountId: bankAccountForMode(mode, null, state.bankAccounts)),
        ],
      ),
    );
  }

  void removePart(int uid) => emit(state.copyWith(extraParts: state.extraParts.where((p) => p.uid != uid).toList()));
  void _updatePart(int uid, PartDraft Function(PartDraft) f) =>
      emit(state.copyWith(extraParts: [for (final p in state.extraParts) p.uid == uid ? f(p) : p]));
  void partModeChanged(int uid, String mode) =>
      _updatePart(uid, (p) => p.copyWith(mode: mode, bankAccountId: () => bankAccountForMode(mode, p.bankAccountId, state.bankAccounts)));
  void partBankAccountChanged(int uid, String? id) => _updatePart(uid, (p) => p.copyWith(bankAccountId: () => id));
  void partAmountChanged(int uid, String v) => _updatePart(uid, (p) => p.copyWith(amount: v));

  String? _splitProblem() {
    for (final p in state.extraParts) {
      if (p.value <= 0) return 'Enter the amount of each payment type, or remove the empty one.';
      final problem = bankAccountProblem(p.mode, p.bankAccountId, state.bankAccounts);
      if (problem != null) return problem;
    }
    if (state.extraParts.isNotEmpty && state.extraPartsTotal >= state.total) {
      return 'The other payment types add up to the whole bill; remove one or lower them.';
    }
    return null;
  }

  /// Adds one of [item], or bumps its quantity if it is already in the bill.
  void add(Item item) => _setQty(item, (state.cart.where((l) => l.item.id == item.id).firstOrNull?.qty ?? 0) + 1);

  void changeQty(Item item, num delta) => _setQty(item, (state.cart.where((l) => l.item.id == item.id).firstOrNull?.qty ?? 0) + delta);

  void _setQty(Item item, num qty) {
    final cart = [...state.cart];
    final index = cart.indexWhere((l) => l.item.id == item.id);
    if (index < 0) {
      if (qty > 0) cart.add(CartLine(item, qty));
    } else if (qty > 0) {
      cart[index] = CartLine(item, qty);
    } else {
      cart.removeAt(index);
    }
    emit(state.copyWith(cart: cart));
  }

  void clear() => emit(state.copyWith(cart: const []));

  Future<void> save({required bool print}) async {
    if (state.submitStatus == SubmitStatus.submitting) return;
    final problem = state.cart.isEmpty
        ? 'Add at least one item to the bill.'
        : (bankAccountProblem(state.paymentMode, state.bankAccountId, state.bankAccounts) ?? _splitProblem());
    if (problem != null) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: problem));
      return;
    }
    emit(state.copyWith(submitStatus: SubmitStatus.submitting));
    final s = state;
    try {
      final number = await _invoices.nextNumber('sale');
      final saved = await _invoices.saveQueued(label: 'POS bill $number · ${s.cart.length} ${s.cart.length == 1 ? 'item' : 'items'} · ${money(s.total)}', {
        'type': 'sale',
        'number': number,
        'invoiceDate': isoDate(DateTime.now()),
        'isCash': true,
        'partyName': s.customerName.trim(),
        'pricesIncludeTax': true,
        'roundOff': true,
        'paymentMode': s.paymentMode,
        'bankAccountId': s.bankAccountId,
        if (s.extraParts.isNotEmpty)
          'payments': [
            {'mode': s.paymentMode, 'bankAccountId': s.bankAccountId, 'amount': ((s.total - s.extraPartsTotal) * 100).round() / 100},
            for (final p in s.extraParts) {'mode': p.mode, 'bankAccountId': p.bankAccountId, 'amount': p.value},
          ],
        'lines': [
          for (final l in s.cart)
            {
              'itemId': l.item.id,
              'name': l.item.name,
              'quantity': l.qty,
              'unit': l.item.unit,
              'price': l.unitPrice,
              'discountAmount': l.discount,
              'gstRate': l.item.gstRate,
              'hsnCode': l.item.hsnCode,
            },
        ],
      });
      // Start the next bill, keeping the payment choice.
      emit(
        state.copyWith(
          cart: const [],
          customerName: '',
          billRev: s.billRev + 1,
          extraParts: const [],
          submitStatus: SubmitStatus.success,
          savedId: saved.id,
          printAfterSave: print,
          queued: false,
        ),
      );
    } on QueuedOffline {
      emit(
        state.copyWith(
          cart: const [],
          customerName: '',
          billRev: s.billRev + 1,
          extraParts: const [],
          submitStatus: SubmitStatus.success,
          printAfterSave: false,
          queued: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
