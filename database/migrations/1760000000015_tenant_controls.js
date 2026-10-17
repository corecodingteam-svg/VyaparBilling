/* Provider-controlled tenant settings: the plan, feature switches (e.g. POS only), a licence end date and suspension.
 * They live apart from firms.settings, which the business's own owner can change. */

exports.up = (pgm) => {
  pgm.addColumns('firms', {
    features: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    plan: { type: 'text', notNull: true, default: 'full' },
    licence_expires_on: { type: 'date' },
    suspended: { type: 'boolean', notNull: true, default: false },
    suspended_reason: { type: 'text' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumns('firms', ['features', 'plan', 'licence_expires_on', 'suspended', 'suspended_reason']);
};
