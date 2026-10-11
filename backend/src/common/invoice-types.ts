/**
 * Every document stored in the invoices tables and what it does.
 *  - stock:   sign applied to product quantities (sale −, purchase +, returns reverse; 0 = none)
 *  - balance: sign of its unpaid amount in the party's balance and of its paid amount in cash/bank
 *             (sale +, purchase −, returns reverse; 0 = quotation-like, no accounting effect)
 *  - ownNumber: we issue the number (required, unique per type); a purchase carries the supplier's
 *  - convertsTo: quotation-like documents can be turned into these types
 */
export const INVOICE_TYPES = {
  sale: { label: 'Sale', stock: -1, balance: 1, ownNumber: true, convertsTo: [] },
  purchase: { label: 'Purchase', stock: 1, balance: -1, ownNumber: false, convertsTo: [] },
  credit_note: { label: 'Credit Note', stock: 1, balance: -1, ownNumber: true, convertsTo: [] },
  debit_note: { label: 'Debit Note', stock: -1, balance: 1, ownNumber: true, convertsTo: [] },
  estimate: { label: 'Estimate', stock: 0, balance: 0, ownNumber: true, convertsTo: ['sale', 'sale_order'] },
  sale_order: { label: 'Sale Order', stock: 0, balance: 0, ownNumber: true, convertsTo: ['sale'] },
  delivery_challan: { label: 'Delivery Challan', stock: 0, balance: 0, ownNumber: true, convertsTo: ['sale'] },
  proforma: { label: 'Proforma Invoice', stock: 0, balance: 0, ownNumber: true, convertsTo: ['sale'] },
  purchase_order: { label: 'Purchase Order', stock: 0, balance: 0, ownNumber: true, convertsTo: ['purchase'] },
} as const satisfies Record<string, { label: string; stock: -1 | 0 | 1; balance: -1 | 0 | 1; ownNumber: boolean; convertsTo: readonly string[] }>;

export type InvoiceType = keyof typeof INVOICE_TYPES;

export const INVOICE_TYPE_NAMES = Object.keys(INVOICE_TYPES) as InvoiceType[];

/** Types that post to stock, party balances and cash/bank. */
export const POSTING_TYPES = INVOICE_TYPE_NAMES.filter((t) => INVOICE_TYPES[t].balance !== 0);

/** Quotation-like types: open until converted. */
export const isQuote = (t: InvoiceType) => INVOICE_TYPES[t].balance === 0;
