/* Expenses (with categories) and estimates/quotations.
 * Estimates reuse the invoices tables as type 'estimate': no stock or balance effect, and a status
 * that flips to 'converted' when a sale is created from them. */

const DEFAULT_EXPENSE_CATEGORIES = ['Petrol', 'Rent', 'Salary', 'Tea', 'Transport'];

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('expense_categories', { id, firm_id: firmRef, name: { type: 'text', notNull: true }, created_at: now });
  pgm.createIndex('expense_categories', ['firm_id', 'lower(name)'], { unique: true, name: 'expense_categories_firm_name_unique' });
  // Existing firms get the same starter categories as new ones.
  pgm.sql(`
    INSERT INTO expense_categories (firm_id, name)
    SELECT f.id, c.name FROM firms f CROSS JOIN (VALUES ${DEFAULT_EXPENSE_CATEGORIES.map((c) => `('${c}')`).join(', ')}) AS c(name)
  `);

  pgm.createTable('expenses', {
    id,
    firm_id: firmRef,
    category_id: { type: 'uuid', notNull: true, references: 'expense_categories' },
    number: { type: 'text' },
    expense_date: { type: 'date', notNull: true },
    subtotal: { type: 'numeric(14,2)', notNull: true },
    round_off: { type: 'numeric(14,2)', notNull: true, default: 0 },
    total: { type: 'numeric(14,2)', notNull: true },
    payment_mode: { type: 'text', notNull: true, default: 'cash', check: "payment_mode IN ('cash','bank','upi','cheque','card')" },
    description: { type: 'text' },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('expenses', ['firm_id', 'category_id', 'expense_date']);

  pgm.createTable('expense_items', {
    id,
    expense_id: { type: 'uuid', notNull: true, references: 'expenses', onDelete: 'CASCADE' },
    name: { type: 'text', notNull: true },
    quantity: { type: 'numeric(14,3)', notNull: true },
    price: { type: 'numeric(14,2)', notNull: true },
    amount: { type: 'numeric(14,2)', notNull: true },
    sort_order: { type: 'integer', notNull: true },
  });
  pgm.createIndex('expense_items', ['expense_id']);

  // ---- estimates
  pgm.dropConstraint('invoices', 'invoices_type_check');
  pgm.addConstraint('invoices', 'invoices_type_check', { check: "type IN ('sale','purchase','estimate')" });
  pgm.addColumn('invoices', {
    // Estimates only: the sale created from this estimate (null = still open).
    converted_invoice_id: { type: 'uuid', references: 'invoices', onDelete: 'SET NULL' },
  });
  // Our own number series (sale invoices, estimates) are unique per type; supplier bill numbers are not.
  pgm.dropIndex('invoices', ['firm_id', 'number'], { name: 'invoices_sale_number_unique' });
  pgm.createIndex('invoices', ['firm_id', 'type', 'number'], {
    unique: true,
    where: "deleted_at IS NULL AND type <> 'purchase'",
    name: 'invoices_own_number_unique',
  });
};

exports.down = (pgm) => {
  pgm.dropIndex('invoices', ['firm_id', 'type', 'number'], { name: 'invoices_own_number_unique' });
  pgm.sql("DELETE FROM invoices WHERE type = 'estimate'");
  pgm.createIndex('invoices', ['firm_id', 'number'], {
    unique: true,
    where: "deleted_at IS NULL AND type = 'sale'",
    name: 'invoices_sale_number_unique',
  });
  pgm.dropColumn('invoices', 'converted_invoice_id');
  pgm.dropConstraint('invoices', 'invoices_type_check');
  pgm.addConstraint('invoices', 'invoices_type_check', { check: "type IN ('sale','purchase')" });
  pgm.dropTable('expense_items');
  pgm.dropTable('expenses');
  pgm.dropTable('expense_categories');
};
