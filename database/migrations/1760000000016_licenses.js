/* Licences. The server is the authority; devices get a signed certificate made from these rows.
 * One licence per company. This replaces firms.licence_expires_on / suspended / suspended_reason, which are moved here. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.createTable('licenses', {
    id,
    firm_id: { type: 'uuid', notNull: true, unique: true, references: 'firms', onDelete: 'CASCADE' },
    product_id: { type: 'text', notNull: true, default: 'billing' },
    status: { type: 'text', notNull: true, default: 'active', check: "status IN ('active','suspended','revoked')" },
    status_reason: { type: 'text' },
    valid_from: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    /** The first instant the licence no longer works; null = no end. */
    expires_at: { type: 'timestamptz' },
    max_devices: { type: 'integer', notNull: true, default: 5, check: 'max_devices >= 1' },
    /** Raised on every change to the licence, so a device can tell its certificate is out of date. */
    version: { type: 'integer', notNull: true, default: 1 },
    created_at: now,
    updated_at: now,
  });

  pgm.createTable('license_devices', {
    id,
    license_id: { type: 'uuid', notNull: true, references: 'licenses', onDelete: 'CASCADE' },
    installation_id: { type: 'text', notNull: true },
    device_name: { type: 'text' },
    platform: { type: 'text' },
    activated_at: now,
    last_seen_at: now,
  });
  pgm.addConstraint('license_devices', 'license_devices_unique', { unique: ['license_id', 'installation_id'] });

  // Existing companies: carry over their end date (the last day, in India) and suspension.
  pgm.sql(`
    INSERT INTO licenses (firm_id, status, status_reason, valid_from, expires_at)
    SELECT id,
           CASE WHEN suspended THEN 'suspended' ELSE 'active' END,
           suspended_reason,
           created_at,
           CASE WHEN licence_expires_on IS NULL THEN NULL ELSE ((licence_expires_on + 1)::timestamp AT TIME ZONE 'Asia/Kolkata') END
    FROM firms`);
  pgm.dropColumns('firms', ['licence_expires_on', 'suspended', 'suspended_reason']);

  // Every new company (sign-up, provider sign-up, restore) gets a licence.
  pgm.sql(`
    CREATE FUNCTION create_default_license() RETURNS trigger AS $$
    BEGIN
      INSERT INTO licenses (firm_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE TRIGGER firms_default_license AFTER INSERT ON firms FOR EACH ROW EXECUTE FUNCTION create_default_license();`);
};

exports.down = (pgm) => {
  pgm.sql('DROP TRIGGER firms_default_license ON firms; DROP FUNCTION create_default_license();');
  pgm.addColumns('firms', {
    licence_expires_on: { type: 'date' },
    suspended: { type: 'boolean', notNull: true, default: false },
    suspended_reason: { type: 'text' },
  });
  pgm.sql(`UPDATE firms f SET suspended = (l.status <> 'active'), suspended_reason = l.status_reason,
           licence_expires_on = (l.expires_at AT TIME ZONE 'Asia/Kolkata')::date - 1 FROM licenses l WHERE l.firm_id = f.id`);
  pgm.dropTable('license_devices');
  pgm.dropTable('licenses');
};
