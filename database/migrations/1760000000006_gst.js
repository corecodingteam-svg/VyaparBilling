/* GST on invoices. Each line has a rate and is split into taxable value + CGST/SGST (intra-state)
 * or IGST (inter-state). `amount` on a line and `subtotal`/`total` on the invoice stay tax-inclusive,
 * so balances and cash/bank flows are unchanged. */

exports.up = (pgm) => {
  const money = { type: 'numeric(14,2)', notNull: true, default: 0 };

  pgm.addColumns('invoice_items', {
    hsn_code: { type: 'varchar(8)' },
    gst_rate: { type: 'numeric(5,2)', notNull: true, default: 0 },
    taxable_value: money,
    cgst: money,
    sgst: money,
    igst: money,
  });
  pgm.sql('UPDATE invoice_items SET taxable_value = amount');

  pgm.addColumns('invoices', {
    // Whether the typed unit prices already include GST.
    prices_include_tax: { type: 'boolean', notNull: true, default: false },
    // Supply to another state than ours → IGST instead of CGST + SGST.
    is_inter_state: { type: 'boolean', notNull: true, default: false },
    party_gstin: { type: 'varchar(15)' },
    taxable_amount: money,
    cgst: money,
    sgst: money,
    igst: money,
  });
  pgm.sql('UPDATE invoices SET taxable_amount = subtotal');
};

exports.down = (pgm) => {
  pgm.dropColumns('invoices', ['prices_include_tax', 'is_inter_state', 'party_gstin', 'taxable_amount', 'cgst', 'sgst', 'igst']);
  pgm.dropColumns('invoice_items', ['hsn_code', 'gst_rate', 'taxable_value', 'cgst', 'sgst', 'igst']);
};
