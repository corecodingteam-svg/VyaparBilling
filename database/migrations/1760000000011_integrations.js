/* Fourth batch: provider integrations (WhatsApp, SMS, e-invoice / e-way bill, Razorpay, Google Business
 * Profile). Credentials are stored encrypted by the application; this migration only adds the tables. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('integrations', {
    id,
    firm_id: firmRef,
    provider: { type: 'text', notNull: true, check: "provider IN ('whatsapp','sms','einvoice','razorpay','google_profile')" },
    // Non-secret settings (sender id, template names, API base URL, ...).
    config: { type: 'jsonb', notNull: true, default: '{}' },
    // Secret settings (tokens, passwords), encrypted by the app; never returned by the API.
    secrets: { type: 'text' },
    created_at: now,
    updated_at: now,
  });
  pgm.addConstraint('integrations', 'integrations_unique', { unique: ['firm_id', 'provider'] });

  pgm.createTable('message_log', {
    id,
    firm_id: firmRef,
    channel: { type: 'text', notNull: true, check: "channel IN ('whatsapp','sms')" },
    // What it was about: an invoice or payment, a reminder, a marketing message, a test.
    kind: { type: 'text', notNull: true, check: "kind IN ('invoice','payment','reminder','marketing','test','other')" },
    party_id: { type: 'uuid', references: 'parties', onDelete: 'SET NULL' },
    ref_id: { type: 'uuid' },
    to_phone: { type: 'text', notNull: true },
    body: { type: 'text', notNull: true },
    status: { type: 'text', notNull: true, check: "status IN ('sent','failed')" },
    provider_id: { type: 'text' },
    error: { type: 'text' },
    created_by: { type: 'uuid', references: 'users', onDelete: 'SET NULL' },
    created_at: now,
  });
  pgm.createIndex('message_log', ['firm_id', 'created_at']);
  pgm.createIndex('message_log', ['party_id']);

  // e-invoice / e-way bill state on each document, and the transport details the e-way bill needs.
  pgm.addColumns('invoices', {
    einvoice_status: { type: 'text', notNull: true, default: 'none', check: "einvoice_status IN ('none','generated','cancelled')" },
    irn: { type: 'text' },
    ack_no: { type: 'text' },
    ack_date: { type: 'timestamptz' },
    signed_qr: { type: 'text' },
    irn_cancelled_at: { type: 'timestamptz' },
    eway_bill_no: { type: 'text' },
    eway_bill_date: { type: 'timestamptz' },
    eway_valid_upto: { type: 'timestamptz' },
    transporter_id: { type: 'text' },
    transporter_name: { type: 'text' },
    transport_mode: { type: 'text', check: "transport_mode IN ('road','rail','air','ship')" },
    transport_doc_no: { type: 'text' },
    transport_doc_date: { type: 'date' },
    vehicle_no: { type: 'text' },
    distance_km: { type: 'integer' },
  });
  pgm.createIndex('invoices', ['firm_id', 'irn'], { where: 'irn IS NOT NULL', name: 'invoices_irn_idx' });

  // The e-invoice schema wants a place and PIN code on both sides.
  pgm.addColumns('parties', { city: { type: 'text' }, pincode: { type: 'varchar(6)' } });
  pgm.addColumn('firms', { city: { type: 'text' } });

  // Online payment links (Razorpay): one per request, closed when the customer pays.
  pgm.createTable('payment_links', {
    id,
    firm_id: firmRef,
    invoice_id: { type: 'uuid', notNull: true, references: 'invoices', onDelete: 'CASCADE' },
    provider: { type: 'text', notNull: true, check: "provider IN ('razorpay')" },
    provider_link_id: { type: 'text', notNull: true },
    short_url: { type: 'text', notNull: true },
    amount: { type: 'numeric(14,2)', notNull: true, check: 'amount > 0' },
    status: { type: 'text', notNull: true, default: 'created', check: "status IN ('created','paid','cancelled','expired','failed')" },
    // The Payment-In recorded when it was paid.
    payment_id: { type: 'uuid', references: 'payments', onDelete: 'SET NULL' },
    provider_payment_id: { type: 'text' },
    note: { type: 'text' },
    created_by: { type: 'uuid', references: 'users', onDelete: 'SET NULL' },
    created_at: now,
    paid_at: { type: 'timestamptz' },
  });
  pgm.addConstraint('payment_links', 'payment_links_provider_unique', { unique: ['provider', 'provider_link_id'] });
  pgm.createIndex('payment_links', ['invoice_id']);
};

exports.down = () => {
  throw new Error('Not reversible; restore from a backup instead.');
};
