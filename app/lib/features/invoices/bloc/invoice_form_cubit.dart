import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/accounting.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/models/firm.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/item.dart';
import '../../../data/models/party.dart';
import '../../../data/repositories/accounting_repository.dart';
import '../../../data/repositories/cash_bank_repository.dart';
import '../../../data/repositories/firm_repository.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../data/repositories/items_repository.dart';
import '../../../data/repositories/parties_repository.dart';
import '../../../shared/doc_math.dart';
import '../../../shared/format.dart';

num _r2(num v) => (v * 100).round() / 100;
num _pow10(int n) => const [1, 10, 100, 1000][n.clamp(0, 3)];

/// One editable invoice row. Values are kept as typed text so half-typed numbers aren't reformatted.
///
/// The `*Rev` counters are part of each input's widget key: bumping one makes that input rebuild
/// with the cubit's value. They are bumped only for programmatic changes (picking an item, the
/// discount % ↔ amount sync), never for the user's own typing, so the cursor is left alone.
class LineDraft extends Equatable {
  const LineDraft({
    required this.uid,
    this.itemId,
    this.name = '',
    this.qty = '',
    this.unit,
    this.price = '',
    this.discountPct = '',
    this.discountAmount = '',
    this.discountByAmount = false,
    this.gstRate,
    this.hsnCode,
    this.cessRate,
    this.batchNo = '',
    this.expiryDate,
    this.mrp = '',
    this.serialNos = '',
    this.rowRev = 0,
    this.pctRev = 0,
    this.amountRev = 0,
    this.priceRev = 0,
  });

  final int uid;
  final String? itemId;
  final String name;
  final String qty;
  final String? unit;
  final String price;
  final String discountPct;
  final String discountAmount;

  /// True when the user last typed the discount as an amount (so the amount, not the %, is exact).
  final bool discountByAmount;

  /// GST %; null = no tax.
  final num? gstRate;
  final String? hsnCode;

  /// Compensation cess %; null = none.
  final num? cessRate;
  final String batchNo;
  final String? expiryDate;
  final String mrp;

  /// Serial numbers / IMEIs, comma-separated, one per unit.
  final String serialNos;
  final int rowRev;
  final int pctRev;
  final int amountRev;

  /// Bumped when the price switches between the sale and the wholesale price as the quantity changes.
  final int priceRev;

  bool get isBlank => name.trim().isEmpty && qty.trim().isEmpty && price.trim().isEmpty;

  num get gross => _r2((parseNum(qty) ?? 0) * (parseNum(price) ?? 0));
  num get discount => (parseNum(discountAmount) ?? 0).clamp(0, gross);

  /// Value after discount: tax-inclusive or not, depending on how prices are entered.
  num get net => _r2(gross - discount);

  /// The serial numbers typed, one per unit.
  List<String> get serials => {for (final s in serialNos.split(RegExp(r'[,\n]'))) if (s.trim().isNotEmpty) s.trim()}.toList();

  LineDraft copyWith({
    String? Function()? itemId,
    String? name,
    String? qty,
    String? Function()? unit,
    String? price,
    String? discountPct,
    String? discountAmount,
    bool? discountByAmount,
    num? Function()? gstRate,
    String? Function()? hsnCode,
    num? Function()? cessRate,
    String? batchNo,
    String? Function()? expiryDate,
    String? mrp,
    String? serialNos,
    int? rowRev,
    int? pctRev,
    int? amountRev,
    int? priceRev,
  }) =>
      LineDraft(
        uid: uid,
        itemId: itemId != null ? itemId() : this.itemId,
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unit: unit != null ? unit() : this.unit,
        price: price ?? this.price,
        discountPct: discountPct ?? this.discountPct,
        discountAmount: discountAmount ?? this.discountAmount,
        discountByAmount: discountByAmount ?? this.discountByAmount,
        gstRate: gstRate != null ? gstRate() : this.gstRate,
        hsnCode: hsnCode != null ? hsnCode() : this.hsnCode,
        cessRate: cessRate != null ? cessRate() : this.cessRate,
        batchNo: batchNo ?? this.batchNo,
        expiryDate: expiryDate != null ? expiryDate() : this.expiryDate,
        mrp: mrp ?? this.mrp,
        serialNos: serialNos ?? this.serialNos,
        rowRev: rowRev ?? this.rowRev,
        pctRev: pctRev ?? this.pctRev,
        amountRev: amountRev ?? this.amountRev,
        priceRev: priceRev ?? this.priceRev,
      );

  @override
  List<Object?> get props =>
      [uid, itemId, name, qty, unit, price, discountPct, discountAmount, discountByAmount, gstRate, hsnCode, cessRate, batchNo, expiryDate, mrp, serialNos, rowRev, pctRev, amountRev, priceRev];
}

/// A further part of the money taken with the document, after the first one (e.g. the UPI part of
/// a bill paid part cash, part UPI).
class PartDraft extends Equatable {
  const PartDraft({required this.uid, this.mode = 'cash', this.bankAccountId, this.amount = ''});
  final int uid;
  final String mode;
  final String? bankAccountId;
  final String amount;

  num get value => parseNum(amount) ?? 0;

  PartDraft copyWith({String? mode, String? Function()? bankAccountId, String? amount}) => PartDraft(
        uid: uid,
        mode: mode ?? this.mode,
        bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
        amount: amount ?? this.amount,
      );

  @override
  List<Object?> get props => [uid, mode, bankAccountId, amount];
}

/// An extra charge on the bill (freight, packing, ...), added after tax.
class ChargeDraft extends Equatable {
  const ChargeDraft({required this.uid, this.name = '', this.amount = ''});
  final int uid;
  final String name;
  final String amount;

  num get value => parseNum(amount) ?? 0;

  @override
  List<Object?> get props => [uid, name, amount];
}

/// The parts of a document that only some businesses use, each switched on in settings: a store,
/// a bill-level discount, extra charges, TCS / TDS and loyalty points.
class DocExtras extends Equatable {
  const DocExtras({
    this.godownId,
    this.billDiscount = '',
    this.billDiscountIsPct = true,
    this.charges = const [],
    this.tcsRate = '',
    this.tdsRate = '',
    this.loyaltyRedeem = '',
    this.loyaltyOwn = 0,
    this.rev = 0,
  });

  /// Store the stock moves through; null = main store.
  final String? godownId;
  final String billDiscount;

  /// The bill discount is typed as a percentage (otherwise as an amount).
  final bool billDiscountIsPct;
  final List<ChargeDraft> charges;
  final String tcsRate;
  final String tdsRate;

  /// Loyalty points the customer redeems against this bill.
  final String loyaltyRedeem;

  /// Editing: points this document itself already took off the party's balance (redeemed − earned),
  /// so they are available again while it is being changed.
  final int loyaltyOwn;

