import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/models/payment.dart';
import '../../../data/repositories/cash_bank_repository.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../data/repositories/parties_repository.dart';
import '../../../data/repositories/payments_repository.dart';
import '../../../shared/format.dart';

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

  /// The party's unpaid invoices (sales for Payment-In, purchases for Payment-Out).
  final List<LinkRow> links;

  /// Bumped when the link amounts are filled in for the user, so their inputs show the new text.
  final int linksRev;
  final SubmitStatus submitStatus;
  final Payment? saved;
  final String? error;

  Party? get party => parties.where((p) => p.id == partyId).firstOrNull;
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
    List<LinkRow>? links,
    int? linksRev,
    SubmitStatus? submitStatus,
    Payment? saved,
    String? error,
  }) =>
      PaymentFormState(
        loadStatus: loadStatus ?? this.loadStatus,
        parties: parties ?? this.parties,
        bankAccounts: bankAccounts ?? this.bankAccounts,
        bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
        partyId: partyId != null ? partyId() : this.partyId,
        number: number ?? this.number,
        date: date ?? this.date,
        paymentMode: paymentMode ?? this.paymentMode,
        links: links ?? this.links,
        linksRev: linksRev ?? this.linksRev,
        submitStatus: submitStatus ?? this.submitStatus,
        saved: saved ?? this.saved,
        error: error,
      );

  @override
  List<Object?> get props => [loadStatus, parties, bankAccounts, bankAccountId, partyId, number, date, paymentMode, links, linksRev, submitStatus, saved, error];
}

class PaymentFormCubit extends Cubit<PaymentFormState> {
  PaymentFormCubit(this._payments, this._parties, this._accounts, this.kind, {this.payment, String? partyId, InvoicesRepository? invoices})
      : super(PaymentFormState(
          partyId: payment?.partyId ?? partyId,
          bankAccountId: payment?.bankAccountId,
          number: payment?.number ?? '',
          date: payment?.paymentDate ?? isoDate(DateTime.now()),
          paymentMode: payment?.paymentMode ?? 'cash',
        )) {
    _invoices = invoices;
  }

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
      final links = await _loadLinks(state.partyId);
      emit(state.copyWith(loadStatus: LoadStatus.success, parties: parties, bankAccounts: bankAccounts, number: number, links: links, linksRev: state.linksRev + 1));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  /// The party's unpaid invoices. When editing, the invoices this payment already settles are
  /// included with their link amounts, and what they owe is shown as if this payment were not there.
  Future<List<LinkRow>> _loadLinks(String? partyId) async {
    final invoices = _invoices;
    if (invoices == null || partyId == null) return const [];
    final unpaid = await invoices.unpaid(kind.type == 'in' ? 'sale' : 'purchase', partyId);
    final own = editing && partyId == payment!.partyId ? (await _payments.get(payment!.id)).allocations : const <PaymentAllocation>[];
    final rows = <LinkRow>[
      for (final a in own.where((a) => unpaid.every((i) => i.id != a.invoiceId)))
        LinkRow(invoiceId: a.invoiceId, number: a.number, date: a.invoiceDate ?? '', total: a.total, due: a.amount, amount: numText(a.amount)),
      for (final InvoiceSummary i in unpaid)
        () {
          final mine = own.where((a) => a.invoiceId == i.id).firstOrNull?.amount ?? 0;
          return LinkRow(invoiceId: i.id, number: i.number, date: i.invoiceDate, total: i.total, due: _r2(i.balance + mine), amount: mine == 0 ? '' : numText(mine));
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
    emit(state.copyWith(partyId: () => p.id, links: const []));
    _reloadLinks();
  }

  /// Typing over a picked party unlinks it until a party is picked again.
  void partyTextChanged(String text) {
    if (state.party?.name != text) emit(state.copyWith(partyId: () => null, links: const []));
  }

  void linkAmountChanged(String invoiceId, String text) =>
      emit(state.copyWith(links: [for (final l in state.links) l.invoiceId == invoiceId ? l.withAmount(text) : l]));

  /// Spreads [amount] over the invoices, oldest first, until it runs out.
  void autoLink(num amount) {
    var left = amount;
    emit(state.copyWith(
      linksRev: state.linksRev + 1,
      links: [
        for (final l in state.links)
          () {
            final take = left < l.due ? left : l.due;
            left = _r2(left - take);
            return l.withAmount(take > 0 ? numText(_r2(take)) : '');
          }(),
      ],
    ));
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
    final accountProblem = bankAccountProblem(state.paymentMode, state.bankAccountId, state.bankAccounts) ?? _linkProblem(amount);
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
