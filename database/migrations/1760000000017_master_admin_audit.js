/* The single master admin (the provider), kept apart from every business's users; disabling a business user's login;
 * and an audit log of everything the master admin does. */

exports.up = (pgm) => {
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('master_admin', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
    // Always true and unique: the table can never hold a second master admin.
    singleton: { type: 'boolean', notNull: true, default: true, unique: true, check: 'singleton' },
    email: { type: 'text', notNull: true },
    full_name: { type: 'text', notNull: true },
    password_hash: { type: 'text', notNull: true },
    created_at: now,
    updated_at: now,
  });

  pgm.addColumns('users', { disabled_at: { type: 'timestamptz' } });

  pgm.createTable('platform_audit', {
    id: { type: 'bigserial', primaryKey: true },
    at: now,
    actor_email: { type: 'text', notNull: true },
    action: { type: 'text', notNull: true },
    // Kept as plain values so the entry survives the business or user being deleted.
    firm_id: { type: 'uuid' },
    firm_name: { type: 'text' },
    target: { type: 'text' },
    details: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
  });
  pgm.createIndex('platform_audit', ['at']);
  pgm.createIndex('platform_audit', ['firm_id', 'at']);
};

exports.down = (pgm) => {
  pgm.dropTable('platform_audit');
  pgm.dropColumns('users', ['disabled_at']);
  pgm.dropTable('master_admin');
};