  /// Bumped when these values are replaced for the user, so their inputs show the new text.
  final int rev;

  num get chargesTotal => _r2(charges.fold<num>(0, (s, c) => s + c.value));
  int get pointsRedeemed => (parseNum(loyaltyRedeem) ?? 0).toInt();

  DocExtras copyWith({
    String? Function()? godownId,
    String? billDiscount,
    bool? billDiscountIsPct,
    List<ChargeDraft>? charges,
    String? tcsRate,
    String? tdsRate,
    String? loyaltyRedeem,
    int? loyaltyOwn,
    int? rev,
  }) =>
      DocExtras(
        godownId: godownId != null ? godownId() : this.godownId,
        billDiscount: billDiscount ?? this.billDiscount,
        billDiscountIsPct: billDiscountIsPct ?? this.billDiscountIsPct,
        charges: charges ?? this.charges,
        tcsRate: tcsRate ?? this.tcsRate,
        tdsRate: tdsRate ?? this.tdsRate,
        loyaltyRedeem: loyaltyRedeem ?? this.loyaltyRedeem,
        loyaltyOwn: loyaltyOwn ?? this.loyaltyOwn,
        rev: rev ?? this.rev,
      );

  @override
  List<Object?> get props => [godownId, billDiscount, billDiscountIsPct, charges, tcsRate, tdsRate, loyaltyRedeem, loyaltyOwn, rev];
}

enum InvoiceFormResult { none, saved, savedAndNew }

class InvoiceFormState extends Equatable {
  const InvoiceFormState({
    required this.kind,
    this.loadStatus = LoadStatus.loading,
    this.parties = const [],
    this.items = const [],
    this.units = const [],
    this.bankAccounts = const [],
    this.isCash = false,
    this.partyId,
    this.partyName = '',
    this.phone = '',
    this.billingAddress = '',
    this.number = '',
    required this.date,
    this.stateOfSupply,
    this.lines = const [],
    this.gstEnabled = true,
    this.pricesIncludeTax = false,
    this.roundOff = true,
    this.receivedInFull = false,
    this.received = '',
    this.paymentMode = 'cash',
    this.bankAccountId,
    this.extraParts = const [],
    this.linkedAmount = 0,
    this.originalUnpaid = 0,
    this.shippingAddress = '',
    this.dueDate,
    this.dueDateAuto = true,
    this.currencies = const [],
    this.currencyCode,
    this.exchangeRate = '',
    this.settings = const FirmSettings(),
    this.extras = const DocExtras(),
    this.godowns = const [],
    this.creditPrompt = 0,
    this.pendingAndNew = false,
    this.description = '',
    this.formRev = 0,
    this.partyRev = 0,
    this.submitStatus = SubmitStatus.idle,
    this.result = InvoiceFormResult.none,
    this.savedId,
    this.error,
  });

  final InvoiceKind kind;
  final LoadStatus loadStatus;
  final List<Party> parties;
  final List<Item> items;
  final List<Unit> units;
  final List<BankAccount> bankAccounts;

  final bool isCash;
  final String? partyId;
  final String partyName;
  final String phone;
  final String billingAddress;
  final String number;
  final String date;
  final String? stateOfSupply;
  final List<LineDraft> lines;

  /// From settings: whether tax columns are shown at all.
  final bool gstEnabled;

  /// Whether the typed unit prices already include GST.
  final bool pricesIncludeTax;
  final bool roundOff;
  final bool receivedInFull;
  final String received;
  final String paymentMode;

  /// Where bank/UPI/card money goes (or a deposited cheque went).
  final String? bankAccountId;

  /// More payment parts after the first (split payment).
  final List<PartDraft> extraParts;

  /// Editing: already settled by Payment-In/Out entries linked to this document.
  final num linkedAmount;

  /// Editing: what this document left unpaid when it was opened (already part of the party's balance).
  final num originalUnpaid;
  final String shippingAddress;
  final String? dueDate;

  /// The due date still follows the invoice date (the user has not set their own).
  final bool dueDateAuto;
  final List<Currency> currencies;

  /// Currency the document is printed in; null = the business's own.
  final String? currencyCode;
  final String exchangeRate;
  final FirmSettings settings;
  final DocExtras extras;

  /// Stores to choose from (main store first); empty unless godowns are switched on.
  final List<Godown> godowns;

  /// Bumped when saving needs the user to confirm going over the party's credit limit.
  final int creditPrompt;
  final bool pendingAndNew;
  final String description;

  /// Bumped to rebuild every input (form loaded / reset for the next invoice).
  final int formRev;

  /// Bumped when a party is picked, to refresh the phone and address inputs.
  final int partyRev;

  final SubmitStatus submitStatus;
  final InvoiceFormResult result;
  final String? savedId;
  final String? error;

  Party? get party => parties.where((p) => p.id == partyId).firstOrNull;

  bool get _postsTax => kind.type == 'sale' || kind.type == 'purchase';

  /// The whole document worked out as the server will: lines, bill discount, charges, TCS and TDS.
  /// On a foreign-currency document everything here is in that currency.
  DocTotals get doc => computeDoc(
        [
          for (final l in lines)
            DocLineInput(gross: l.gross, discount: l.discount, gstRate: l.gstRate ?? 0, cessRate: settings.cessEnabled || l.cessRate != null ? (l.cessRate ?? 0) : 0),
        ],
        pricesIncludeTax: pricesIncludeTax,
        roundOff: roundOff,
        billDiscountPct: extras.billDiscountIsPct ? parseNum(extras.billDiscount) : null,
        billDiscountAmount: extras.billDiscountIsPct ? null : parseNum(extras.billDiscount),
        charges: extras.chargesTotal,
        tcsRate: _postsTax ? (parseNum(extras.tcsRate) ?? 0) : 0,
        tdsRate: _postsTax ? (parseNum(extras.tdsRate) ?? 0) : 0,
      );

  num amountOf(LineDraft l) => doc.lines[lines.indexOf(l)].amount;
  num taxOf(LineDraft l) {
    final d = doc.lines[lines.indexOf(l)];
    return _r2(d.tax + d.cess);
  }

  num get taxableTotal => doc.taxable;
  num get taxTotal => doc.tax;

  /// Sum of line amounts, tax included.
  num get subtotal => doc.subtotal;
  num get total => doc.total;
  num get roundOffValue => doc.roundOff;
  num get totalQty => lines.fold<num>(0, (s, l) => s + (parseNum(l.qty) ?? 0));
  num get totalDiscount => _r2(lines.fold<num>(0, (s, l) => s + l.discount));

