/* Second feature batch: payments linked to invoices, split payments, shipping address / due date /
 * currency on invoices, stored files (logo, signature, item images, attachments), expense GST and
 * expense items, books lock date, multiple companies per login with roles, journal entries,
 * currencies and service reminders. */

const { moneyFlowsSql } = require('./1760000000005_more_documents.js');

const account = (alias) => `CASE WHEN ${alias}.payment_mode = 'cash' THEN 'cash' WHEN ${alias}.bank_account_id IS NOT NULL THEN 'bank'
                                 WHEN ${alias}.payment_mode = 'cheque' THEN 'cheque' ELSE 'none' END`;

// An invoice can now be paid in several parts (e.g. part cash, part UPI): one flow per part.
const invoiceBranch = `
    SELECT i.firm_id, i.type AS source, i.id AS source_id,
           CASE i.type WHEN 'sale' THEN 'Sale' WHEN 'purchase' THEN 'Purchase'
                       WHEN 'credit_note' THEN 'Credit Note' ELSE 'Debit Note' END AS label,
           i.party_name AS name, i.number AS ref_number, i.invoice_date AS flow_date, i.created_at, ip.payment_mode,
           CASE WHEN i.type IN ('sale', 'debit_note') THEN ip.amount ELSE -ip.amount END AS amount,
           ${account('ip')} AS account, ip.bank_account_id
      FROM invoice_payments ip JOIN invoices i ON i.id = ip.invoice_id
     WHERE i.deleted_at IS NULL AND i.type IN ('sale', 'purchase', 'credit_note', 'debit_note')`;

const loanFlows = `
    UNION ALL
    SELECT l.firm_id, 'loan', l.id, 'Loan Received', l.name, NULL, l.balance_date, l.created_at,
           CASE WHEN l.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, l.opening_balance,
           CASE WHEN l.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, l.bank_account_id
      FROM loan_accounts l
     WHERE l.deleted_at IS NULL AND l.opening_balance > 0
    UNION ALL
    SELECT t.firm_id, 'loan_txn', t.id, CASE WHEN t.kind = 'payment' THEN 'Loan Payment' ELSE 'Loan Received' END, l.name, NULL,
           t.txn_date, t.created_at, CASE WHEN t.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END,
           CASE WHEN t.kind = 'payment' THEN -(t.principal + t.interest) ELSE t.principal END,
           CASE WHEN t.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, t.bank_account_id
      FROM loan_transactions t JOIN loan_accounts l ON l.id = t.loan_id
     WHERE t.deleted_at IS NULL AND t.kind IN ('payment', 'increase')`;

