/* Loan accounts: money borrowed (received into cash or a bank), repayments split into principal
 * and interest, further borrowing and charges. Their cash/bank legs join the money_flows view. */

const { moneyFlowsSql, invoiceBranch } = require('./1760000000005_more_documents.js');

const loanFlows = `
    UNION ALL
    -- the loan amount received when the account was opened
    SELECT l.firm_id, 'loan', l.id, 'Loan Received', l.name, NULL, l.balance_date, l.created_at,
           CASE WHEN l.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, l.opening_balance,
           CASE WHEN l.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, l.bank_account_id
      FROM loan_accounts l
     WHERE l.deleted_at IS NULL AND l.opening_balance > 0
    UNION ALL
    -- repayments (principal + interest) go out; further borrowing comes in; charges move no money
    SELECT t.firm_id, 'loan_txn', t.id, CASE WHEN t.kind = 'payment' THEN 'Loan Payment' ELSE 'Loan Received' END, l.name, NULL,
           t.txn_date, t.created_at, CASE WHEN t.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END,
           CASE WHEN t.kind = 'payment' THEN -(t.principal + t.interest) ELSE t.principal END,
           CASE WHEN t.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, t.bank_account_id
      FROM loan_transactions t JOIN loan_accounts l ON l.id = t.loan_id
     WHERE t.deleted_at IS NULL AND t.kind IN ('payment', 'increase')`;

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('loan_accounts', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    lender: { type: 'text' },
    account_number: { type: 'text' },
    opening_balance: { type: 'numeric(14,2)', notNull: true, default: 0, check: 'opening_balance >= 0' },
    balance_date: { type: 'date', notNull: true, default: pgm.func('CURRENT_DATE') },
    bank_account_id: { type: 'uuid', references: 'bank_accounts' }, // where the loan was received; null = cash
    interest_rate: { type: 'numeric(5,2)' },
    term_months: { type: 'integer' },
    description: { type: 'text' },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('loan_accounts', ['firm_id', 'lower(name)'], { unique: true, where: 'deleted_at IS NULL', name: 'loan_accounts_firm_name_unique' });

  pgm.createTable('loan_transactions', {
    id,
    firm_id: firmRef,
    loan_id: { type: 'uuid', notNull: true, references: 'loan_accounts', onDelete: 'CASCADE' },
    kind: { type: 'text', notNull: true, check: "kind IN ('payment','increase','charge')" },
    principal: { type: 'numeric(14,2)', notNull: true, check: 'principal >= 0' },
    interest: { type: 'numeric(14,2)', notNull: true, default: 0, check: 'interest >= 0' },
    txn_date: { type: 'date', notNull: true },
    bank_account_id: { type: 'uuid', references: 'bank_accounts' }, // paid from / received into; null = cash
    description: { type: 'text' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('loan_transactions', ['loan_id', 'txn_date']);

  pgm.dropView('money_flows');
  pgm.createView('money_flows', {}, moneyFlowsSql(invoiceBranch) + loanFlows);
};

exports.down = (pgm) => {
  pgm.dropView('money_flows');
  pgm.createView('money_flows', {}, moneyFlowsSql(invoiceBranch));
  pgm.dropTable('loan_transactions');
  pgm.dropTable('loan_accounts');
};
