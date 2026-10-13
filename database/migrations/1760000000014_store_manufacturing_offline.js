/* Seventh batch: manufacturing (bills of materials and production entries), the online store, and
 * idempotency keys so a save sent again by an app that was offline is applied only once. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  // ---- manufacturing
  pgm.createTable('bom_lines', {
    id,
    firm_id: firmRef,
    item_id: { type: 'uuid', notNull: true, references: 'items', onDelete: 'CASCADE' },
    component_id: { type: 'uuid', notNull: true, references: 'items', onDelete: 'CASCADE' },
    quantity: { type: 'numeric(14,3)', notNull: true, check: 'quantity > 0' },
    sort_order: { type: 'integer', notNull: true, default: 0 },
  });
  pgm.addConstraint('bom_lines', 'bom_lines_unique', { unique: ['item_id', 'component_id'] });
  pgm.addConstraint('bom_lines', 'bom_lines_not_self', { check: 'item_id <> component_id' });

  pgm.createTable('manufacture_entries', {
    id,
    firm_id: firmRef,
    number: { type: 'text', notNull: true },
    item_id: { type: 'uuid', notNull: true, references: 'items' },
    quantity: { type: 'numeric(14,3)', notNull: true, check: 'quantity > 0' },
    entry_date: { type: 'date', notNull: true },
    godown_id: { type: 'uuid', references: 'godowns' },
    component_cost: { type: 'numeric(14,2)', notNull: true, default: 0 },
    extra_cost: { type: 'numeric(14,2)', notNull: true, default: 0 },
    description: { type: 'text' },
    created_by: { type: 'uuid' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('manufacture_entries', ['firm_id', 'entry_date']);
  pgm.addColumn('stock_movements', { manufacture_id: { type: 'uuid', references: 'manufacture_entries', onDelete: 'CASCADE' } });
  pgm.dropConstraint('stock_movements', 'stock_movements_type_check');
  pgm.addConstraint('stock_movements', 'stock_movements_type_check', {
    check: "type IN ('opening','add','reduce','sale','purchase','credit_note','debit_note','transfer','manufacture_in','manufacture_out')",
  });

  // ---- online store
  pgm.addColumn('firms', { store_slug: { type: 'text', unique: true } });
  pgm.addColumn('items', { in_store: { type: 'boolean', notNull: true, default: false } });
  pgm.createTable('store_orders', {
    id,
    firm_id: firmRef,
    invoice_id: { type: 'uuid', references: 'invoices', onDelete: 'CASCADE' },
    customer_name: { type: 'text', notNull: true },
    phone: { type: 'text', notNull: true },
    address: { type: 'text' },
    note: { type: 'text' },
    client_hash: { type: 'text' },
    status: { type: 'text', notNull: true, default: 'new', check: "status IN ('new','accepted','rejected')" },
    created_at: now,
  });
  pgm.createIndex('store_orders', ['firm_id', 'created_at']);

  // ---- offline sync
  pgm.createTable('idempotency_keys', {
    firm_id: firmRef,
    key: { type: 'text', notNull: true },
    method: { type: 'text', notNull: true },
    path: { type: 'text', notNull: true },
    status: { type: 'integer', notNull: true },
    response: { type: 'jsonb' },
    created_at: now,
  });
  pgm.addConstraint('idempotency_keys', 'idempotency_keys_pk', { primaryKey: ['firm_id', 'key'] });
};

exports.down = () => {
  throw new Error('Not reversible; restore from a backup instead.');
};
