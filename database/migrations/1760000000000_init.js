/* Billing app foundation: firms, users, parties, categories, units, items, stock movements.
 * Money is numeric(14,2) (rupees); quantities numeric(14,3). Every business row is scoped by firm_id. */

exports.up = (pgm) => {
  pgm.createExtension('pgcrypto', { ifNotExists: true });

  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('firms', {
    id,
    name: { type: 'text', notNull: true },
    phone: { type: 'text' },
    gstin: { type: 'varchar(15)' },
    email: { type: 'text' },
    books_start_date: { type: 'date', notNull: true, default: pgm.func('CURRENT_DATE') },
    business_type: { type: 'text' },
    business_category: { type: 'text' },
    state_code: { type: 'char(2)' },
    pincode: { type: 'varchar(6)' },
    address: { type: 'text' },
    created_at: now,
    updated_at: now,
  });

  pgm.createTable('users', {
    id,
    firm_id: firmRef,
    email: { type: 'text', notNull: true, unique: true },
    password_hash: { type: 'text', notNull: true },
    full_name: { type: 'text', notNull: true },
    role: { type: 'text', notNull: true, default: 'owner' },
    created_at: now,
  });

  pgm.createTable('parties', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    phone: { type: 'text' },
    gstin: { type: 'varchar(15)' },
    gst_type: {
      type: 'text',
      notNull: true,
      default: 'unregistered',
      check: "gst_type IN ('unregistered','regular','composition')",
    },
    state_code: { type: 'char(2)' },
    email: { type: 'text' },
    billing_address: { type: 'text' },
    shipping_address: { type: 'text' },
    // Positive = party owes us (to receive); negative = we owe the party (to pay).
    opening_balance: { type: 'numeric(14,2)', notNull: true, default: 0 },
    opening_balance_date: { type: 'date', notNull: true, default: pgm.func('CURRENT_DATE') },
    credit_limit: { type: 'numeric(14,2)' }, // null = no limit
    additional_fields: { type: 'jsonb', notNull: true, default: '[]' }, // [{name, value}]
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('parties', ['firm_id', 'name']);

  pgm.createTable('categories', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    created_at: now,
  });
  pgm.createIndex('categories', ['firm_id', 'lower(name)'], { unique: true, name: 'categories_firm_name_unique' });

  pgm.createTable('units', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    short_name: { type: 'text', notNull: true },
    created_at: now,
  });
  pgm.createIndex('units', ['firm_id', 'lower(short_name)'], { unique: true, name: 'units_firm_short_unique' });

  pgm.createTable('items', {
    id,
    firm_id: firmRef,
    type: { type: 'text', notNull: true, default: 'product', check: "type IN ('product','service')" },
    name: { type: 'text', notNull: true },
    hsn_code: { type: 'varchar(8)' },
    unit: { type: 'text' },
    category_id: { type: 'uuid', references: 'categories', onDelete: 'SET NULL' },
    item_code: { type: 'text' },
    sale_price: { type: 'numeric(14,2)', notNull: true, default: 0 },
    sale_price_includes_tax: { type: 'boolean', notNull: true, default: false },
    sale_discount: { type: 'numeric(14,2)', notNull: true, default: 0 },
    sale_discount_type: { type: 'text', notNull: true, default: 'percent', check: "sale_discount_type IN ('percent','amount')" },
    wholesale_price: { type: 'numeric(14,2)' },
    wholesale_min_qty: { type: 'numeric(14,3)' },
    purchase_price: { type: 'numeric(14,2)', notNull: true, default: 0 },
    purchase_price_includes_tax: { type: 'boolean', notNull: true, default: false },
    gst_rate: { type: 'numeric(5,2)' }, // null = none
    opening_qty: { type: 'numeric(14,3)', notNull: true, default: 0 },
    opening_price: { type: 'numeric(14,2)' },
    opening_date: { type: 'date', notNull: true, default: pgm.func('CURRENT_DATE') },
    min_stock: { type: 'numeric(14,3)' },
    location: { type: 'text' },
    stock_qty: { type: 'numeric(14,3)', notNull: true, default: 0 },
    created_at: now,
    updated_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('items', ['firm_id', 'name']);
  pgm.createIndex('items', ['firm_id', 'item_code'], {
    unique: true,
    where: 'item_code IS NOT NULL AND deleted_at IS NULL',
  });

  pgm.createTable('stock_movements', {
    id,
    firm_id: firmRef,
    item_id: { type: 'uuid', notNull: true, references: 'items', onDelete: 'CASCADE' },
    type: { type: 'text', notNull: true, check: "type IN ('opening','add','reduce')" },
    qty_change: { type: 'numeric(14,3)', notNull: true },
    price_per_unit: { type: 'numeric(14,2)' },
    movement_date: { type: 'date', notNull: true },
    notes: { type: 'text' },
    created_at: now,
  });
  pgm.createIndex('stock_movements', ['item_id', 'movement_date']);
};

exports.down = (pgm) => {
  ['stock_movements', 'items', 'units', 'categories', 'parties', 'users', 'firms'].forEach((t) => pgm.dropTable(t));
};
