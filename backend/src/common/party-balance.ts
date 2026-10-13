import { RawBuilder, sql } from 'kysely';

/**
 * A party's current balance (positive = they owe us, negative = we owe them):
 * opening balance + unpaid sales − unpaid purchases − payments received + payments made, with sale
 * returns (credit notes) and purchase returns (debit notes) reversing their side. Quotation-like
 * documents (estimates, orders, challans, proformas) never count. A foreign-currency payment settles
 * invoices at the rate they were booked at; the difference to what was actually paid is an exchange
 * gain or loss (payments.fx_gain), not part of the party's balance.
 * [partyId] is a SQL reference to the party id column, e.g. sql.ref('parties.id').
 */
/**
 * What an invoice (alias i) leaves owing before later payments: its total less what was paid with
 * it, less TDS the payer holds back, less loyalty points redeemed against it.
 */
export const UNPAID_SQL = sql.raw('(i.total - i.received - i.tds_amount - i.loyalty_amount)');

/** With [asOf] (yyyy-mm-dd) only documents and payments dated on or before that day count. */
export function partyBalanceSql(partyId: RawBuilder<unknown> | ReturnType<typeof sql.ref>, openingBalance: ReturnType<typeof sql.ref>, asOf?: string) {
  const invoicesUpTo = asOf ? sql`and i.invoice_date <= ${asOf}` : sql``;
  const paymentsUpTo = asOf ? sql`and pm.payment_date <= ${asOf}` : sql``;
  return sql<string>`(
    ${openingBalance}
    + coalesce((select sum(case when i.type in ('sale', 'debit_note') then ${UNPAID_SQL} else -(${UNPAID_SQL}) end)
                from invoices i where i.party_id = ${partyId} and i.deleted_at is null
                  and i.type in ('sale', 'purchase', 'credit_note', 'debit_note') ${invoicesUpTo}), 0)
    + coalesce((select sum(case when pm.type = 'out' then pm.amount + pm.fx_gain else -(pm.amount - pm.fx_gain) end)
                from payments pm where pm.party_id = ${partyId} and pm.deleted_at is null ${paymentsUpTo}), 0)
  )`;
}

export const PAYMENT_MODES = ['cash', 'bank', 'upi', 'cheque', 'card'] as const;

/** Rupee rounding to 2 decimals without float drift. */
export const r2 = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;
