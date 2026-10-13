import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/models/accounting.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/models/payment.dart';
import '../../../data/repositories/accounting_repository.dart';
import '../../../data/repositories/cash_bank_repository.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../data/repositories/parties_repository.dart';
import '../../../data/repositories/payments_repository.dart';
import '../../../shared/format.dart';
import '../../invoices/bloc/invoice_form_cubit.dart' show PartDraft;

num _r2(num v) => (v * 100).round() / 100;

/// An invoice of the party that this payment can be set against.
class LinkRow extends Equatable {
  const LinkRow({required this.invoiceId, required this.number, required this.date, required this.total, required this.due, this.amount = ''});
  final String invoiceId;
  final String number;
  final String date;
  final num total;

  /// What the invoice still owes, not counting this payment's own link.
  final num due;

  /// Typed amount of this payment to set against it.
  final String amount;

  num get value => parseNum(amount) ?? 0;

  LinkRow withAmount(String amount) => LinkRow(invoiceId: invoiceId, number: number, date: date, total: total, due: due, amount: amount);

  @override
  List<Object?> get props => [invoiceId, number, date, total, due, amount];
}

/// Non-text state of the payment dialog. Number, amount and description live in controllers.
class PaymentFormState extends Equatable {
  const PaymentFormState({
    this.loadStatus = LoadStatus.loading,
    this.parties = const [],
    this.bankAccounts = const [],
    this.bankAccountId,
    this.partyId,
    this.number = '',
    required this.date,
    this.paymentMode = 'cash',
    this.extraParts = const [],
    this.currencies = const [],
    this.currencyCode,
    this.exchangeRate = '',
    this.links = const [],
    this.linksRev = 0,
    this.submitStatus = SubmitStatus.idle,
    this.saved,
    this.error,
  });

  final LoadStatus loadStatus;
  final List<Party> parties;
  final List<BankAccount> bankAccounts;

  /// Where bank/UPI/card money goes (or a deposited cheque went).
  final String? bankAccountId;
  final String? partyId;

  /// Suggested receipt number, used to fill the number input once loaded.
  final String number;
  final String date;
  final String paymentMode;

  /// More payment modes after the first (split payment).
  final List<PartDraft> extraParts;
  final List<Currency> currencies;

  /// A foreign-currency payment: the amount, the modes and the links are all in it. null = rupees.
  final String? currencyCode;
  final String exchangeRate;

  /// The party's unpaid invoices (sales for Payment-In, purchases for Payment-Out).
  final List<LinkRow> links;

  /// Bumped when the link amounts are filled in for the user, so their inputs show the new text.
  final int linksRev;
  final SubmitStatus submitStatus;
  final Payment? saved;
  final String? error;

  Party? get party => parties.where((p) => p.id == partyId).firstOrNull;
  Currency? get currency => currencies.where((c) => c.code == currencyCode).firstOrNull;
  String get currencySymbol => currencyCode == null ? '₹' : (currency?.symbol ?? currencyCode!);
  num get extraPartsTotal => _r2(extraParts.fold<num>(0, (s, p) => s + p.value));

  /// What the payment comes to in rupees at this rate, for a foreign-currency payment.
  num? baseOf(num amount) {
    final rate = parseNum(exchangeRate);
    return currencyCode == null || rate == null || rate <= 0 ? null : _r2(amount * rate);
  }

  num get linkedTotal => _r2(links.fold<num>(0, (s, l) => s + l.value));

  PaymentFormState copyWith({
    LoadStatus? loadStatus,
    List<Party>? parties,
    List<BankAccount>? bankAccounts,
    String? Function()? bankAccountId,
    String? Function()? partyId,
    String? number,
    String? date,
    String? paymentMode,
    List<PartDraft>? extraParts,
    List<Currency>? currencies,
    String? Function()? currencyCode,
    String? exchangeRate,
    List<LinkRow>? links,
    int? linksRev,
    SubmitStatus? submitStatus,
    Payment? saved,
    String? error,
  }) => PaymentFormState(
    loadStatus: loadStatus ?? this.loadStatus,
    parties: parties ?? this.parties,
    bankAccounts: bankAccounts ?? this.bankAccounts,
    bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
    partyId: partyId != null ? partyId() : this.partyId,
    number: number ?? this.number,
    date: date ?? this.date,
    paymentMode: paymentMode ?? this.paymentMode,
    extraParts: extraParts ?? this.extraParts,
    currencies: currencies ?? this.currencies,
    currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
    exchangeRate: exchangeRate ?? this.exchangeRate,
    links: links ?? this.links,
    linksRev: linksRev ?? this.linksRev,
    submitStatus: submitStatus ?? this.submitStatus,
    saved: saved ?? this.saved,
    error: error,
  );

