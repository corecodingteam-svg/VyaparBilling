/* Sale orders, delivery challans, proforma invoices, purchase orders (quotation-like: no stock,
 * balance or money effect; convertible) and sale/purchase returns (credit/debit notes, which
 * reverse stock, balance and money). All live in the invoices tables as further types. */

const QUOTES = ['estimate', 'sale_order', 'delivery_challan', 'proforma', 'purchase_order'];
const POSTING = ['sale', 'purchase', 'credit_note', 'debit_note'];
const list = (a) => a.map((t) => `'${t}'`).join(',');

const accountCase = `CASE WHEN payment_mode = 'cash' THEN 'cash' WHEN bank_account_id IS NOT NULL THEN 'bank'
                          WHEN payment_mode = 'cheque' THEN 'cheque' ELSE 'none' END`;

/** money_flows with the invoice branch parameterised; the other branches are unchanged. */
const moneyFlowsSql = (invoiceBranch) => `
    ${invoiceBranch}
    UNION ALL
    SELECT p.firm_id, 'payment_' || p.type, p.id, CASE WHEN p.type = 'in' THEN 'Payment-In' ELSE 'Payment-Out' END, pa.name, p.number,
           p.payment_date, p.created_at, p.payment_mode,
           CASE WHEN p.type = 'in' THEN p.amount ELSE -p.amount END,
           ${accountCase}, p.bank_account_id
      FROM payments p JOIN parties pa ON pa.id = p.party_id
     WHERE p.deleted_at IS NULL
    UNION ALL
    SELECT e.firm_id, 'expense', e.id, 'Expense', c.name, e.number,
           e.expense_date, e.created_at, e.payment_mode, -e.total,
           ${accountCase}, e.bank_account_id
      FROM expenses e JOIN expense_categories c ON c.id = e.category_id
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
     WHERE a.deleted_at IS NULL AND a.kind = 'bank_to_bank'`;

// Money comes in on sales and purchase returns; it goes out on purchases and sale returns.
const newInvoiceBranch = `
    SELECT i.firm_id, i.type AS source, i.id AS source_id,
           CASE i.type WHEN 'sale' THEN 'Sale' WHEN 'purchase' THEN 'Purchase'
                       WHEN 'credit_note' THEN 'Credit Note' ELSE 'Debit Note' END AS label,
           i.party_name AS name, i.number AS ref_number, i.invoice_date AS flow_date, i.created_at, i.payment_mode,
           CASE WHEN i.type IN ('sale', 'debit_note') THEN i.received ELSE -i.received END AS amount,
           ${accountCase} AS account, i.bank_account_id
      FROM invoices i
     WHERE i.deleted_at IS NULL AND i.type IN (${list(POSTING)}) AND i.received > 0`;

const oldInvoiceBranch = `
    SELECT i.firm_id, i.type AS source, i.id AS source_id, initcap(i.type) AS label, i.party_name AS name, i.number AS ref_number,
           i.invoice_date AS flow_date, i.created_at, i.payment_mode,
           CASE WHEN i.type = 'sale' THEN i.received ELSE -i.received END AS amount,
           ${accountCase} AS account, i.bank_account_id
      FROM invoices i
     WHERE i.deleted_at IS NULL AND i.type IN ('sale', 'purchase') AND i.received > 0`;

exports.moneyFlowsSql = moneyFlowsSql;
exports.invoiceBranch = newInvoiceBranch;

exports.up = (pgm) => {
  pgm.dropConstraint('invoices', 'invoices_type_check');
  pgm.addConstraint('invoices', 'invoices_type_check', { check: `type IN (${list([...POSTING, ...QUOTES])})` });

  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', {
    check: `type IN ('opening','add','reduce',${list(POSTING)})`,
  });

  pgm.dropView('money_flows');
  pgm.createView('money_flows', {}, moneyFlowsSql(newInvoiceBranch));
};

exports.down = (pgm) => {
  pgm.dropView('money_flows');
  pgm.sql(`DELETE FROM stock_movements WHERE type IN ('credit_note','debit_note')`);
  pgm.sql(`DELETE FROM invoices WHERE type NOT IN ('sale','purchase','estimate')`);
  pgm.createView('money_flows', {}, moneyFlowsSql(oldInvoiceBranch));
  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', { check: "type IN ('opening','add','reduce','sale','purchase')" });
  pgm.dropConstraint('invoices', 'invoices_type_check');
  pgm.addConstraint('invoices', 'invoices_type_check', { check: "type IN ('sale','purchase','estimate')" });
};