// Journal lines posted to cash or a bank account: a debit is money in, a credit is money out.
const journalFlows = `
    UNION ALL
    SELECT e.firm_id, 'journal', e.id, 'Journal Entry', coalesce(e.description, ''), e.number, e.entry_date, e.created_at,
           CASE WHEN jl.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, jl.debit - jl.credit,
           CASE WHEN jl.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END, jl.bank_account_id
      FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id
     WHERE e.deleted_at IS NULL AND jl.money_account IS NOT NULL`;

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };
  const money = { type: 'numeric(14,2)', notNull: true, default: 0 };
  const mode = { type: 'text', notNull: true, check: "payment_mode IN ('cash','bank','upi','cheque','card')" };

  // ---- split payments on invoices
  pgm.createTable('invoice_payments', {
    id,
    firm_id: firmRef,
    invoice_id: { type: 'uuid', notNull: true, references: 'invoices', onDelete: 'CASCADE' },
    payment_mode: mode,
    bank_account_id: { type: 'uuid', references: 'bank_accounts' },
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
    sort_order: { type: 'integer', notNull: true, default: 0 },
  });
  pgm.createIndex('invoice_payments', ['invoice_id']);
  pgm.createIndex('invoice_payments', ['bank_account_id']);
  pgm.dropView('money_flows');
  pgm.sql(`INSERT INTO invoice_payments (firm_id, invoice_id, payment_mode, bank_account_id, amount)
           SELECT firm_id, id, payment_mode, bank_account_id, received FROM invoices WHERE received > 0`);
  pgm.dropColumn('invoices', 'bank_account_id');

  // ---- payments linked to specific invoices
  pgm.createTable('payment_allocations', {
    id,
    firm_id: firmRef,
    payment_id: { type: 'uuid', notNull: true, references: 'payments', onDelete: 'CASCADE' },
    invoice_id: { type: 'uuid', notNull: true, references: 'invoices', onDelete: 'CASCADE' },
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
  });
  pgm.addConstraint('payment_allocations', 'payment_allocations_unique', { unique: ['payment_id', 'invoice_id'] });
  pgm.createIndex('payment_allocations', ['invoice_id']);

  // ---- more on invoices
  pgm.addColumns('invoices', {
    shipping_address: { type: 'text' },
    due_date: { type: 'date' },
    // Display currency for the printed document; the books always stay in the base currency.
    currency_code: { type: 'varchar(3)' },
    exchange_rate: { type: 'numeric(14,6)' },
    created_by: { type: 'uuid', references: 'users', onDelete: 'SET NULL' },
  });
  pgm.addColumn('payments', { created_by: { type: 'uuid', references: 'users', onDelete: 'SET NULL' } });

  // ---- stored files
  pgm.createTable('files', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    mime_type: { type: 'text', notNull: true },
    size: { type: 'integer', notNull: true },
    data: { type: 'bytea', notNull: true },
    created_at: now,
  });
  pgm.addColumns('firms', {
    logo_file_id: { type: 'uuid', references: 'files', onDelete: 'SET NULL' },
    signature_file_id: { type: 'uuid', references: 'files', onDelete: 'SET NULL' },
    // No transaction dated on or before this day can be added, changed or deleted.
    books_lock_date: { type: 'date' },
  });
  pgm.addColumns('items', {
    image_file_id: { type: 'uuid', references: 'files', onDelete: 'SET NULL' },
    // Services only: remind the customer this many days after each sale.
    service_reminder_days: { type: 'integer' },
  });
  pgm.createTable('attachments', {
    id,
    firm_id: firmRef,
    owner_type: { type: 'text', notNull: true, check: "owner_type IN ('invoice','expense','payment')" },
    owner_id: { type: 'uuid', notNull: true },
    file_id: { type: 'uuid', notNull: true, references: 'files', onDelete: 'CASCADE' },
    created_at: now,
  });
  pgm.createIndex('attachments', ['owner_type', 'owner_id']);

  // ---- expense GST and reusable expense items
  pgm.addColumns('expenses', {
    prices_include_tax: { type: 'boolean', notNull: true, default: false },
    taxable_amount: money,
    tax_amount: money,
  });
  pgm.sql('UPDATE expenses SET taxable_amount = subtotal');
  pgm.addColumns('expense_items', {
    gst_rate: { type: 'numeric(5,2)', notNull: true, default: 0 },
    taxable_value: money,
    tax: money,
  });
  pgm.sql('UPDATE expense_items SET taxable_value = amount');
  pgm.createTable('expense_item_defs', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    price: money,
    hsn_code: { type: 'varchar(8)' },
    gst_rate: { type: 'numeric(5,2)' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('expense_item_defs', ['firm_id', 'lower(name)'], { unique: true, where: 'deleted_at IS NULL', name: 'expense_item_defs_name_unique' });

  // ---- several companies per login, several users per company
  pgm.createTable('firm_members', {
    firm_id: firmRef,
    user_id: { type: 'uuid', notNull: true, references: 'users', onDelete: 'CASCADE' },
    role: { type: 'text', notNull: true, check: "role IN ('owner','admin','accountant','salesman')" },
    created_at: now,
  });
  pgm.addConstraint('firm_members', 'firm_members_pk', { primaryKey: ['firm_id', 'user_id'] });
  pgm.sql("INSERT INTO firm_members (firm_id, user_id, role) SELECT firm_id, id, 'owner' FROM users");

  // ---- accounting: own ledger accounts and journal entries
  pgm.createTable('ledger_accounts', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    type: { type: 'text', notNull: true, check: "type IN ('asset','liability','income','expense','equity')" },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('ledger_accounts', ['firm_id', 'lower(name)'], { unique: true, where: 'deleted_at IS NULL', name: 'ledger_accounts_name_unique' });
  pgm.createTable('journal_entries', {
    id,
    firm_id: firmRef,
    number: { type: 'text', notNull: true },
    entry_date: { type: 'date', notNull: true },
    description: { type: 'text' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createTable('journal_lines', {
    id,
    firm_id: firmRef,
    entry_id: { type: 'uuid', notNull: true, references: 'journal_entries', onDelete: 'CASCADE' },
    // Exactly one of: an own ledger account, or cash / a bank account.
    ledger_account_id: { type: 'uuid', references: 'ledger_accounts' },
    money_account: { type: 'text', check: "money_account IN ('cash','bank')" },
    bank_account_id: { type: 'uuid', references: 'bank_accounts' },
    debit: money,
    credit: money,
    sort_order: { type: 'integer', notNull: true, default: 0 },
  });
  pgm.addConstraint('journal_lines', 'journal_lines_account_check', {
    check: `(ledger_account_id IS NOT NULL AND money_account IS NULL AND bank_account_id IS NULL)
         OR (ledger_account_id IS NULL AND money_account = 'cash' AND bank_account_id IS NULL)
         OR (ledger_account_id IS NULL AND money_account = 'bank' AND bank_account_id IS NOT NULL)`,
  });
  pgm.addConstraint('journal_lines', 'journal_lines_side_check', {
    check: '(debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)',
  });
  pgm.createIndex('journal_lines', ['entry_id']);

  // ---- currencies for printing documents in another currency
  pgm.createTable('currencies', {
    id,
    firm_id: firmRef,
    code: { type: 'varchar(3)', notNull: true },
    symbol: { type: 'text', notNull: true },
    // How many units of the base currency one unit of this currency is worth.
    rate: { type: 'numeric(14,6)', notNull: true, check: 'rate > 0' },
    updated_at: now,
  });
  pgm.addConstraint('currencies', 'currencies_code_unique', { unique: ['firm_id', 'code'] });

  // ---- service reminders marked as done (the reminders themselves are derived from sales)
  pgm.createTable('service_reminders_done', {
    invoice_item_id: { type: 'uuid', primaryKey: true, references: 'invoice_items', onDelete: 'CASCADE' },
    firm_id: firmRef,
    done_at: now,
  });

  pgm.createView('money_flows', {}, moneyFlowsSql(invoiceBranch) + loanFlows + journalFlows);
};

exports.down = () => {
  throw new Error('This migration restructures payments and is not reversible; restore from a backup instead.');
};
