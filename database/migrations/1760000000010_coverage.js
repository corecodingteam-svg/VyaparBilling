/* Third feature batch: split payments on expenses and Payment-In/Out, salesman party assignment and
 * location, godowns, batch / serial / MRP, cess, bill-level discount and additional charges,
 * TCS / TDS, loyalty points, party groups, foreign-currency books and scheduled backups. */

const account = (alias) => `CASE WHEN ${alias}.payment_mode = 'cash' THEN 'cash' WHEN ${alias}.bank_account_id IS NOT NULL THEN 'bank'
                                 WHEN ${alias}.payment_mode = 'cheque' THEN 'cheque' ELSE 'none' END`;
const cashOrBank = (alias) => `CASE WHEN ${alias}.bank_account_id IS NULL THEN 'cash' ELSE 'bank' END`;

// Every movement of money. Invoices, payments and expenses can each be paid in several parts
// (e.g. part cash, part UPI): one row per part.
const moneyFlows = `
    SELECT i.firm_id, i.type AS source, i.id AS source_id,
           CASE i.type WHEN 'sale' THEN 'Sale' WHEN 'purchase' THEN 'Purchase'
                       WHEN 'credit_note' THEN 'Credit Note' ELSE 'Debit Note' END AS label,
           i.party_name AS name, i.number AS ref_number, i.invoice_date AS flow_date, i.created_at, ip.payment_mode,
           CASE WHEN i.type IN ('sale', 'debit_note') THEN ip.amount ELSE -ip.amount END AS amount,
           ${account('ip')} AS account, ip.bank_account_id
      FROM invoice_payments ip JOIN invoices i ON i.id = ip.invoice_id
     WHERE i.deleted_at IS NULL AND i.type IN ('sale', 'purchase', 'credit_note', 'debit_note')
    UNION ALL
    SELECT p.firm_id, 'payment_' || p.type, p.id, CASE WHEN p.type = 'in' THEN 'Payment-In' ELSE 'Payment-Out' END, pa.name, p.number,
           p.payment_date, p.created_at, pp.payment_mode,
           CASE WHEN p.type = 'in' THEN pp.amount ELSE -pp.amount END,
           ${account('pp')}, pp.bank_account_id
      FROM payment_parts pp JOIN payments p ON p.id = pp.payment_id JOIN parties pa ON pa.id = p.party_id
     WHERE p.deleted_at IS NULL
    UNION ALL
    SELECT e.firm_id, 'expense', e.id, 'Expense', c.name, e.number,
           e.expense_date, e.created_at, ep.payment_mode, -ep.amount,
           ${account('ep')}, ep.bank_account_id
      FROM expense_payments ep JOIN expenses e ON e.id = ep.expense_id JOIN expense_categories c ON c.id = e.category_id
     WHERE e.deleted_at IS NULL
    UNION ALL
    SELECT a.firm_id, 'adjustment', a.id,
           CASE a.kind WHEN 'cash_add' THEN 'Add Cash' WHEN 'cash_reduce' THEN 'Reduce Cash'
                       WHEN 'bank_to_cash' THEN 'Cash Withdraw' ELSE 'Cash Deposit' END,
           coalesce(b.name, a.description, ''), NULL, a.adjustment_date, a.created_at, 'cash',
           CASE WHEN a.kind IN ('cash_add', 'bank_to_cash') THEN a.amount ELSE -a.amount END,
           'cash', NULL
      FROM fund_adjustments a LEFT JOIN bank_accounts b ON b.id = a.bank_account_id
     WHERE a.deleted_at IS NULL AND a.kind IN ('cash_add', 'cash_reduce', 'bank_to_cash', 'cash_to_bank')
    UNION ALL
    SELECT a.firm_id, 'adjustment', a.id,
           CASE a.kind WHEN 'bank_add' THEN 'Increase Balance' WHEN 'bank_reduce' THEN 'Reduce Balance'
                       WHEN 'bank_to_cash' THEN 'Cash Withdraw' WHEN 'cash_to_bank' THEN 'Cash Deposit' ELSE 'Transfer Out' END,
           CASE WHEN a.kind = 'bank_to_bank' THEN 'To ' || tb.name ELSE coalesce(a.description, '') END,
           NULL, a.adjustment_date, a.created_at, 'bank',
           CASE WHEN a.kind IN ('bank_add', 'cash_to_bank') THEN a.amount ELSE -a.amount END,
           'bank', a.bank_account_id
      FROM fund_adjustments a LEFT JOIN bank_accounts tb ON tb.id = a.to_bank_account_id
     WHERE a.deleted_at IS NULL AND a.bank_account_id IS NOT NULL
    UNION ALL
    SELECT a.firm_id, 'adjustment', a.id, 'Transfer In', 'From ' || fb.name, NULL, a.adjustment_date, a.created_at, 'bank',
           a.amount, 'bank', a.to_bank_account_id
      FROM fund_adjustments a JOIN bank_accounts fb ON fb.id = a.bank_account_id
     WHERE a.deleted_at IS NULL AND a.kind = 'bank_to_bank'
    UNION ALL
    SELECT l.firm_id, 'loan', l.id, 'Loan Received', l.name, NULL, l.balance_date, l.created_at,
           ${cashOrBank('l')}, l.opening_balance, ${cashOrBank('l')}, l.bank_account_id
      FROM loan_accounts l
     WHERE l.deleted_at IS NULL AND l.opening_balance > 0
    UNION ALL
    SELECT t.firm_id, 'loan_txn', t.id, CASE WHEN t.kind = 'payment' THEN 'Loan Payment' ELSE 'Loan Received' END, l.name, NULL,
           t.txn_date, t.created_at, ${cashOrBank('t')},
           CASE WHEN t.kind = 'payment' THEN -(t.principal + t.interest) ELSE t.principal END,
           ${cashOrBank('t')}, t.bank_account_id
      FROM loan_transactions t JOIN loan_accounts l ON l.id = t.loan_id
     WHERE t.deleted_at IS NULL AND t.kind IN ('payment', 'increase')
    UNION ALL
    SELECT e.firm_id, 'journal', e.id, 'Journal Entry', coalesce(e.description, ''), e.number, e.entry_date, e.created_at,
           ${cashOrBank('jl')}, jl.debit - jl.credit, ${cashOrBank('jl')}, jl.bank_account_id
      FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id
     WHERE e.deleted_at IS NULL AND jl.money_account IS NOT NULL`;

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };
  const money = { type: 'numeric(14,2)', notNull: true, default: 0 };
  const fx = { type: 'numeric(14,2)' };
  const mode = { type: 'text', notNull: true, check: "payment_mode IN ('cash','bank','upi','cheque','card')" };
  const part = (owner, table) => ({
    id,
    firm_id: firmRef,
    [owner]: { type: 'uuid', notNull: true, references: table, onDelete: 'CASCADE' },
    payment_mode: mode,
    bank_account_id: { type: 'uuid', references: 'bank_accounts' },
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
    sort_order: { type: 'integer', notNull: true, default: 0 },
  });

  pgm.dropView('money_flows');

  // ---- split payments on Payment-In/Out and expenses (their own columns keep the first part, for lists)
  pgm.createTable('payment_parts', part('payment_id', 'payments'));
  pgm.createIndex('payment_parts', ['payment_id']);
  pgm.sql(`INSERT INTO payment_parts (firm_id, payment_id, payment_mode, bank_account_id, amount)
           SELECT firm_id, id, payment_mode, bank_account_id, amount FROM payments WHERE amount > 0`);
  pgm.createTable('expense_payments', part('expense_id', 'expenses'));
  pgm.createIndex('expense_payments', ['expense_id']);
  pgm.sql(`INSERT INTO expense_payments (firm_id, expense_id, payment_mode, bank_account_id, amount)
           SELECT firm_id, id, payment_mode, bank_account_id, total FROM expenses WHERE total > 0`);

  // ---- party groups, the salesman a party belongs to, the currency a foreign party is billed in
  pgm.createTable('party_groups', { id, firm_id: firmRef, name: { type: 'text', notNull: true }, created_at: now });
  pgm.createIndex('party_groups', ['firm_id', 'lower(name)'], { unique: true, name: 'party_groups_name_unique' });
  pgm.addColumns('parties', {
    group_id: { type: 'uuid', references: 'party_groups', onDelete: 'SET NULL' },
    assigned_user_id: { type: 'uuid', references: 'users', onDelete: 'SET NULL' },
    currency_code: { type: 'varchar(3)' },
    loyalty_opening: { type: 'integer', notNull: true, default: 0 },
  });

  // ---- where salesmen are
  pgm.createTable('user_locations', {
    id,
    firm_id: firmRef,
    user_id: { type: 'uuid', notNull: true, references: 'users', onDelete: 'CASCADE' },
    latitude: { type: 'double precision', notNull: true },
    longitude: { type: 'double precision', notNull: true },
    accuracy: { type: 'double precision' },
    // What they were doing: a regular check-in, or saving a sale / payment.
    context: { type: 'text', notNull: true, default: 'ping', check: "context IN ('ping','sale','payment')" },
    ref_id: { type: 'uuid' },
    recorded_at: now,
  });
  pgm.createIndex('user_locations', ['firm_id', 'user_id', 'recorded_at']);

  // ---- godowns (stores). A null godown anywhere means the main store.
  pgm.createTable('godowns', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    address: { type: 'text' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('godowns', ['firm_id', 'lower(name)'], { unique: true, where: 'deleted_at IS NULL', name: 'godowns_name_unique' });
  pgm.addColumns('stock_movements', {
    godown_id: { type: 'uuid', references: 'godowns' },
    batch_no: { type: 'text' },
    expiry_date: { type: 'date' },
  });
  pgm.createIndex('stock_movements', ['item_id', 'godown_id']);
  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', {
    check: "type IN ('opening','add','reduce','sale','purchase','credit_note','debit_note','transfer')",
  });

  // ---- more on documents
  pgm.addColumns('invoices', {
    godown_id: { type: 'uuid', references: 'godowns' },
    // Bill-level discount, spread over the lines before tax (discount_amount is what it came to).
    discount_pct: { type: 'numeric(7,4)', notNull: true, default: 0 },
    discount_amount: money,
    // Freight, packing, ...: [{ name, amount }], added after tax.
    charges: { type: 'jsonb', notNull: true, default: '[]' },
    charges_total: money,
    cess: money,
    // TCS is collected on top of the bill; TDS is held back by the payer and so reduces what is still to pay.
    tcs_rate: { type: 'numeric(6,3)', notNull: true, default: 0 },
    tcs_amount: money,
    tds_rate: { type: 'numeric(6,3)', notNull: true, default: 0 },
    tds_amount: money,
    loyalty_earned: { type: 'integer', notNull: true, default: 0 },
    loyalty_redeemed: { type: 'integer', notNull: true, default: 0 },
    loyalty_amount: money,
    // Foreign-currency documents: the same figures in that currency (the books stay in the base currency).
    fx_total: fx,
    fx_received: fx,
  });
  pgm.addColumns('invoice_items', {
    bill_discount: money,
    cess_rate: { type: 'numeric(5,2)', notNull: true, default: 0 },
    cess: money,
    batch_no: { type: 'text' },
    mfg_date: { type: 'date' },
    expiry_date: { type: 'date' },
    mrp: { type: 'numeric(14,2)' },
    // Comma-separated serial numbers / IMEIs, one per unit.
    serial_nos: { type: 'text' },
    fx_price: fx,
    fx_amount: fx,
  });
  pgm.addColumn('invoice_payments', { fx_amount: fx });
  pgm.addColumns('items', {
    cess_rate: { type: 'numeric(5,2)' },
    mrp: { type: 'numeric(14,2)' },
  });

  // ---- payments in a foreign currency
  pgm.addColumns('payments', {
    currency_code: { type: 'varchar(3)' },
    exchange_rate: { type: 'numeric(14,6)' },
    fx_amount: fx,
    // Gain (+) or loss (−) from settling invoices at a different rate than they were booked at.
    fx_gain: money,
  });
  pgm.addColumn('payment_allocations', { fx_amount: fx });

  // ---- backups made on a schedule, and where they are copied to
  pgm.createTable('backups', {
    id,
    firm_id: firmRef,
    file_name: { type: 'text', notNull: true },
    size: { type: 'integer', notNull: true },
    kind: { type: 'text', notNull: true, check: "kind IN ('auto','manual')" },
    drive_file_id: { type: 'text' },
    drive_error: { type: 'text' },
    created_at: now,
  });
  pgm.createIndex('backups', ['firm_id', 'created_at']);
  pgm.addColumns('firms', {
    drive_refresh_token: { type: 'text' },
    drive_email: { type: 'text' },
  });

  pgm.createView('money_flows', {}, moneyFlows);
};

exports.down = () => {
  throw new Error('This migration restructures payments and is not reversible; restore from a backup instead.');
};