  @override
  List<Object?> get props => [
    loadStatus,
    parties,
    bankAccounts,
    bankAccountId,
    partyId,
    number,
    date,
    paymentMode,
    extraParts,
    currencies,
    currencyCode,
    exchangeRate,
    links,
    linksRev,
    submitStatus,
    saved,
    error,
  ];
}

class PaymentFormCubit extends Cubit<PaymentFormState> {
  PaymentFormCubit(
    this._payments,
    this._parties,
    this._accounts,
    this.kind, {
    this.payment,
    String? partyId,
    InvoicesRepository? invoices,
    AccountingRepository? accounting,
  }) : super(
         PaymentFormState(
           partyId: payment?.partyId ?? partyId,
           bankAccountId: payment?.bankAccountId,
           number: payment?.number ?? '',
           date: payment?.paymentDate ?? isoDate(DateTime.now()),
           paymentMode: payment?.paymentMode ?? 'cash',
         ),
       ) {
    _invoices = invoices;
    _accounting = accounting;
  }

  late final AccountingRepository? _accounting;
  int _nextUid = 0;

  /// Without it the payment is simply not linked to invoices.
  late final InvoicesRepository? _invoices;

  final PaymentsRepository _payments;
  final PartiesRepository _parties;
  final CashBankRepository _accounts;
  final PaymentKind kind;
  final Payment? payment;

  bool get editing => payment != null;

