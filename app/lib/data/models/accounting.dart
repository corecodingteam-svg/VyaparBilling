import 'package:equatable/equatable.dart';

const ledgerTypes = {'asset': 'Asset', 'liability': 'Liability', 'income': 'Income', 'expense': 'Expense', 'equity': 'Equity / Capital'};

/// An account of the business's own, used in journal entries.
class LedgerAccount extends Equatable {
  LedgerAccount.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        type = j['type'] as String,
        balance = (j['balance'] as num?) ?? 0;

  final String id;
  final String name;
  final String type;

  /// Debits − credits: positive is a debit balance.
  final num balance;

  @override
  List<Object?> get props => [id, name, type, balance];
}

class JournalLine extends Equatable {
  JournalLine.fromJson(Map<String, dynamic> j)
      : ledgerAccountId = j['ledgerAccountId'] as String?,
        moneyAccount = j['moneyAccount'] as String?,
        bankAccountId = j['bankAccountId'] as String?,
        accountName = (j['accountName'] as String?) ?? '',
        debit = (j['debit'] as num?) ?? 0,
        credit = (j['credit'] as num?) ?? 0;

  final String? ledgerAccountId;

  /// 'cash' or 'bank' when the line is on cash-in-hand or a bank account instead of a ledger account.
  final String? moneyAccount;
  final String? bankAccountId;
  final String accountName;
  final num debit;
  final num credit;

  @override
  List<Object?> get props => [ledgerAccountId, moneyAccount, bankAccountId, accountName, debit, credit];
}

class JournalEntry extends Equatable {
  JournalEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        number = j['number'] as String,
        date = j['date'] as String,
        description = j['description'] as String?,
        amount = (j['amount'] as num?) ?? 0,
        lines = [for (final l in (j['lines'] as List?) ?? const []) JournalLine.fromJson(l as Map<String, dynamic>)];

  final String id;
  final String number;
  final String date;
  final String? description;

  /// Total of the debit side (equal to the credit side).
  final num amount;
  final List<JournalLine> lines;

  @override
  List<Object?> get props => [id, number, date, description, amount, lines];
}

/// A foreign currency documents can be printed in.
class Currency extends Equatable {
  Currency.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        code = j['code'] as String,
        symbol = j['symbol'] as String,
        rate = j['rate'] as num;

  final String id;
  final String code;
  final String symbol;

  /// Value of one unit in the business's own currency.
  final num rate;

  @override
  List<Object?> get props => [id, code, symbol, rate];
}
