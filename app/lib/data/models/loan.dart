import 'package:equatable/equatable.dart';

class LoanAccount extends Equatable {
  LoanAccount.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        lender = j['lender'] as String?,
        accountNumber = j['accountNumber'] as String?,
        openingBalance = j['openingBalance'] as num,
        balanceDate = j['balanceDate'] as String,
        bankAccountId = j['bankAccountId'] as String?,
        interestRate = j['interestRate'] as num?,
        termMonths = j['termMonths'] as int?,
        description = j['description'] as String?,
        balance = j['balance'] as num;

  final String id;
  final String name;
  final String? lender;
  final String? accountNumber;
  final num openingBalance;
  final String balanceDate;

  /// Where the loan was received; null = cash.
  final String? bankAccountId;
  final num? interestRate;
  final int? termMonths;
  final String? description;

  /// Outstanding loan amount.
  final num balance;

  @override
  List<Object?> get props =>
      [id, name, lender, accountNumber, openingBalance, balanceDate, bankAccountId, interestRate, termMonths, description, balance];
}

class LoanTxn extends Equatable {
  LoanTxn.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String?,
        kind = j['kind'] as String,
        type = j['type'] as String,
        date = j['date'] as String,
        principal = j['principal'] as num,
        interest = j['interest'] as num,
        total = j['total'] as num,
        balance = j['balance'] as num,
        bankAccountId = j['bankAccountId'] as String?,
        description = j['description'] as String?;

  /// Paid from / received into this bank account; null = cash.
  final String? bankAccountId;

  /// Null for the opening-loan row.
  final String? id;

  /// opening | payment | increase | charge
  final String kind;
  final String type;
  final String date;
  final num principal;
  final num interest;
  final num total;

  /// Loan outstanding after this entry.
  final num balance;
  final String? description;

  @override
  List<Object?> get props => [id, kind, type, date, principal, interest, total, balance, bankAccountId, description];
}

const loanTxnKinds = {'payment': 'Make Payment', 'increase': 'Take More Loan', 'charge': 'Charges On Loan'};
