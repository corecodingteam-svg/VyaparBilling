/* Purchase bills carry the supplier's own bill number: optional and not unique.
 * Only our own sale invoice numbers must be unique. */

exports.up = (pgm) => {
  pgm.dropIndex('invoices', ['firm_id', 'type', 'number'], { name: 'invoices_number_unique' });
  pgm.createIndex('invoices', ['firm_id', 'number'], {
    unique: true,
    where: "deleted_at IS NULL AND type = 'sale'",
    name: 'invoices_sale_number_unique',
  });
};

exports.down = (pgm) => {
  pgm.dropIndex('invoices', ['firm_id', 'number'], { name: 'invoices_sale_number_unique' });
  pgm.createIndex('invoices', ['firm_id', 'type', 'number'], {
    unique: true,
    where: 'deleted_at IS NULL',
    name: 'invoices_number_unique',
  });
};
