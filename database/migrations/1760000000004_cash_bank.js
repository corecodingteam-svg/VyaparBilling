/* Cash & bank: bank accounts, fund adjustments/transfers, and the account a transaction's money
 * moved through. Balances are never stored — the money_flows view lists every movement of money,
 * and balances are sums over it. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('bank_accounts', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    opening_balance: { type: 'numeric(14,2)', notNull: true, default: 0 },
    opening_date: { type: 'date', notNull: true, default: pgm.func('CURRENT_DATE') },
    account_number: { type: 'text' },
    ifsc: { type: 'text' },
    bank_name: { type: 'text' },
    holder_name: { type: 'text' },
    upi_id: { type: 'text' },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('bank_accounts', ['firm_id', 'lower(name)'], {
    unique: true,
    where: 'deleted_at IS NULL',
    name: 'bank_accounts_firm_name_unique',
  });

  // Bank/UPI/card money (and deposited cheques) land in a bank account; cash never has one.
  for (const table of ['invoices', 'payments', 'expenses']) {
    pgm.addColumn(table, { bank_account_id: { type: 'uuid', references: 'bank_accounts' } });
    pgm.createIndex(table, ['bank_account_id']);
  }

  pgm.createTable('fund_adjustments', {
    id,
    firm_id: firmRef,
    kind: {
      type: 'text',
      notNull: true,
      check: "kind IN ('cash_add','cash_reduce','bank_add','bank_reduce','bank_to_cash','cash_to_bank','bank_to_bank')",
    },
    bank_account_id: { type: 'uuid', references: 'bank_accounts' }, // the bank involved (source for transfers out)
    to_bank_account_id: { type: 'uuid', references: 'bank_accounts' }, // bank_to_bank destination
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
    adjustment_date: { type: 'date', notNull: true },
    description: { type: 'text' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.addConstraint('fund_adjustments', 'fund_adjustments_accounts_check', {
    check: `(kind IN ('cash_add','cash_reduce') AND bank_account_id IS NULL AND to_bank_account_id IS NULL)
         OR (kind IN ('bank_add','bank_reduce','bank_to_cash','cash_to_bank') AND bank_account_id IS NOT NULL AND to_bank_account_id IS NULL)
         OR (kind = 'bank_to_bank' AND bank_account_id IS NOT NULL AND to_bank_account_id IS NOT NULL AND bank_account_id <> to_bank_account_id)`,
  });

  // One row per movement of money. account: 'cash' | 'bank' | 'cheque' (not yet deposited) | 'none'
  // (bank/UPI/card money with no account chosen). amount is signed: + money in, − money out.
  const account = `CASE WHEN payment_mode = 'cash' THEN 'cash' WHEN bank_account_id IS NOT NULL THEN 'bank'
                        WHEN payment_mode = 'cheque' THEN 'cheque' ELSE 'none' END`;
  pgm.createView('money_flows', {}, `
    SELECT i.firm_id, i.type AS source, i.id AS source_id, initcap(i.type) AS label, i.party_name AS name, i.number AS ref_number,
           i.invoice_date AS flow_date, i.created_at, i.payment_mode,
           CASE WHEN i.type = 'sale' THEN i.received ELSE -i.received END AS amount,
           ${account} AS account, i.bank_account_id
      FROM invoices i
     WHERE i.deleted_at IS NULL AND i.type IN ('sale', 'purchase') AND i.received > 0
    UNION ALL
    SELECT p.firm_id, 'payment_' || p.type, p.id, CASE WHEN p.type = 'in' THEN 'Payment-In' ELSE 'Payment-Out' END, pa.name, p.number,
           p.payment_date, p.created_at, p.payment_mode,
           CASE WHEN p.type = 'in' THEN p.amount ELSE -p.amount END,
           ${account}, p.bank_account_id
      FROM payments p JOIN parties pa ON pa.id = p.party_id
     WHERE p.deleted_at IS NULL
    UNION ALL
    SELECT e.firm_id, 'expense', e.id, 'Expense', c.name, e.number,
           e.expense_date, e.created_at, e.payment_mode, -e.total,
           ${account}, e.bank_account_id
      FROM expenses e JOIN expense_categories c ON c.id = e.category_id
     WHERE e.deleted_at IS NULL
    UNION ALL
    -- cash leg of adjustments that touch cash
    SELECT a.firm_id, 'adjustment', a.id,
           CASE a.kind WHEN 'cash_add' THEN 'Add Cash' WHEN 'cash_reduce' THEN 'Reduce Cash'
                       WHEN 'bank_to_cash' THEN 'Cash Withdraw' ELSE 'Cash Deposit' END,
           coalesce(b.name, a.description, ''), NULL, a.adjustment_date, a.created_at, 'cash',
           CASE WHEN a.kind IN ('cash_add', 'bank_to_cash') THEN a.amount ELSE -a.amount END,
           'cash', NULL
      FROM fund_adjustments a LEFT JOIN bank_accounts b ON b.id = a.bank_account_id
     WHERE a.deleted_at IS NULL AND a.kind IN ('cash_add', 'cash_reduce', 'bank_to_cash', 'cash_to_bank')
    UNION ALL
    -- bank leg (source bank for transfers)
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
    -- destination leg of bank-to-bank transfers
    SELECT a.firm_id, 'adjustment', a.id, 'Transfer In', 'From ' || fb.name, NULL, a.adjustment_date, a.created_at, 'bank',
           a.amount, 'bank', a.to_bank_account_id
      FROM fund_adjustments a JOIN bank_accounts fb ON fb.id = a.bank_account_id
     WHERE a.deleted_at IS NULL AND a.kind = 'bank_to_bank'
  `);
};

exports.down = (pgm) => {
  pgm.dropView('money_flows');
  pgm.dropTable('fund_adjustments');
  for (const table of ['invoices', 'payments', 'expenses']) pgm.dropColumn(table, 'bank_account_id');
  pgm.dropTable('bank_accounts');
};
