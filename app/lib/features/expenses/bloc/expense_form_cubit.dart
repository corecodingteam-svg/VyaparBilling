import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/gst_states.dart';
import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/models/expense.dart';
import '../../../data/repositories/cash_bank_repository.dart';
import '../../../data/repositories/expenses_repository.dart';
import '../../../data/repositories/firm_repository.dart';
import '../../../data/models/invoice.dart' show paymentModes;
import '../../../shared/format.dart';
import '../../invoices/bloc/invoice_form_cubit.dart' show PartDraft;
import '../../../shared/theme.dart';

num _r2(num v) => (v * 100).round() / 100;

/// One editable expense row; values are kept as typed text.
class ExpenseLineDraft extends Equatable {
  const ExpenseLineDraft({required this.uid, this.name = '', this.qty = '', this.price = '', this.gstRate, this.rev = 0});
  final int uid;
  final String name;
  final String qty;
  final String price;

  /// GST % paid on this line; null = none.
  final num? gstRate;

  /// Bumped when a saved expense item fills the row, so its inputs show the new values.
  final int rev;

  bool get isBlank => name.trim().isEmpty && qty.trim().isEmpty && price.trim().isEmpty;
  num get gross => _r2((parseNum(qty) ?? 0) * (parseNum(price) ?? 0));

  // These mirror the server (backend/src/expenses/expenses.service.ts); the server's figures are final.
  num taxable(bool pricesIncludeTax) => pricesIncludeTax ? _r2(gross / (1 + (gstRate ?? 0) / 100)) : gross;
  num tax(bool pricesIncludeTax) => pricesIncludeTax ? _r2(gross - taxable(true)) : _r2(gross * (gstRate ?? 0) / 100);

  /// Tax included.
  num amount([bool pricesIncludeTax = false]) => _r2(taxable(pricesIncludeTax) + tax(pricesIncludeTax));

  ExpenseLineDraft copyWith({String? name, String? qty, String? price, num? Function()? gstRate, int? rev}) => ExpenseLineDraft(
    uid: uid,
    name: name ?? this.name,
    qty: qty ?? this.qty,
    price: price ?? this.price,
    gstRate: gstRate != null ? gstRate() : this.gstRate,
    rev: rev ?? this.rev,
  );

  @override
  List<Object?> get props => [uid, name, qty, price, gstRate, rev];
}

enum ExpenseFormResult { none, saved, savedAndNew }

class ExpenseFormState extends Equatable {
  const ExpenseFormState({
    this.loadStatus = LoadStatus.loading,
    this.categories = const [],
    this.bankAccounts = const [],
    this.bankAccountId,
    this.categoryId,
    this.number = '',
    required this.date,
    this.lines = const [],
    this.itemDefs = const [],
    this.gstEnabled = false,
    this.pricesIncludeTax = false,
    this.roundOff = true,
    this.paymentMode = 'cash',
    this.extraParts = const [],
    this.description = '',
    this.supplierState,
    this.supplierGstin = '',
    this.formRev = 0,
    this.submitStatus = SubmitStatus.idle,
    this.result = ExpenseFormResult.none,
    this.savedId,
    this.error,
    this.issue,
  });

  final LoadStatus loadStatus;
  final List<ExpenseCategory> categories;
  final List<BankAccount> bankAccounts;

  /// Which bank account paid, for bank/UPI/card (or a cleared cheque).
  final String? bankAccountId;
  final String? categoryId;
  final String number;
  final String date;
  final List<ExpenseLineDraft> lines;

  /// Saved expense items offered while typing a row's name.
  final List<ExpenseItemDef> itemDefs;

  /// From settings: whether GST can be recorded on expenses.
  final bool gstEnabled;

  /// Whether the typed prices already include GST.
  final bool pricesIncludeTax;
  final bool roundOff;
  final String paymentMode;

  /// More payment types after the first (split payment).
  final List<PartDraft> extraParts;
  final String description;

  /// Where the supplier billed from; another state than the company's makes the GST IGST.
  final String? supplierState;
  final String supplierGstin;

  /// Bumped to rebuild every input (form loaded / reset for the next expense).
  final int formRev;
  final SubmitStatus submitStatus;
  final ExpenseFormResult result;
  final String? savedId;
  final String? error;

  /// Which part of the form [error] is about, so the screen can outline it.
  final FormIssue? issue;

