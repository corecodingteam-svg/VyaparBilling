import 'package:equatable/equatable.dart';

/// Bank, UPI and card money lands in a bank account; cash goes to cash-in-hand and a cheque
/// only reaches a bank once it is deposited.
bool modeUsesBank(String paymentMode) => const {'bank', 'upi', 'card'}.contains(paymentMode);

class BankAccount extends Equatable {
  BankAccount.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        openingBalance = j['openingBalance'] as num,
        openingDate = j['openingDate'] as String,
        accountNumber = j['accountNumber'] as String?,
        ifsc = j['ifsc'] as String?,
        bankName = j['bankName'] as String?,
        holderName = j['holderName'] as String?,
        upiId = j['upiId'] as String?,
        balance = j['balance'] as num;

  final String id;
  final String name;
  final num openingBalance;
  final String openingDate;
  final String? accountNumber;
  final String? ifsc;
  final String? bankName;
  final String? holderName;
  final String? upiId;
  final num balance;

  bool get hasDetails => [accountNumber, ifsc, bankName, holderName, upiId].any((v) => (v ?? '').isNotEmpty);

  @override
  List<Object?> get props => [id, name, openingBalance, openingDate, accountNumber, ifsc, bankName, holderName, upiId, balance];
}

/// One movement of money in a cash/bank/cheque list.
class MoneyTxn extends Equatable {
  MoneyTxn.fromJson(Map<String, dynamic> j)
      : source = j['source'] as String,
        id = j['id'] as String,
        type = j['type'] as String,
        name = j['name'] as String,
        number = j['number'] as String?,
        date = j['date'] as String,
        amount = j['amount'] as num,
        paymentMode = j['paymentMode'] as String,
        bankAccountId = j['bankAccountId'] as String?,
        status = j['status'] as String?;

  /// sale | purchase | payment_in | payment_out | expense | adjustment | opening
  final String source;
  final String id;
  final String type;
  final String name;
  final String? number;
  final String date;

  /// Signed: positive = money in, negative = money out.
  final num amount;
  final String paymentMode;
  final String? bankAccountId;

  /// Cheques only: 'open' until deposited, then 'closed'.
  final String? status;

  bool get isOpenCheque => status == 'open';

  @override
  List<Object?> get props => [source, id, type, name, number, date, amount, paymentMode, bankAccountId, status];
}

/// Kinds of manual fund movement and how they read in the UI.
const adjustmentKinds = {
  'cash_add': 'Add Cash',
  'cash_reduce': 'Reduce Cash',
  'bank_to_cash': 'Bank to Cash Transfer',
  'cash_to_bank': 'Cash to Bank Transfer',
  'bank_to_bank': 'Bank to Bank Transfer',
  'bank_add': 'Increase Bank Balance',
  'bank_reduce': 'Reduce Bank Balance',
};

/// The bank account to keep after the payment type changes: none for cash/cheque, the current
/// one if still valid, or the only account when there is exactly one.
String? bankAccountForMode(String paymentMode, String? current, List<BankAccount> accounts) {
  if (!modeUsesBank(paymentMode)) return null;
  if (accounts.any((a) => a.id == current)) return current;
  return accounts.length == 1 ? accounts.single.id : null;
}

/// Validation message when bank/UPI/card money has no account chosen (only once accounts exist).
String? bankAccountProblem(String paymentMode, String? bankAccountId, List<BankAccount> accounts) =>
    modeUsesBank(paymentMode) && accounts.isNotEmpty && bankAccountId == null ? 'Select the bank account.' : null;
