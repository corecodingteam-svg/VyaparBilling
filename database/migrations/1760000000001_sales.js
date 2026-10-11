/* Sale/purchase invoices, payments in/out, and invoice-linked stock movements.
 * Invoices keep a snapshot of party name/address and line item names so history survives edits. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };
  const paymentMode = {
    type: 'text',
    notNull: true,
    default: 'cash',
    check: "%s IN ('cash','bank','upi','cheque','card')",
  };

  pgm.createTable('invoices', {
    id,
    firm_id: firmRef,
    type: { type: 'text', notNull: true, check: "type IN ('sale','purchase')" },
    number: { type: 'text', notNull: true },
    invoice_date: { type: 'date', notNull: true },
    is_cash: { type: 'boolean', notNull: true, default: false },
    party_id: { type: 'uuid', references: 'parties' }, // null = walk-in cash customer
    party_name: { type: 'text', notNull: true },
    phone: { type: 'text' },
    billing_address: { type: 'text' },
    state_of_supply: { type: 'char(2)' },
    subtotal: { type: 'numeric(14,2)', notNull: true },
    round_off: { type: 'numeric(14,2)', notNull: true, default: 0 },
    total: { type: 'numeric(14,2)', notNull: true },
    received: { type: 'numeric(14,2)', notNull: true, default: 0 }, // paid at billing time
    payment_mode: { ...paymentMode, check: paymentMode.check.replace('%s', 'payment_mode') },
    description: { type: 'text' },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('invoices', ['firm_id', 'type', 'number'], {
    unique: true,
    where: 'deleted_at IS NULL',
    name: 'invoices_number_unique',
  });
  pgm.createIndex('invoices', ['firm_id', 'type', 'invoice_date']);
  pgm.createIndex('invoices', ['party_id']);

  pgm.createTable('invoice_items', {
    id,
    invoice_id: { type: 'uuid', notNull: true, references: 'invoices', onDelete: 'CASCADE' },
    item_id: { type: 'uuid', references: 'items' }, // null = free-text line, no stock effect
    name: { type: 'text', notNull: true },
    quantity: { type: 'numeric(14,3)', notNull: true },
    unit: { type: 'text' },
    price: { type: 'numeric(14,2)', notNull: true },
    discount_pct: { type: 'numeric(5,2)', notNull: true, default: 0 },
    discount_amount: { type: 'numeric(14,2)', notNull: true, default: 0 },
    amount: { type: 'numeric(14,2)', notNull: true },
    sort_order: { type: 'integer', notNull: true },
  });
  pgm.createIndex('invoice_items', ['invoice_id']);

  pgm.createTable('payments', {
    id,
    firm_id: firmRef,
    type: { type: 'text', notNull: true, check: "type IN ('in','out')" },
    number: { type: 'text', notNull: true },
    party_id: { type: 'uuid', notNull: true, references: 'parties' },
    payment_date: { type: 'date', notNull: true },
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
    payment_mode: { ...paymentMode, check: paymentMode.check.replace('%s', 'payment_mode') },
    description: { type: 'text' },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('payments', ['firm_id', 'type', 'number'], {
    unique: true,
    where: 'deleted_at IS NULL',
    name: 'payments_number_unique',
  });
  pgm.createIndex('payments', ['firm_id', 'type', 'payment_date']);
  pgm.createIndex('payments', ['party_id']);

  pgm.addColumn('stock_movements', {
    invoice_id: { type: 'uuid', references: 'invoices', onDelete: 'CASCADE' },
  });
  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', {
    check: "type IN ('opening','add','reduce','sale','purchase')",
  });
};

exports.down = (pgm) => {
  pgm.sql("DELETE FROM stock_movements WHERE type IN ('sale','purchase')");
  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', { check: "type IN ('opening','add','reduce')" });
  pgm.dropColumn('stock_movements', 'invoice_id');
  pgm.dropTable('payments');
  pgm.dropTable('invoice_items');
  pgm.dropTable('invoices');
};