  num amountOf(ExpenseLineDraft l) => l.amount(pricesIncludeTax);
  num get taxTotal => _r2(lines.fold<num>(0, (s, l) => s + l.tax(pricesIncludeTax)));
  num get taxableTotal => _r2(lines.fold<num>(0, (s, l) => s + l.taxable(pricesIncludeTax)));
  num get extraPartsTotal => _r2(extraParts.fold<num>(0, (s, p) => s + p.value));
  num get subtotal => _r2(lines.fold<num>(0, (s, l) => s + amountOf(l)));
  num get total => roundOff ? subtotal.round() : subtotal;
  num get roundOffValue => _r2(total - subtotal);
  num get totalQty => lines.fold<num>(0, (s, l) => s + (parseNum(l.qty) ?? 0));

  ExpenseFormState copyWith({
    LoadStatus? loadStatus,
    List<ExpenseCategory>? categories,
    List<BankAccount>? bankAccounts,
    String? Function()? bankAccountId,
    String? Function()? categoryId,
    String? number,
    String? date,
    List<ExpenseLineDraft>? lines,
    List<ExpenseItemDef>? itemDefs,
    bool? gstEnabled,
    bool? pricesIncludeTax,
    bool? roundOff,
    String? paymentMode,
    List<PartDraft>? extraParts,
    String? description,
    String? Function()? supplierState,
    String? supplierGstin,
    int? formRev,
    SubmitStatus? submitStatus,
    ExpenseFormResult? result,
    String? savedId,
    String? error,
    FormIssue? issue,
  }) => ExpenseFormState(
    loadStatus: loadStatus ?? this.loadStatus,
    categories: categories ?? this.categories,
    bankAccounts: bankAccounts ?? this.bankAccounts,
    bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    number: number ?? this.number,
    date: date ?? this.date,
    lines: lines ?? this.lines,
    itemDefs: itemDefs ?? this.itemDefs,
    gstEnabled: gstEnabled ?? this.gstEnabled,
    pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
    roundOff: roundOff ?? this.roundOff,
    paymentMode: paymentMode ?? this.paymentMode,
    extraParts: extraParts ?? this.extraParts,
    description: description ?? this.description,
    supplierState: supplierState != null ? supplierState() : this.supplierState,
    supplierGstin: supplierGstin ?? this.supplierGstin,
    formRev: formRev ?? this.formRev,
    submitStatus: submitStatus ?? this.submitStatus,
    result: result ?? this.result,
    savedId: savedId ?? this.savedId,
    error: error,
    issue: issue,
  );

  @override
  List<Object?> get props => [
    loadStatus,
    categories,
    bankAccounts,
    bankAccountId,
    categoryId,
    number,
    date,
    lines,
    itemDefs,
    gstEnabled,
    pricesIncludeTax,
    roundOff,
    paymentMode,
    extraParts,
    description,
    supplierState,
    supplierGstin,
    formRev,
    submitStatus,
    result,
    savedId,
    error,
    issue,
  ];
}

/// State and rules of the create/edit expense screen.
class ExpenseFormCubit extends Cubit<ExpenseFormState> {
  ExpenseFormCubit(this._repo, this._accounts, ChangeBus bus, {this.expenseId, String? categoryId, FirmRepository? firm})
    : super(ExpenseFormState(date: isoDate(DateTime.now()), categoryId: categoryId)) {
    // A category added from this screen should appear in the picker.
    _sub = bus.on({DataTopic.expenses}).listen((_) => _reloadCategories());
    _firm = firm;
  }

  /// Only needed to know whether GST is switched on.
  late final FirmRepository? _firm;

  final ExpensesRepository _repo;
  final CashBankRepository _accounts;
  final String? expenseId;
  late final StreamSubscription<void> _sub;
  int _nextUid = 0;

  bool get editing => expenseId != null;

  ExpenseLineDraft _blank() => ExpenseLineDraft(uid: _nextUid++);

