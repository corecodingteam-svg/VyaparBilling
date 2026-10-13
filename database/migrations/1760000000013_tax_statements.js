/* Sixth batch: what the quarterly TDS (Form 140) and TCS (Form 143) statements need — the company's TAN and
 * PAN, each party's PAN and section, and the challans the tax was deposited with. */

exports.up = (pgm) => {
  const id = { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') };
  const firmRef = { type: 'uuid', notNull: true, references: 'firms', onDelete: 'CASCADE' };
  const now = { type: 'timestamptz', notNull: true, default: pgm.func('now()') };

  pgm.addColumn('firms', { tan: { type: 'text' }, pan: { type: 'text' } });
  pgm.addColumn('parties', {
    pan: { type: 'text' },
    // Section code of the TDS deducted from this party (Form 140), or the collection code of TCS collected from them (Form 143).
    tds_section: { type: 'text' },
    tcs_code: { type: 'text' },
    // Form 143 Annexure 8 (1 company, 2 individual, …).
    collectee_code: { type: 'smallint' },
  });

  pgm.createTable('tax_challans', {
    id,
    firm_id: firmRef,
    kind: { type: 'text', notNull: true, check: "kind IN ('tds','tcs')" },
    /** e.g. 202627 for tax year 2026-27 */
    tax_year: { type: 'text', notNull: true },
    quarter: { type: 'text', notNull: true, check: "quarter IN ('Q1','Q2','Q3','Q4')" },
    bsr_code: { type: 'text', notNull: true },
    challan_no: { type: 'text', notNull: true },
    deposit_date: { type: 'date', notNull: true },
    tax: { type: 'numeric(14,2)', notNull: true, default: 0 },
    interest: { type: 'numeric(14,2)', notNull: true, default: 0 },
    fee: { type: 'numeric(14,2)', notNull: true, default: 0 },
    other: { type: 'numeric(14,2)', notNull: true, default: 0 },
    minor_head: { type: 'text', notNull: true, default: '200' },
    created_at: now,
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('tax_challans', ['firm_id', 'kind', 'tax_year', 'quarter']);
};

exports.down = () => {
  throw new Error('Not reversible; restore from a backup instead.');
};
