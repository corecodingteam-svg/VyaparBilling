/* Fifth batch: supplier state on expenses (so their GST can be IGST) and geofences for location tracking. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  // The supplier's state; when it differs from the company's the expense's GST is IGST.
  pgm.addColumn('expenses', { supplier_state: { type: 'text' }, supplier_gstin: { type: 'text' } });

  pgm.createTable('geofences', {
    id,
    firm_id: firmRef,
    name: { type: 'text', notNull: true },
    latitude: { type: 'double precision', notNull: true },
    longitude: { type: 'double precision', notNull: true },
    radius_m: { type: 'integer', notNull: true, check: 'radius_m between 20 and 50000' },
    created_at: now,
  });
  pgm.createIndex('geofences', ['firm_id']);
};

exports.down = () => {
  throw new Error('Not reversible; restore from a backup instead.');
};