  Future<void> load() async {
    emit(state.copyWith(loadStatus: LoadStatus.loading));
    try {
      final (categories, bankAccounts, itemDefs) = await (_repo.categories(), _accounts.accounts(), _repo.itemDefs()).wait;
      final gstEnabled = (await _firm?.get())?.settings.gstEnabled ?? false;
      if (editing) {
        final e = await _repo.get(expenseId!);
        emit(
          state.copyWith(
            loadStatus: LoadStatus.success,
            categories: categories,
            bankAccounts: bankAccounts,
            itemDefs: itemDefs,
            // Tax already recorded on the expense stays visible even if GST was switched off since.
            gstEnabled: gstEnabled || e.taxAmount > 0,
            pricesIncludeTax: e.pricesIncludeTax,
            bankAccountId: () => e.bankAccountId,
            categoryId: () => e.categoryId,
            number: e.number ?? '',
            date: e.expenseDate,
            lines: [
              for (final l in e.lines)
                ExpenseLineDraft(
                  uid: _nextUid++,
                  name: l.name,
                  qty: numText(l.quantity),
                  price: numText(l.price),
                  gstRate: l.gstRate == 0 ? null : l.gstRate,
                ),
            ],
            roundOff: e.roundOff != 0 || e.total == e.total.roundToDouble(),
            paymentMode: e.payments.firstOrNull?.mode ?? e.paymentMode,
            extraParts: [
              for (final p in e.payments.skip(1)) PartDraft(uid: _nextUid++, mode: p.mode, bankAccountId: p.bankAccountId, amount: numText(p.amount)),
            ],
            description: e.description ?? '',
            supplierState: () => e.supplierState,
            supplierGstin: e.supplierGstin ?? '',
            formRev: state.formRev + 1,
          ),
        );
      } else {
        final preselected = categories.any((c) => c.id == state.categoryId) ? state.categoryId : null;
        emit(
          state.copyWith(
            loadStatus: LoadStatus.success,
            categories: categories,
            bankAccounts: bankAccounts,
            itemDefs: itemDefs,
            gstEnabled: gstEnabled,
            categoryId: () => preselected,
            lines: [_blank()],
            formRev: state.formRev + 1,
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _reloadCategories() async {
    try {
      final (categories, itemDefs) = await (_repo.categories(), _repo.itemDefs()).wait;
      if (!isClosed) emit(state.copyWith(categories: categories, itemDefs: itemDefs));
    } catch (_) {
      // Keep the list we have.
    }
  }

  void categoryChanged(String? id) => emit(state.copyWith(categoryId: () => id));
  void numberChanged(String v) => emit(state.copyWith(number: v));
  void dateChanged(String v) => emit(state.copyWith(date: v));
  void roundOffToggled(bool v) => emit(state.copyWith(roundOff: v));
  void paymentModeChanged(String v) =>
      emit(state.copyWith(paymentMode: v, bankAccountId: () => bankAccountForMode(v, state.bankAccountId, state.bankAccounts)));
  void bankAccountChanged(String? id) => emit(state.copyWith(bankAccountId: () => id));

  // Split payment: further payment types after the first.
  void addPart() {
    final used = {state.paymentMode, for (final p in state.extraParts) p.mode};
    final mode = paymentModes.keys.firstWhere((m) => !used.contains(m), orElse: () => 'cash');
    emit(
      state.copyWith(
        extraParts: [
          ...state.extraParts,
          PartDraft(uid: _nextUid++, mode: mode, bankAccountId: bankAccountForMode(mode, null, state.bankAccounts)),
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
  void descriptionChanged(String v) => emit(state.copyWith(description: v));
  void supplierStateChanged(String? v) => emit(state.copyWith(supplierState: () => v));

  /// A valid GSTIN starts with its state's code, which saves picking the state.
  void supplierGstinChanged(String v) {
    final gstin = v.trim().toUpperCase();
    final code = gstin.length >= 2 && gstStates.containsKey(gstin.substring(0, 2)) ? gstin.substring(0, 2) : null;
    emit(state.copyWith(supplierGstin: gstin, supplierState: code != null ? () => code : null));
  }

  void addLine() => emit(state.copyWith(lines: [...state.lines, _blank()]));

  void removeLine(int uid) {
    final rest = state.lines.where((l) => l.uid != uid).toList();
    emit(state.copyWith(lines: rest.isEmpty ? [_blank()] : rest));
  }

  void _updateLine(int uid, ExpenseLineDraft Function(ExpenseLineDraft) change) =>
      emit(state.copyWith(lines: [for (final l in state.lines) l.uid == uid ? change(l) : l]));

  void lineNameChanged(int uid, String v) => _updateLine(uid, (l) => l.copyWith(name: v));
  void lineQtyChanged(int uid, String v) => _updateLine(uid, (l) => l.copyWith(qty: v));
  void linePriceChanged(int uid, String v) => _updateLine(uid, (l) => l.copyWith(price: v));
  void lineGstRateChanged(int uid, num? rate) => _updateLine(uid, (l) => l.copyWith(gstRate: () => rate));
  void pricesIncludeTaxChanged(bool v) => emit(state.copyWith(pricesIncludeTax: v));

  /// Picking a saved expense item fills its price and tax rate, and opens a fresh row below.
  void itemDefSelected(int uid, ExpenseItemDef def) {
    var lines = [
      for (final l in state.lines)
        if (l.uid != uid)
          l
        else
          l.copyWith(
            name: def.name,
            qty: l.qty.trim().isEmpty ? '1' : l.qty,
            price: def.price == 0 ? l.price : numText(def.price),
            gstRate: () => state.gstEnabled ? def.gstRate : null,
            rev: l.rev + 1,
          ),
    ];
    if (lines.last.uid == uid) lines = [...lines, _blank()];
    emit(state.copyWith(lines: lines));
  }

  /// Returns a message for the first problem, or null when the expense can be saved.
  /// The first problem and which part of the form it is about, or null when the form can be saved.
  FormIssue? firstIssue() {
    final s = state;
    if (s.categoryId == null) return FormIssue('category', 'Select an expense category.');
    final filled = s.lines.where((l) => !l.isBlank).toList();
    if (filled.isEmpty) return FormIssue('items', 'Add at least one item.');
    for (final l in filled) {
      final row = s.lines.indexOf(l) + 1;
      if (l.name.trim().isEmpty) return FormIssue('row:${l.uid}', 'Row $row: enter the item name.');
      final qty = parseNum(l.qty);
      if (qty == null || qty <= 0) return FormIssue('row:${l.uid}', 'Row $row: enter a quantity greater than 0.');
      final price = parseNum(l.price);
      if (price == null || price < 0) return FormIssue('row:${l.uid}', 'Row $row: enter a valid price.');
    }
    for (final p in s.extraParts) {
      if (p.value <= 0) return FormIssue('payments', 'Enter the amount of each payment type, or remove the empty one.');
      final problem = bankAccountProblem(p.mode, p.bankAccountId, s.bankAccounts);
      if (problem != null) return FormIssue('payments', problem);
    }
    if (s.extraParts.isNotEmpty && s.extraPartsTotal >= s.total) {
      return FormIssue('payments', 'The other payment types add up to the whole amount; remove one or lower them.');
    }
    final bank = bankAccountProblem(s.paymentMode, s.bankAccountId, s.bankAccounts);
    return bank == null ? null : FormIssue('payments', bank);
  }

  /// The message for the first problem, or null when the form can be saved.
  String? validate() => firstIssue()?.message;


  Future<void> save({required bool andNew}) async {
    if (state.submitStatus == SubmitStatus.submitting) return;
    final issue = firstIssue();
    final problem = issue?.message;
    if (issue != null) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, result: ExpenseFormResult.none, error: problem, issue: issue));
      return;
    }
    emit(state.copyWith(submitStatus: SubmitStatus.submitting, result: ExpenseFormResult.none));
    final s = state;
    try {
      final saved = await _repo.save(expenseId, {
        'categoryId': s.categoryId,
        'number': s.number.trim(),
        'expenseDate': s.date,
        'roundOff': s.roundOff,
        'pricesIncludeTax': s.pricesIncludeTax,
        'paymentMode': s.paymentMode,
        'bankAccountId': s.bankAccountId,
        if (s.extraParts.isNotEmpty)
          'payments': [
            {'mode': s.paymentMode, 'bankAccountId': s.bankAccountId, 'amount': _r2(s.total - s.extraPartsTotal)},
            for (final p in s.extraParts) {'mode': p.mode, 'bankAccountId': p.bankAccountId, 'amount': p.value},
          ],
        'description': s.description.trim(),
        'supplierState': s.supplierState,
        'supplierGstin': s.supplierGstin.trim(),
        'lines': [
          for (final l in s.lines.where((l) => !l.isBlank))
            {'name': l.name.trim(), 'quantity': parseNum(l.qty), 'price': parseNum(l.price), if (l.gstRate != null) 'gstRate': l.gstRate},
        ],
      });
      if (!andNew) {
        emit(state.copyWith(submitStatus: SubmitStatus.success, result: ExpenseFormResult.saved, savedId: saved.id));
        return;
      }
      // Fresh form in the same category for the next expense.
      emit(
        ExpenseFormState(
          loadStatus: LoadStatus.success,
          categories: state.categories,
          bankAccounts: s.bankAccounts,
          itemDefs: state.itemDefs,
          gstEnabled: s.gstEnabled,
          pricesIncludeTax: s.pricesIncludeTax,
          bankAccountId: s.bankAccountId,
          categoryId: s.categoryId,
          date: s.date,
          lines: [_blank()],
          paymentMode: s.paymentMode,
          formRev: s.formRev + 1,
          submitStatus: SubmitStatus.success,
          result: ExpenseFormResult.savedAndNew,
          savedId: saved.id,
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