  /// Loyalty points the customer can use on this bill, and what the points being redeemed are worth.
  int get loyaltyAvailable => (party?.loyaltyPoints ?? 0) + extras.loyaltyOwn;
  bool get showLoyalty => settings.loyaltyEnabled && kind.isSale && partyId != null && currencyCode == null;
  num get loyaltyAmount => showLoyalty ? _r2(extras.pointsRedeemed * settings.loyaltyPointValue) : 0;
  int get loyaltyEarned => showLoyalty ? ((total - loyaltyAmount) / settings.loyaltyEarnPer).floor().clamp(0, 1 << 31) : 0;

  /// Settled without money moving: TDS the payer holds back and loyalty points redeemed.
  num get deductions => kind.hasPayment ? _r2(doc.tds + loyaltyAmount) : 0;

  /// What can still be paid with the document.
  num get payable => (total - deductions).clamp(0, total);

  num get extraPartsTotal => _r2(extraParts.fold<num>(0, (s, p) => s + p.value));

  /// The first payment part. In cash mode or "received in full" it is whatever the other parts leave.
  num get firstPartValue {
    if (!kind.hasPayment) return 0;
    final rest = (payable - extraPartsTotal).clamp(0, payable);
    return isCash || receivedInFull ? rest : (parseNum(received) ?? 0).clamp(0, rest);
  }

  /// Everything taken with the document. Cash invoices are always fully paid.
  num get receivedValue => kind.hasPayment ? _r2(firstPartValue + extraPartsTotal.clamp(0, payable)) : 0;
  num get balance => _r2(total - receivedValue - linkedAmount - deductions);

  bool get showDueDate => settings.dueDatesEnabled && kind.hasPayment && !isCash;
  bool get showShipping => settings.shippingAddressEnabled && !kind.purchaseSide;
  bool get showDiscounts => settings.itemWiseDiscount;
  bool get showGodown => settings.godownsEnabled && godowns.length > 1;
  bool get showBatch => settings.batchTrackingEnabled;
  bool get showSerial => settings.serialTrackingEnabled && !kind.isQuote;
  bool get showMrp => settings.mrpEnabled;
  bool get showCess => settings.cessEnabled && gstEnabled;

  /// Whether lines carry anything beyond the main row (batch, expiry, MRP, serial numbers, cess).
  bool get showLineExtras => showBatch || showSerial || showMrp || showCess;
  bool get showTcs => settings.tcsEnabled && _postsTax;
  bool get showTds => settings.tdsEnabled && _postsTax;
  Currency? get currency => currencies.where((c) => c.code == currencyCode).firstOrNull;

  /// The symbol amounts on this document are in.
  String get currencySymbol => currencyCode == null ? '₹' : (currency?.symbol ?? currencyCode!);

  /// Rupees per unit of the document's currency (1 for a rupee document).
  num get _rate => currencyCode == null ? 1 : (parseNum(exchangeRate) ?? 0);

  /// A foreign-currency document's total in rupees, as it will be booked; null for a rupee document.
  num? get baseTotal => currencyCode == null || _rate <= 0 ? null : _r2(total * _rate);

  /// Set when this credit sale would take the customer past their credit limit.
  String? get creditLimitWarning {
    final p = party;
    if (!kind.isSale || isCash || p == null || p.creditLimit == null) return null;
    final after = _r2(p.balance - originalUnpaid + (total - receivedValue - deductions) * _rate);
    if (after <= p.creditLimit!) return null;
    return '${p.name} will owe ${money(after)}, over the credit limit of ${money(p.creditLimit)}.';
  }

  InvoiceFormState copyWith({
    LoadStatus? loadStatus,
    List<Party>? parties,
    List<Item>? items,
    List<Unit>? units,
    List<BankAccount>? bankAccounts,
    bool? isCash,
    String? Function()? partyId,
    String? partyName,
    String? phone,
    String? billingAddress,
    String? number,
    String? date,
    String? Function()? stateOfSupply,
    List<LineDraft>? lines,
    bool? gstEnabled,
    bool? pricesIncludeTax,
    bool? roundOff,
    bool? receivedInFull,
    String? received,
    String? paymentMode,
    String? Function()? bankAccountId,
    List<PartDraft>? extraParts,
    num? linkedAmount,
    num? originalUnpaid,
    String? shippingAddress,
    String? Function()? dueDate,
    bool? dueDateAuto,
    List<Currency>? currencies,
    String? Function()? currencyCode,
    String? exchangeRate,
    FirmSettings? settings,
    DocExtras? extras,
    List<Godown>? godowns,
    int? creditPrompt,
    bool? pendingAndNew,
    String? description,
    int? formRev,
    int? partyRev,
    SubmitStatus? submitStatus,
    InvoiceFormResult? result,
    String? savedId,
    String? error,
  }) =>
      InvoiceFormState(
        kind: kind,
        loadStatus: loadStatus ?? this.loadStatus,
        parties: parties ?? this.parties,
        items: items ?? this.items,
        units: units ?? this.units,
        bankAccounts: bankAccounts ?? this.bankAccounts,
        isCash: isCash ?? this.isCash,
        partyId: partyId != null ? partyId() : this.partyId,
        partyName: partyName ?? this.partyName,
        phone: phone ?? this.phone,
        billingAddress: billingAddress ?? this.billingAddress,
        number: number ?? this.number,
        date: date ?? this.date,
        stateOfSupply: stateOfSupply != null ? stateOfSupply() : this.stateOfSupply,
        lines: lines ?? this.lines,
        gstEnabled: gstEnabled ?? this.gstEnabled,
        pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
        roundOff: roundOff ?? this.roundOff,
        receivedInFull: receivedInFull ?? this.receivedInFull,
        received: received ?? this.received,
        paymentMode: paymentMode ?? this.paymentMode,
        bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
        extraParts: extraParts ?? this.extraParts,
        linkedAmount: linkedAmount ?? this.linkedAmount,
        originalUnpaid: originalUnpaid ?? this.originalUnpaid,
        shippingAddress: shippingAddress ?? this.shippingAddress,
        dueDate: dueDate != null ? dueDate() : this.dueDate,
        dueDateAuto: dueDateAuto ?? this.dueDateAuto,
        currencies: currencies ?? this.currencies,
        currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
        exchangeRate: exchangeRate ?? this.exchangeRate,
        settings: settings ?? this.settings,
        extras: extras ?? this.extras,
        godowns: godowns ?? this.godowns,
        creditPrompt: creditPrompt ?? this.creditPrompt,
        pendingAndNew: pendingAndNew ?? this.pendingAndNew,
        description: description ?? this.description,
        formRev: formRev ?? this.formRev,
        partyRev: partyRev ?? this.partyRev,
        submitStatus: submitStatus ?? this.submitStatus,
        result: result ?? this.result,
        savedId: savedId ?? this.savedId,
        error: error,
      );