  Future<void> load() async {
    emit(state.copyWith(loadStatus: LoadStatus.loading));
    try {
      final (parties, bankAccounts) = await (_parties.list(), _accounts.accounts()).wait;
      final number = editing ? payment!.number : await _payments.nextNumber(kind.type);
      var currencies = const <Currency>[];
      try {
        currencies = await _accounting?.currencies() ?? const [];
      } catch (_) {}
      final p = payment;
      // Editing: the first mode stays in the usual fields, any others are listed below it.
      final parts = p?.parts ?? const <PaymentPart>[];
      final foreign = p?.currencyCode != null;
      emit(
        state.copyWith(
          currencies: currencies,
          currencyCode: foreign ? () => p!.currencyCode : null,
          exchangeRate: foreign ? numText(p!.exchangeRate) : null,
          extraParts: [
            for (final x in parts.skip(1)) PartDraft(uid: _nextUid++, mode: x.mode, bankAccountId: x.bankAccountId, amount: numText(x.amount)),
          ],
          paymentMode: parts.firstOrNull?.mode,
          bankAccountId: parts.isEmpty ? null : () => parts.first.bankAccountId,
        ),
      );
      final links = await _loadLinks(state.partyId);
      emit(
        state.copyWith(
          loadStatus: LoadStatus.success,
          parties: parties,
          bankAccounts: bankAccounts,
          number: number,
          links: links,
          linksRev: state.linksRev + 1,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  /// The party's unpaid invoices. When editing, the invoices this payment already settles are
  /// included with their link amounts, and what they owe is shown as if this payment were not there.
  Future<List<LinkRow>> _loadLinks(String? partyId) async {
    final invoices = _invoices;
    if (invoices == null || partyId == null) return const [];
    // Only documents in the payment's currency can be settled by it.
    final unpaid = [
      for (final i in await invoices.unpaid(kind.type == 'in' ? 'sale' : 'purchase', partyId))
        if (i.currencyCode == state.currencyCode) i,
    ];
    final own = editing && partyId == payment!.partyId ? (await _payments.get(payment!.id)).allocations : const <PaymentAllocation>[];
    final rows = <LinkRow>[
      for (final a in own.where((a) => unpaid.every((i) => i.id != a.invoiceId)))
        LinkRow(invoiceId: a.invoiceId, number: a.number, date: a.invoiceDate ?? '', total: a.total, due: a.amount, amount: numText(a.amount)),
      for (final InvoiceSummary i in unpaid)
        () {
          final mine = own.where((a) => a.invoiceId == i.id).firstOrNull?.amount ?? 0;
          return LinkRow(
            invoiceId: i.id,
            number: i.number,
            date: i.invoiceDate,
            total: i.isForeign ? (i.fxTotal ?? i.total) : i.total,
            due: _r2((i.isForeign ? (i.fxBalance ?? i.balance) : i.balance) + mine),
            amount: mine == 0 ? '' : numText(mine),
          );
        }(),
    ];
    return rows..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _reloadLinks() async {
    final partyId = state.partyId;
    try {
      final links = await _loadLinks(partyId);
      if (!isClosed && state.partyId == partyId) emit(state.copyWith(links: links, linksRev: state.linksRev + 1));
    } catch (_) {
      // The payment can still be saved without links.
    }
  }

  void partySelected(Party p) {
    // A foreign party pays in its own currency.
    final c = state.currencies.where((c) => c.code == p.currencyCode).firstOrNull;
    emit(
      state.copyWith(
        partyId: () => p.id,
        links: const [],
        currencyCode: c == null ? null : () => c.code,
        exchangeRate: c == null ? null : numText(c.rate),
      ),
    );
    _reloadLinks();
  }

  /// Switching currency starts the links again: only invoices in that currency can be settled.
  void currencyChanged(String? code) {
    emit(
      state.copyWith(
        currencyCode: () => code,
        exchangeRate: code == null ? '' : numText(state.currencies.where((c) => c.code == code).firstOrNull?.rate),
        links: const [],
      ),
    );
    _reloadLinks();
  }

  void exchangeRateChanged(String v) => emit(state.copyWith(exchangeRate: v));

  // Split payment: further modes after the first.
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

  /// Typing over a picked party unlinks it until a party is picked again.
  void partyTextChanged(String text) {
    if (state.party?.name != text) emit(state.copyWith(partyId: () => null, links: const []));
  }

  void linkAmountChanged(String invoiceId, String text) =>
      emit(state.copyWith(links: [for (final l in state.links) l.invoiceId == invoiceId ? l.withAmount(text) : l]));

  /// Spreads [amount] over the invoices, oldest first, until it runs out.
  void autoLink(num amount) {
    var left = amount;
    emit(
      state.copyWith(
        linksRev: state.linksRev + 1,
        links: [
          for (final l in state.links)
            () {
              final take = left < l.due ? left : l.due;
              left = _r2(left - take);
              return l.withAmount(take > 0 ? numText(_r2(take)) : '');
            }(),
        ],
      ),
    );
  }

  void clearLinks() => emit(state.copyWith(linksRev: state.linksRev + 1, links: [for (final l in state.links) l.withAmount('')]));

  String? _linkProblem(num amount) {
    for (final l in state.links.where((l) => l.amount.trim().isNotEmpty)) {
      final v = parseNum(l.amount);
      if (v == null || v < 0) return 'Invoice ${l.number}: enter a valid amount.';
      if (v > l.due) return 'Invoice ${l.number} only has ${money(l.due)} left to pay.';
    }
    if (state.linkedTotal > amount) return 'The linked amount ${money(state.linkedTotal)} is more than the payment of ${money(amount)}.';
    return null;
  }

  void dateChanged(String v) => emit(state.copyWith(date: v));
  void paymentModeChanged(String v) =>
      emit(state.copyWith(paymentMode: v, bankAccountId: () => bankAccountForMode(v, state.bankAccountId, state.bankAccounts)));
  void bankAccountChanged(String? id) => emit(state.copyWith(bankAccountId: () => id));

  Future<void> save({required String number, required num amount, required String description}) async {
    if (state.submitStatus == SubmitStatus.submitting) return;
    if (state.partyId == null) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: 'Select a party from the list.'));
      return;
    }
    String? accountProblem = bankAccountProblem(state.paymentMode, state.bankAccountId, state.bankAccounts) ?? _linkProblem(amount);
    for (final p in state.extraParts) {
      accountProblem ??= (p.value <= 0
          ? 'Enter the amount of each payment type, or remove the empty one.'
          : bankAccountProblem(p.mode, p.bankAccountId, state.bankAccounts));
    }
    if (accountProblem == null && state.extraPartsTotal >= amount && state.extraParts.isNotEmpty) {
      accountProblem = 'The other payment types add up to the whole amount; remove one or lower them.';
    }
    if (accountProblem == null && state.currencyCode != null && (parseNum(state.exchangeRate) ?? 0) <= 0) {
      accountProblem = 'Enter the exchange rate for ${state.currencyCode}.';
    }
    if (accountProblem != null) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: accountProblem));
      return;
    }
    emit(state.copyWith(submitStatus: SubmitStatus.submitting));
    try {
      final saved = await _payments.save(payment?.id, {
        'type': kind.type,
        'number': number.trim(),
        'partyId': state.partyId,
        'paymentDate': state.date,
        'amount': amount,
        'paymentMode': state.paymentMode,
        'bankAccountId': state.bankAccountId,
        if (state.extraParts.isNotEmpty)
          'parts': [
            {'mode': state.paymentMode, 'bankAccountId': state.bankAccountId, 'amount': _r2(amount - state.extraPartsTotal)},
            for (final p in state.extraParts) {'mode': p.mode, 'bankAccountId': p.bankAccountId, 'amount': p.value},
          ],
        if (state.currencyCode != null) ...{'currencyCode': state.currencyCode, 'exchangeRate': parseNum(state.exchangeRate)},
        if (_invoices != null)
          'allocations': [
            for (final l in state.links.where((l) => l.value > 0)) {'invoiceId': l.invoiceId, 'amount': l.value},
          ],
        'description': description.trim(),
      });
      emit(state.copyWith(submitStatus: SubmitStatus.success, saved: saved));
    } catch (e) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
