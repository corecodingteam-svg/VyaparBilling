/* Per-business settings (see backend/src/firm/firm-settings.ts for the keys and defaults). */

exports.up = (pgm) => {
  pgm.addColumn('firms', { settings: { type: 'jsonb', notNull: true, default: '{}' } });
};

exports.down = (pgm) => {
  pgm.dropColumn('firms', 'settings');
};