  @override
  List<Object?> get props => [
        kind, loadStatus, parties, items, units, isCash, partyId, partyName, phone, billingAddress, number, date,
        stateOfSupply, lines, gstEnabled, pricesIncludeTax, roundOff, receivedInFull, received, paymentMode, bankAccountId, bankAccounts, description, formRev, partyRev,
        extraParts, linkedAmount, originalUnpaid, shippingAddress, dueDate, dueDateAuto, currencies, currencyCode, exchangeRate, settings, extras, godowns, creditPrompt,
        pendingAndNew, submitStatus, result, savedId, error,
      ];
}

/// State and rules of the create/edit invoice screen.
class InvoiceFormCubit extends Cubit<InvoiceFormState> {
  InvoiceFormCubit({
    required this._invoices,
    required this._parties,
    required this._items,
    required this._accounts,
    required this._firm,
    this._accounting,
    required ChangeBus bus,
    required InvoiceKind kind,
    this.invoiceId,
    this.fromDocumentId,
  }) : super(InvoiceFormState(kind: kind, date: isoDate(DateTime.now()))) {
    // A party or item added from this screen should appear in the pickers.
    _sub = bus.on({DataTopic.parties, DataTopic.items, DataTopic.catalog, DataTopic.accounts}).listen((_) => _reloadLookups());
  }

  final InvoicesRepository _invoices;
  final PartiesRepository _parties;
  final ItemsRepository _items;
  final CashBankRepository _accounts;
  final FirmRepository _firm;

  /// Only needed to offer foreign currencies.
  final AccountingRepository? _accounting;
  final String? invoiceId;

  /// New document pre-filled from this estimate/order; saving marks that one as converted.
  final String? fromDocumentId;
  late final StreamSubscription<void> _sub;
  int _nextUid = 0;

  bool get editing => invoiceId != null;

  LineDraft _blank() => LineDraft(uid: _nextUid++);

  String _plusDays(String date, int days) => isoDate(DateTime.parse(date).add(Duration(days: days)));

  Future<List<Godown>> _loadGodowns() async {
    try {
      return await _items.godowns();
    } catch (_) {
      return const []; // stock then simply moves through the main store
    }
  }

  Future<List<Currency>> _loadCurrencies() async {
    try {
      return await _accounting?.currencies() ?? const [];
    } catch (_) {
      return const []; // documents are simply printed in the business's own currency
    }
  }

  Future<void> load() async {
    emit(state.copyWith(loadStatus: LoadStatus.loading));
    try {
      final (parties, items, units, bankAccounts) = await (_parties.list(), _items.list('all'), _items.units(), _accounts.accounts()).wait;
      final settings = (await _firm.get()).settings;
      final currencies = await _loadCurrencies();
      final godowns = settings.godownsEnabled ? await _loadGodowns() : const <Godown>[];
      final sourceId = invoiceId ?? fromDocumentId;
      if (sourceId != null) {
        final inv = await _invoices.get(sourceId);
        // Converting: copy the source's party and lines into a new document of this kind.
        final converting = !editing;
        final number = converting ? await _invoices.nextNumber(state.kind.type) : inv.number;
        // The first payment part stays in the single "received" box; any others are listed below it.
        final parts = converting ? const <PaymentPart>[] : inv.payments;
        final first = parts.firstOrNull;
        // A foreign-currency document is edited in its own currency.
        final foreign = inv.isForeign && (inv.exchangeRate ?? 0) > 0;
        final rate = foreign ? inv.exchangeRate! : 1;
        num own(num rupees, num? fx) => foreign ? (fx ?? _r2(rupees / rate)) : rupees;
        final firstAmount = first == null ? (converting ? 0 : own(inv.received, inv.fxReceived)) : own(first.amount, first.fxAmount);
        emit(state.copyWith(
          loadStatus: LoadStatus.success,
          parties: parties,
          items: items,
          units: units,
          bankAccounts: bankAccounts,
          gstEnabled: settings.gstEnabled,
          settings: settings,
          currencies: currencies,
          godowns: godowns,
          extraParts: [
            for (final p in parts.skip(1)) PartDraft(uid: _nextUid++, mode: p.mode, bankAccountId: p.bankAccountId, amount: numText(own(p.amount, p.fxAmount))),
          ],
          linkedAmount: converting ? 0 : (foreign ? _r2((inv.fxTotal ?? 0) - (inv.fxReceived ?? 0) - (inv.fxBalance ?? 0)) : inv.linkedAmount),
          originalUnpaid: converting ? 0 : inv.total - inv.received - inv.tdsAmount - inv.loyaltyAmount,
          extras: DocExtras(
            godownId: inv.godownId,
            // Shown as a percentage when that is how it was given (a round figure), otherwise as the amount.
            billDiscount: inv.discountAmount == 0
                ? ''
                : (inv.discountPct == inv.discountPct.roundToDouble() ? numText(inv.discountPct) : numText(own(inv.discountAmount, null))),
            billDiscountIsPct: inv.discountAmount == 0 || inv.discountPct == inv.discountPct.roundToDouble(),
            charges: [for (final (name, amount) in inv.charges) ChargeDraft(uid: _nextUid++, name: name, amount: numText(own(amount, null)))],
            tcsRate: inv.tcsRate == 0 ? '' : numText(inv.tcsRate),
            tdsRate: inv.tdsRate == 0 ? '' : numText(inv.tdsRate),
            loyaltyRedeem: converting || inv.loyaltyRedeemed == 0 ? '' : '${inv.loyaltyRedeemed}',
            loyaltyOwn: converting ? 0 : inv.loyaltyRedeemed - inv.loyaltyEarned,
            rev: state.extras.rev + 1,
          ),
          shippingAddress: inv.shippingAddress ?? '',
          // An older invoice saved without a due date gets the usual credit period to start from.
          dueDate: () => converting
              ? (settings.dueDatesEnabled ? _plusDays(state.date, settings.defaultCreditDays) : null)
              : (inv.dueDate ?? (settings.dueDatesEnabled ? _plusDays(inv.invoiceDate, settings.defaultCreditDays) : null)),
          dueDateAuto: converting,
          currencyCode: () => inv.currencyCode,
          exchangeRate: inv.exchangeRate == null ? '' : numText(inv.exchangeRate),
          isCash: inv.isCash,
          partyId: () => inv.partyId,
          partyName: inv.partyName,
          phone: inv.phone ?? '',
          billingAddress: inv.billingAddress ?? '',
          number: number,
          date: converting ? state.date : inv.invoiceDate,
          stateOfSupply: () => inv.stateOfSupply,
          lines: [
            for (final l in inv.lines)
              LineDraft(
                uid: _nextUid++,
                itemId: l.itemId,
                name: l.name,
                qty: numText(l.quantity),
                unit: l.unit,
                price: numText(own(l.price, l.fxPrice)),
                discountPct: l.discountPct == 0 ? '' : numText(l.discountPct),
                discountAmount: l.discountAmount == 0 ? '' : numText(own(l.discountAmount, null)),
                cessRate: l.cessRate == 0 ? null : l.cessRate,
                batchNo: l.batchNo ?? '',
                expiryDate: l.expiryDate,
                mrp: numText(l.mrp),
                // Serial numbers belong to the units of one document; a converted document enters its own.
                serialNos: converting ? '' : (l.serialNos ?? ''),
                // Treat it as a % discount only when the % reproduces the stored amount exactly;
                // otherwise the amount is the source of truth and must not be re-derived.
                discountByAmount: _r2(_r2(l.quantity * l.price) * l.discountPct / 100) != l.discountAmount,
                gstRate: l.gstRate == 0 ? null : l.gstRate,
                hsnCode: l.hsnCode,
              ),
          ],
          pricesIncludeTax: inv.pricesIncludeTax,
          roundOff: inv.roundOff != 0 || inv.total == inv.total.roundToDouble(),
          receivedInFull: !converting && !inv.isCash && inv.received > 0 && inv.received == inv.total - inv.tdsAmount - inv.loyaltyAmount,
          received: firstAmount == 0 ? '' : numText(firstAmount),
          paymentMode: first?.mode ?? inv.paymentMode,
          bankAccountId: () => converting ? null : (first?.bankAccountId ?? inv.bankAccountId),
          description: inv.description ?? '',
          formRev: state.formRev + 1,
        ));
      } else {
        // Await before copying the state so nothing changed in the meantime is overwritten.
        final number = state.kind.numberRequired ? await _invoices.nextNumber(state.kind.type) : '';
        emit(state.copyWith(
          loadStatus: LoadStatus.success,
          parties: parties,
          items: items,
          units: units,
          bankAccounts: bankAccounts,
          gstEnabled: settings.gstEnabled,
          settings: settings,
          currencies: currencies,
          godowns: godowns,
          dueDate: () => settings.dueDatesEnabled ? _plusDays(state.date, settings.defaultCreditDays) : null,
          // New documents start from the business's defaults.
          roundOff: settings.defaultRoundOff,
          isCash: state.kind.supportsCash && settings.defaultCashSale,
          number: number,
          lines: [_blank()],
          formRev: state.formRev + 1,
        ));
      }
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _reloadLookups() async {
    try {
      final (parties, items, units, bankAccounts) = await (_parties.list(), _items.list('all'), _items.units(), _accounts.accounts()).wait;
      if (!isClosed) emit(state.copyWith(parties: parties, items: items, units: units, bankAccounts: bankAccounts));
    } catch (_) {
      // Keep the lists we have; the pickers still work.
    }
  }

  // ---------------------------------------------------------------- header

  void cashToggled(bool isCash) => emit(state.copyWith(isCash: isCash && state.kind.supportsCash));

  void partySelected(Party p) => emit(state.copyWith(
        partyId: () => p.id,
        partyName: p.name,
        phone: p.phone ?? '',
        billingAddress: p.billingAddress ?? '',
        shippingAddress: p.shippingAddress ?? '',
        stateOfSupply: () => p.stateCode ?? state.stateOfSupply,
        partyRev: state.partyRev + 1,
        // A foreign party is billed in its own currency, at the saved rate.
        currencyCode: _currencyOf(p) == null ? null : () => p.currencyCode,
        exchangeRate: _currencyOf(p) == null ? null : numText(_currencyOf(p)!.rate),
      ));

  Currency? _currencyOf(Party p) => state.currencies.where((c) => c.code == p.currencyCode).firstOrNull;

  /// Free typing in the party box; it only stays linked to a party while the text matches its name.
  void partyNameChanged(String text) {
    final match = state.party?.name == text;
    emit(state.copyWith(partyName: text, partyId: () => match ? state.partyId : null));
  }

  void phoneChanged(String v) => emit(state.copyWith(phone: v));
  void billingAddressChanged(String v) => emit(state.copyWith(billingAddress: v));
  void shippingAddressChanged(String v) => emit(state.copyWith(shippingAddress: v));
  void numberChanged(String v) => emit(state.copyWith(number: v));

  /// The due date follows the invoice date until the user picks their own.
  void dateChanged(String v) => emit(state.copyWith(
        date: v,
        dueDate: state.dueDateAuto && state.settings.dueDatesEnabled ? () => _plusDays(v, state.settings.defaultCreditDays) : null,
      ));
  void dueDateChanged(String v) => emit(state.copyWith(dueDate: () => v, dueDateAuto: false));

  /// Picking a currency fills in its saved rate, which can then be adjusted for this document.
  void currencyChanged(String? code) => emit(state.copyWith(
        currencyCode: () => code,
        exchangeRate: code == null ? '' : numText(state.currencies.where((c) => c.code == code).firstOrNull?.rate),
      ));
  void exchangeRateChanged(String v) => emit(state.copyWith(exchangeRate: v));
  void stateOfSupplyChanged(String? v) => emit(state.copyWith(stateOfSupply: () => v));

  // ---------------------------------------------------------------- lines

  void _updateLine(int uid, LineDraft Function(LineDraft) change) =>
      emit(state.copyWith(lines: [for (final l in state.lines) l.uid == uid ? change(l) : l]));

  void addLine() => emit(state.copyWith(lines: [...state.lines, _blank()]));

  void removeLine(int uid) {
    final rest = state.lines.where((l) => l.uid != uid).toList();
    emit(state.copyWith(lines: rest.isEmpty ? [_blank()] : rest));
  }

  /// Picking an item fills its unit, price and default discount, and opens a fresh row below.
  void itemSelected(int uid, Item item) {
    final isSale = state.kind.usesSalePrice;
    // The item's price may be stored with or without tax; convert it to how this document's prices are entered.
    var lines = [
      for (final l in state.lines)
        if (l.uid != uid)
          l
        else
          _withDiscountFromPct(
            l.copyWith(
              itemId: () => item.id,
              name: item.name,
              qty: l.qty.trim().isEmpty ? '1' : l.qty,
              unit: () => item.unit,
              price: numText(_priceFor(item, parseNum(l.qty) ?? 1)),
              discountPct: isSale && item.saleDiscountType == 'percent' && item.saleDiscount > 0 ? numText(item.saleDiscount) : '',
              discountAmount: isSale && item.saleDiscountType == 'amount' && item.saleDiscount > 0 ? numText(item.saleDiscount) : '',
              discountByAmount: isSale && item.saleDiscountType == 'amount' && item.saleDiscount > 0,
              gstRate: () => state.gstEnabled ? item.gstRate : null,
              hsnCode: () => item.hsnCode,
              cessRate: () => state.showCess ? item.cessRate : null,
              mrp: state.showMrp ? numText(item.mrp) : '',
              batchNo: '',
              expiryDate: () => null,
              serialNos: '',
              rowRev: l.rowRev + 1,
            ),
          ),
    ];
    if (lines.last.uid == uid) lines = [...lines, _blank()];
    emit(state.copyWith(lines: lines));
  }

  /// The item's price for [qty], converted to how this document's prices are entered (with or
  /// without tax). Sales switch to the wholesale price from the item's minimum wholesale quantity.
  num _priceFor(Item item, num qty) {
    final isSale = state.kind.usesSalePrice;
    final itemIncludesTax = isSale ? item.salePriceIncludesTax : item.purchasePriceIncludesTax;
    final factor = 1 + (item.gstRate ?? 0) / 100;
    final wholesale = isSale && state.settings.wholesalePriceEnabled && item.wholesalePrice != null && qty >= (item.wholesaleMinQty ?? 1);
    final listPrice = !isSale ? item.purchasePrice : (wholesale ? item.wholesalePrice! : item.salePrice);
    return itemIncludesTax == state.pricesIncludeTax ? listPrice : _r2(state.pricesIncludeTax ? listPrice * factor : listPrice / factor);
  }

  void lineNameChanged(int uid, String text) => _updateLine(
        uid,
        // Editing the text unlinks the item unless it still matches (free-text lines don't move stock).
        (l) => l.copyWith(name: text, itemId: () => text == _itemName(l.itemId) ? l.itemId : null),
      );

  String? _itemName(String? id) => state.items.where((i) => i.id == id).firstOrNull?.name;

  void lineQtyChanged(int uid, String text) => _updateLine(uid, (l) {
        var next = l.copyWith(qty: text);
        // Crossing the wholesale quantity changes the price, unless the user typed their own.
        final item = state.items.where((i) => i.id == l.itemId).firstOrNull;
        if (item != null && l.price == numText(_priceFor(item, parseNum(l.qty) ?? 1))) {
          final price = numText(_priceFor(item, parseNum(text) ?? 1));
          if (price != l.price) next = next.copyWith(price: price, priceRev: l.priceRev + 1);
        }
        return _withDiscountFromPct(next);
      });
  void linePriceChanged(int uid, String text) => _updateLine(uid, (l) => _withDiscountFromPct(l.copyWith(price: text)));
  void lineUnitChanged(int uid, String? unit) => _updateLine(uid, (l) => l.copyWith(unit: () => unit));
  void lineGstRateChanged(int uid, num? rate) => _updateLine(uid, (l) => l.copyWith(gstRate: () => rate));

  void lineCessRateChanged(int uid, String text) => _updateLine(uid, (l) => l.copyWith(cessRate: () => parseNum(text)));
  void lineBatchChanged(int uid, String text) => _updateLine(uid, (l) => l.copyWith(batchNo: text));
  void lineExpiryChanged(int uid, String? date) => _updateLine(uid, (l) => l.copyWith(expiryDate: () => date));
  void lineMrpChanged(int uid, String text) => _updateLine(uid, (l) => l.copyWith(mrp: text));
  void lineSerialsChanged(int uid, String text) => _updateLine(uid, (l) => l.copyWith(serialNos: text));

  /// Picking a batch from stock fills its number, expiry and MRP.
  void lineBatchPicked(int uid, ItemBatch b) => _updateLine(
        uid,
        (l) => l.copyWith(batchNo: b.batchNo, expiryDate: () => b.expiryDate, mrp: b.mrp == null ? l.mrp : numText(b.mrp), rowRev: l.rowRev + 1),
      );

  /// Picking serial numbers from stock sets them and, as each is one unit, the quantity.
  void lineSerialsPicked(int uid, List<String> serials) => _updateLine(
        uid,
        (l) => _withDiscountFromPct(l.copyWith(serialNos: serials.join(', '), qty: serials.isEmpty ? l.qty : '${serials.length}', rowRev: l.rowRev + 1)),
      );

  // Document extras: store, bill discount, charges, TCS / TDS, loyalty points.
  void _extras(DocExtras Function(DocExtras) change) => emit(state.copyWith(extras: change(state.extras)));

  void godownChanged(String? id) => _extras((e) => e.copyWith(godownId: () => id));
  void billDiscountChanged(String v) => _extras((e) => e.copyWith(billDiscount: v));
  void billDiscountModeChanged(bool isPct) => _extras((e) => e.copyWith(billDiscountIsPct: isPct));
  void addCharge() => _extras((e) {
        final used = {for (final c in e.charges) c.name};
        final name = state.settings.chargeNames.where((n) => !used.contains(n)).firstOrNull ?? '';
        return e.copyWith(charges: [...e.charges, ChargeDraft(uid: _nextUid++, name: name)]);
      });
  void removeCharge(int uid) => _extras((e) => e.copyWith(charges: e.charges.where((c) => c.uid != uid).toList()));
  void chargeNameChanged(int uid, String v) =>
      _extras((e) => e.copyWith(charges: [for (final c in e.charges) c.uid == uid ? ChargeDraft(uid: uid, name: v, amount: c.amount) : c]));
  void chargeAmountChanged(int uid, String v) =>
      _extras((e) => e.copyWith(charges: [for (final c in e.charges) c.uid == uid ? ChargeDraft(uid: uid, name: c.name, amount: v) : c]));
  void tcsRateChanged(String v) => _extras((e) => e.copyWith(tcsRate: v));
  void tdsRateChanged(String v) => _extras((e) => e.copyWith(tdsRate: v));
  void loyaltyRedeemChanged(String v) => _extras((e) => e.copyWith(loyaltyRedeem: v));

  /// Switches how the typed prices are read; the numbers themselves are left as typed.
  void pricesIncludeTaxChanged(bool v) => emit(state.copyWith(pricesIncludeTax: v));

  /// Typing a % recalculates the discount amount.
  void lineDiscountPctChanged(int uid, String text) =>
      _updateLine(uid, (l) => _withDiscountFromPct(l.copyWith(discountPct: text, discountByAmount: false)));

  /// Typing an amount recalculates the %.
  void lineDiscountAmountChanged(int uid, String text) => _updateLine(uid, (l) {
        final amount = parseNum(text);
        final pct = (amount == null || l.gross == 0) ? '' : numText(_r2(amount / l.gross * 100));
        return l.copyWith(discountAmount: text, discountPct: pct, discountByAmount: true, pctRev: l.pctRev + 1);
      });

  /// Keeps the discount amount in step with qty/price/% when the discount is percentage-based.
  LineDraft _withDiscountFromPct(LineDraft l) {
    if (l.discountByAmount) return l;
    final pct = parseNum(l.discountPct);
    final amount = pct == null ? '' : numText(_r2(l.gross * pct / 100));
    return amount == l.discountAmount ? l : l.copyWith(discountAmount: amount, amountRev: l.amountRev + 1);
  }

  // ---------------------------------------------------------------- footer

  void roundOffToggled(bool v) => emit(state.copyWith(roundOff: v));
  void receivedInFullToggled(bool v) => emit(state.copyWith(receivedInFull: v));
  void receivedChanged(String v) => emit(state.copyWith(received: v));
  void paymentModeChanged(String v) =>
      emit(state.copyWith(paymentMode: v, bankAccountId: () => bankAccountForMode(v, state.bankAccountId, state.bankAccounts)));
  void bankAccountChanged(String? id) => emit(state.copyWith(bankAccountId: () => id));

  // Split payment: further parts after the first.
  void _updatePart(int uid, PartDraft Function(PartDraft) change) =>
      emit(state.copyWith(extraParts: [for (final p in state.extraParts) p.uid == uid ? change(p) : p]));

  /// Adds a part in a mode not used yet, so "Cash + UPI" is two taps.
  void addPart() {
    final used = {state.paymentMode, for (final p in state.extraParts) p.mode};
    final mode = paymentModes.keys.firstWhere((m) => !used.contains(m), orElse: () => 'cash');
    emit(state.copyWith(
      extraParts: [...state.extraParts, PartDraft(uid: _nextUid++, mode: mode, bankAccountId: bankAccountForMode(mode, null, state.bankAccounts))],
    ));
  }

  void removePart(int uid) => emit(state.copyWith(extraParts: state.extraParts.where((p) => p.uid != uid).toList()));
  void partModeChanged(int uid, String mode) =>
      _updatePart(uid, (p) => p.copyWith(mode: mode, bankAccountId: () => bankAccountForMode(mode, p.bankAccountId, state.bankAccounts)));
  void partBankAccountChanged(int uid, String? id) => _updatePart(uid, (p) => p.copyWith(bankAccountId: () => id));
  void partAmountChanged(int uid, String v) => _updatePart(uid, (p) => p.copyWith(amount: v));
  void descriptionChanged(String v) => emit(state.copyWith(description: v));

  // ---------------------------------------------------------------- save

  /// Returns a message for the first problem, or null when the invoice can be saved.
  String? validate() {
    final s = state;
    if (s.kind.numberRequired && s.number.trim().isEmpty) return 'Enter the ${s.kind.numberLabel.toLowerCase().replaceAll('.', '')}.';
    if (!s.isCash && s.partyId == null) {
      return s.partyName.trim().isEmpty
          ? 'Select a ${s.kind.partyLabel.toLowerCase()}.'
          : '"${s.partyName.trim()}" is not a saved party. Pick one from the list or add it first.';
    }
    final filled = s.lines.where((l) => !l.isBlank).toList();
    if (filled.isEmpty) return 'Add at least one item.';
    for (final l in filled) {
      final row = s.lines.indexOf(l) + 1;
      if (l.name.trim().isEmpty) return 'Row $row: enter the item name.';
      final qty = parseNum(l.qty);
      if (qty == null || qty <= 0) return 'Row $row: enter a quantity greater than 0.';
      final decimals = s.settings.quantityDecimals;
      final scaled = qty * _pow10(decimals);
      if ((scaled - scaled.roundToDouble()).abs() > 1e-6) {
        return decimals == 0 ? 'Row $row: quantity must be a whole number.' : 'Row $row: quantity can have at most $decimals decimal places.';
      }
      final price = parseNum(l.price);
      if (l.price.trim().isNotEmpty && (price == null || price < 0)) return 'Row $row: enter a valid price.';
      final pct = parseNum(l.discountPct);
      if (pct != null && (pct < 0 || pct > 100)) return 'Row $row: discount must be between 0 and 100%.';
      if ((parseNum(l.discountAmount) ?? 0) > l.gross) return 'Row $row: discount is more than the amount.';
      if (s.showSerial && l.serials.isNotEmpty && l.serials.length != qty) {
        return 'Row $row: enter one serial number per unit (quantity ${numText(qty)}, serial numbers ${l.serials.length}).';
      }
      if (l.mrp.trim().isNotEmpty && (parseNum(l.mrp) == null || parseNum(l.mrp)! < 0)) return 'Row $row: enter a valid MRP.';
    }
    final e = s.extras;
    final billDiscount = parseNum(e.billDiscount);
    if (e.billDiscount.trim().isNotEmpty && (billDiscount == null || billDiscount < 0 || (e.billDiscountIsPct && billDiscount > 100))) {
      return e.billDiscountIsPct ? 'The bill discount must be between 0 and 100%.' : 'Enter a valid bill discount.';
    }
    for (final c in e.charges) {
      if (c.name.trim().isEmpty && c.amount.trim().isEmpty) continue;
      if (c.name.trim().isEmpty) return 'Name each additional charge.';
      if (parseNum(c.amount) == null || parseNum(c.amount)! < 0) return 'Enter the amount of "${c.name.trim()}".';
    }
    for (final (label, text) in [('TCS', e.tcsRate), ('TDS', e.tdsRate)]) {
      final rate = parseNum(text);
      if (text.trim().isNotEmpty && (rate == null || rate < 0 || rate > 30)) return '$label must be between 0 and 30%.';
    }
    if (s.showLoyalty && e.loyaltyRedeem.trim().isNotEmpty) {
      final points = parseNum(e.loyaltyRedeem);
      if (points == null || points < 0 || points != points.roundToDouble()) return 'Enter the loyalty points to redeem as a whole number.';
      if (points > s.loyaltyAvailable) return 'The customer has only ${s.loyaltyAvailable} loyalty points.';
      if (s.loyaltyAmount + s.doc.tds > s.total) return 'The points redeemed are worth more than the bill.';
    }
    if (s.kind.hasPayment && !s.isCash && !s.receivedInFull && s.received.trim().isNotEmpty) {
      final r = parseNum(s.received);
      if (r == null || r < 0) return 'Enter a valid ${s.kind.paidLabel.toLowerCase()} amount.';
      if (r > s.total) return '${s.kind.paidLabel} amount cannot be more than the total.';
    }
    if (s.kind.hasPayment) {
      for (final p in s.extraParts) {
        final amount = parseNum(p.amount);
        if (amount == null || amount <= 0) return 'Enter the amount of each payment, or remove the empty one.';
        final problem = bankAccountProblem(p.mode, p.bankAccountId, s.bankAccounts);
        if (problem != null) return problem;
      }
      if (s.extraPartsTotal > s.total) return 'The payments add up to more than the total.';
      if (s.extraParts.isNotEmpty && !s.isCash && !s.receivedInFull && (parseNum(s.received) ?? 0) + s.extraPartsTotal > s.total) {
        return 'The payments add up to more than the total.';
      }
      if (s.receivedValue + s.linkedAmount + s.deductions > s.total) {
        return 'Payments of ${money(s.linkedAmount)} are already linked to this ${s.kind.singular.toLowerCase()}; reduce the amount ${s.kind.paidLabel.toLowerCase()} here.';
      }
    }
    // The account only matters when some money actually changes hands now.
    if (s.kind.hasPayment && s.firstPartValue > 0) {
      final problem = bankAccountProblem(s.paymentMode, s.bankAccountId, s.bankAccounts);
      if (problem != null) return problem;
    }
    if (s.currencyCode != null) {
      final rate = parseNum(s.exchangeRate);
      if (rate == null || rate <= 0) return 'Enter the exchange rate for ${s.currencyCode}.';
    }
    return null;
  }

  Map<String, dynamic> _body() {
    final s = state;
    return {
      'type': s.kind.type,
      if (!editing && fromDocumentId != null) 'fromDocumentId': fromDocumentId,
      'number': s.number.trim(),
      'invoiceDate': s.date,
      'isCash': s.isCash,
      'partyId': s.partyId,
      'partyName': s.partyName.trim(),
      'phone': s.phone.trim(),
      'billingAddress': s.billingAddress.trim(),
      'stateOfSupply': s.stateOfSupply,
      'roundOff': s.roundOff,
      'pricesIncludeTax': s.pricesIncludeTax,
      'received': s.receivedValue,
      'paymentMode': s.paymentMode,
      'bankAccountId': s.kind.hasPayment ? s.bankAccountId : null,
      // Paid in several parts: the parts replace the single amount above.
      if (s.kind.hasPayment && s.extraParts.isNotEmpty)
        'payments': [
          if (s.firstPartValue > 0) {'mode': s.paymentMode, 'bankAccountId': s.bankAccountId, 'amount': s.firstPartValue},
          for (final p in s.extraParts) {'mode': p.mode, 'bankAccountId': p.bankAccountId, 'amount': p.value},
        ],
      if (s.showGodown) 'godownId': s.extras.godownId,
      if (s.settings.billDiscountEnabled && (parseNum(s.extras.billDiscount) ?? 0) > 0)
        (s.extras.billDiscountIsPct ? 'discountPct' : 'discountAmount'): parseNum(s.extras.billDiscount),
      if (s.settings.additionalChargesEnabled)
        'charges': [
          for (final c in s.extras.charges)
            if (c.name.trim().isNotEmpty && c.value > 0) {'name': c.name.trim(), 'amount': c.value},
        ],
      if (s.showTcs && (parseNum(s.extras.tcsRate) ?? 0) > 0) 'tcsRate': parseNum(s.extras.tcsRate),
      if (s.showTds && (parseNum(s.extras.tdsRate) ?? 0) > 0) 'tdsRate': parseNum(s.extras.tdsRate),
      if (s.showLoyalty && s.extras.pointsRedeemed > 0) 'loyaltyRedeem': s.extras.pointsRedeemed,
      if (s.showShipping) 'shippingAddress': s.shippingAddress.trim(),
      if (s.showDueDate && s.dueDate != null) 'dueDate': s.dueDate,
      if (s.currencyCode != null) ...{'currencyCode': s.currencyCode, 'exchangeRate': parseNum(s.exchangeRate)},
      'description': s.description.trim(),
      'lines': [
        for (final l in s.lines.where((l) => !l.isBlank))
          {
            'itemId': l.itemId,
            'name': l.name.trim(),
            'quantity': parseNum(l.qty),
            'unit': l.unit,
            'price': parseNum(l.price) ?? 0,
            if (l.discountByAmount) 'discountAmount': l.discount else 'discountPct': parseNum(l.discountPct) ?? 0,
            'gstRate': l.gstRate,
            'hsnCode': l.hsnCode,
            if (s.showCess && (l.cessRate ?? 0) > 0) 'cessRate': l.cessRate,
            if (s.showBatch && l.batchNo.trim().isNotEmpty) 'batchNo': l.batchNo.trim(),
            if (s.showBatch && l.expiryDate != null) 'expiryDate': l.expiryDate,
            if (s.showMrp && parseNum(l.mrp) != null) 'mrp': parseNum(l.mrp),
            if (s.showSerial && l.serials.isNotEmpty) 'serialNos': l.serials.join(', '),
          },
      ],
    };
  }

  /// Saves the document. Going over the party's credit limit is allowed, but only after the user
  /// confirms: the first call raises [InvoiceFormState.creditPrompt], and the screen calls again
  /// with [overLimitConfirmed].
  Future<void> save({required bool andNew, bool overLimitConfirmed = false}) async {
    if (state.submitStatus == SubmitStatus.submitting) return;
    final problem = validate();
    if (problem != null) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, result: InvoiceFormResult.none, error: problem));
      return;
    }
    if (state.creditLimitWarning != null && !overLimitConfirmed) {
      emit(state.copyWith(creditPrompt: state.creditPrompt + 1, pendingAndNew: andNew, submitStatus: SubmitStatus.idle));
      return;
    }
    emit(state.copyWith(submitStatus: SubmitStatus.submitting, result: InvoiceFormResult.none));
    try {
      final saved = await _invoices.save(invoiceId, _body());
      if (!andNew) {
        emit(state.copyWith(submitStatus: SubmitStatus.success, result: InvoiceFormResult.saved, savedId: saved.id));
        return;
      }
      // Fresh form for the next invoice, keeping the lookups and cash/credit choice.
      final next = state.kind.numberRequired ? await _invoices.nextNumber(state.kind.type) : '';
      emit(InvoiceFormState(
        kind: state.kind,
        loadStatus: LoadStatus.success,
        parties: state.parties,
        items: state.items,
        units: state.units,
        bankAccounts: state.bankAccounts,
        isCash: state.isCash,
        gstEnabled: state.gstEnabled,
        settings: state.settings,
        currencies: state.currencies,
        godowns: state.godowns,
        extras: DocExtras(godownId: state.extras.godownId, rev: state.extras.rev + 1),
        dueDate: state.settings.dueDatesEnabled ? _plusDays(state.date, state.settings.defaultCreditDays) : null,
        roundOff: state.roundOff,
        pricesIncludeTax: state.pricesIncludeTax,
        number: next,
        date: state.date,
        lines: [_blank()],
        formRev: state.formRev + 1,
        submitStatus: SubmitStatus.success,
        result: InvoiceFormResult.savedAndNew,
        savedId: saved.id,
      ));
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
