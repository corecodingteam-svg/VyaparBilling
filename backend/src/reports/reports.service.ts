import { FirmService } from '../firm/firm.service';
import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { sql } from 'kysely';
import { INVOICE_TYPES, InvoiceType, POSTING_TYPES } from '../common/invoice-types';
import { today } from '../common/numbers';
import { partyBalanceSql, r2 } from '../common/party-balance';
import { GST_STATES } from '../common/states';
import { Db, KYSELY } from '../database/database.module';
import { PartiesService } from '../parties/parties.service';

type ColumnType = 'text' | 'date' | 'money' | 'qty' | 'number';
type Column = { key: string; label: string; type: ColumnType };
type Row = Record<string, string | number | boolean | null>;
type Figure = { label: string; value: number | string; type: ColumnType };

/** What every report returns: a table plus headline figures. Rows may set `_bold` for subtotal lines. */
export interface Report {
  id: string;
  title: string;
  /** Human description of the filter used, for the printed heading. */
  subtitle: string;
  columns: Column[];
  rows: Row[];
  summary: Figure[];
}

/** What each report builder produces; the title and default subtitle are added by run(). */
type ReportBody = Pick<Report, 'columns' | 'rows' | 'summary'> & { subtitle?: string };

export interface ReportParams {
  from?: string;
  to?: string;
  partyId?: string;
  bankAccountId?: string;
  itemId?: string;
}

/** Filters a report accepts: a date range, one party (required, or optional with "party?"), one bank account, one item. */
type Param = 'period' | 'party' | 'party?' | 'bank' | 'item';

export const REPORT_CATALOG: Array<{ id: string; title: string; group: string; params: Param[] }> = [
  { id: 'sale', title: 'Sale Report', group: 'Transaction', params: ['period'] },
  { id: 'purchase', title: 'Purchase Report', group: 'Transaction', params: ['period'] },
  { id: 'day-book', title: 'Day Book', group: 'Transaction', params: ['period'] },
  { id: 'all-transactions', title: 'All Transactions', group: 'Transaction', params: ['period'] },
  { id: 'profit-loss', title: 'Profit & Loss', group: 'Transaction', params: ['period'] },
  { id: 'bill-wise-profit', title: 'Bill Wise Profit', group: 'Transaction', params: ['period'] },
  { id: 'cash-flow', title: 'Cash Flow', group: 'Transaction', params: ['period'] },
  { id: 'balance-sheet', title: 'Balance Sheet', group: 'Transaction', params: [] },
  { id: 'trial-balance', title: 'Trial Balance', group: 'Transaction', params: [] },
  { id: 'orders', title: 'Orders & Estimates', group: 'Transaction', params: ['period'] },
  { id: 'salesman', title: 'Sale by User', group: 'Transaction', params: ['period'] },
  { id: 'exchange', title: 'Exchange Gain & Loss', group: 'Transaction', params: ['period'] },
  { id: 'party-statement', title: 'Party Statement', group: 'Party', params: ['party', 'period'] },
  { id: 'all-parties', title: 'All Parties', group: 'Party', params: [] },
  { id: 'ageing', title: 'Receivables Ageing', group: 'Party', params: [] },
  { id: 'ageing-payable', title: 'Payables Ageing', group: 'Party', params: [] },
  { id: 'loyalty', title: 'Loyalty Points', group: 'Party', params: [] },
  { id: 'party-profit', title: 'Party Wise Profit & Loss', group: 'Party', params: ['period'] },
  { id: 'party-item', title: 'Party Report by Item', group: 'Party', params: ['party?', 'period'] },
  { id: 'sale-by-party', title: 'Sale Purchase by Party', group: 'Party', params: ['period'] },
  { id: 'gstr1', title: 'GSTR-1 (Sales)', group: 'GST', params: ['period'] },
  { id: 'gstr3b', title: 'GSTR-3B Summary', group: 'GST', params: ['period'] },
  { id: 'gstr9', title: 'GSTR-9 (Annual Return)', group: 'GST', params: ['period'] },
  { id: 'hsn-summary', title: 'Sale Summary by HSN', group: 'GST', params: ['period'] },
  { id: 'gstr2', title: 'GSTR-2 (Purchases)', group: 'GST', params: ['period'] },
  { id: 'gst-rate', title: 'GST Rate Report', group: 'GST', params: ['period'] },
  { id: 'sac-summary', title: 'SAC Report (Services)', group: 'GST', params: ['period'] },
  { id: 'gst-by-party', title: 'GST Report by Party', group: 'GST', params: ['period'] },
  { id: 'tcs', title: 'TCS Report', group: 'GST', params: ['period'] },
  { id: 'tds', title: 'TDS Report', group: 'GST', params: ['period'] },
  { id: 'tcs-return', title: 'TCS Return (Form 143 / 27EQ details)', group: 'GST', params: ['period'] },
  { id: 'tds-return', title: 'TDS Return (Form 140 / 26Q details)', group: 'GST', params: ['period'] },
  { id: 'stock-summary', title: 'Stock Summary', group: 'Item / Stock', params: [] },
  { id: 'low-stock', title: 'Low Stock Summary', group: 'Item / Stock', params: [] },
  { id: 'stock-detail', title: 'Stock Detail', group: 'Item / Stock', params: ['period'] },
  { id: 'item-detail', title: 'Item Detail', group: 'Item / Stock', params: ['item', 'period'] },
  { id: 'stock-by-category', title: 'Stock Summary by Category', group: 'Item / Stock', params: [] },
  { id: 'godown-stock', title: 'Stock by Godown', group: 'Item / Stock', params: [] },
  { id: 'batch-stock', title: 'Batch Stock', group: 'Item / Stock', params: [] },
  { id: 'expiry', title: 'Expiry Report', group: 'Item / Stock', params: [] },
  { id: 'serial', title: 'Serial Number Report', group: 'Item / Stock', params: [] },
  { id: 'item-sale', title: 'Item Wise Sale', group: 'Item / Stock', params: ['period'] },
  { id: 'item-profit', title: 'Item Wise Profit & Loss', group: 'Item / Stock', params: ['period'] },
  { id: 'category-profit', title: 'Item Category Wise Profit & Loss', group: 'Item / Stock', params: ['period'] },
  { id: 'sale-by-category', title: 'Sale Purchase by Item Category', group: 'Item / Stock', params: ['period'] },
  { id: 'item-discount', title: 'Item Wise Discount', group: 'Item / Stock', params: ['period'] },
  { id: 'discount', title: 'Discount Report', group: 'Business Status', params: ['period'] },
  { id: 'expense', title: 'Expense Report', group: 'Business Status', params: ['period'] },
  { id: 'expense-transactions', title: 'Expense Transactions', group: 'Business Status', params: ['period'] },
  { id: 'expense-item', title: 'Expense Item Report', group: 'Business Status', params: ['period'] },
  { id: 'bank-statement', title: 'Bank Statement', group: 'Business Status', params: ['bank', 'period'] },
  { id: 'loan-statement', title: 'Loan Statement', group: 'Business Status', params: ['period'] },
];

const col = (key: string, label: string, type: ColumnType = 'text'): Column => ({ key, label, type });
const money = (label: string, value: number): Figure => ({ label, value: r2(value), type: 'money' });
const n = (v: string | number | null | undefined) => Number(v ?? 0);
const fmt = (iso: string) => iso.split('-').reverse().join('/');

@Injectable()
export class ReportsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly parties: PartiesService,
    private readonly firms: FirmService,
  ) {}

  async run(firmId: string, id: string, params: ReportParams): Promise<Report> {
    const def = REPORT_CATALOG.find((r) => r.id === id);
    if (!def) throw new NotFoundException({ code: 'REPORT_NOT_FOUND', message: 'Unknown report.' });
    const from = params.from ?? today().slice(0, 8) + '01';
    const to = params.to ?? today();
    if (from > to) throw new BadRequestException({ code: 'BAD_RANGE', message: 'The "from" date is after the "to" date.' });
    const period = `${fmt(from)} to ${fmt(to)}`;

    const body = await this.build(firmId, id, { ...params, from, to });
    // The body goes first: a builder may leave its subtitle undefined, which must not hide the default.
    return { ...body, id, title: def.title, subtitle: body.subtitle ?? (def.params.includes('period') ? period : `As of ${fmt(today())}`) };
  }

  private build(firmId: string, id: string, p: Required<Pick<ReportParams, 'from' | 'to'>> & ReportParams): Promise<ReportBody> {
    switch (id) {
      case 'sale':
        return this.invoiceRegister(firmId, 'sale', 'credit_note', p.from, p.to);
      case 'purchase':
        return this.invoiceRegister(firmId, 'purchase', 'debit_note', p.from, p.to);
      case 'day-book':
      case 'all-transactions':
        return this.allTransactions(firmId, p.from, p.to);
      case 'profit-loss':
        return this.profitAndLoss(firmId, p.from, p.to);
      case 'bill-wise-profit':
        return this.billWiseProfit(firmId, p.from, p.to);
      case 'cash-flow':
        return this.statement(firmId, { account: 'cash' }, p.from, p.to, 'Cash in hand');
      case 'bank-statement':
        return this.bankStatement(firmId, p.bankAccountId, p.from, p.to);
      case 'balance-sheet':
        return this.balanceSheet(firmId);
      case 'party-statement':
        return this.partyStatement(firmId, p.partyId, p.from, p.to);
      case 'all-parties':
        return this.allParties(firmId);
      case 'gstr1':
        return this.gstr1(firmId, p.from, p.to);
      case 'gstr3b':
        return this.gstr3b(firmId, p.from, p.to);
      case 'hsn-summary':
        return this.saleLinesBy(firmId, 'hsn', p.from, p.to);
      case 'gst-rate':
        return this.saleLinesBy(firmId, 'rate', p.from, p.to);
      case 'item-sale':
        return this.saleLinesBy(firmId, 'item', p.from, p.to);
      case 'stock-summary':
        return this.stock(firmId, false);
      case 'low-stock':
        return this.stock(firmId, true);
      case 'expense':
        return this.expenses(firmId, p.from, p.to);
      case 'trial-balance':
        return this.trialBalance(firmId);
      case 'exchange':
        return this.exchange(firmId, p.from, p.to);
      case 'tcs':
        return this.withheld(firmId, 'tcs', p.from, p.to);
      case 'tds':
        return this.withheld(firmId, 'tds', p.from, p.to);
      case 'godown-stock':
        return this.godownStock(firmId);
      case 'batch-stock':
        return this.batchStock(firmId, false);
      case 'expiry':
        return this.batchStock(firmId, true);
      case 'serial':
        return this.serials(firmId);
      case 'loyalty':
        return this.loyalty(firmId);
      case 'orders':
        return this.orders(firmId, p.from, p.to);
      case 'salesman':
        return this.salesman(firmId, p.from, p.to);
      case 'party-profit':
        return this.profitBy(firmId, 'party', p.from, p.to);
      case 'item-profit':
        return this.profitBy(firmId, 'item', p.from, p.to);
      case 'category-profit':
        return this.profitBy(firmId, 'category', p.from, p.to);
      case 'party-item':
        return this.salePurchaseBy(firmId, 'item', p.from, p.to, p.partyId);
      case 'sale-by-party':
        return this.salePurchaseBy(firmId, 'party', p.from, p.to);
      case 'sale-by-category':
        return this.salePurchaseBy(firmId, 'category', p.from, p.to);
      case 'gst-by-party':
        return this.gstByParty(firmId, p.from, p.to);
      case 'gstr2':
        return this.gstr2(firmId, p.from, p.to);
      case 'sac-summary':
        return this.saleLinesBy(firmId, 'sac', p.from, p.to);
      case 'stock-detail':
        return this.stockDetail(firmId, p.from, p.to);
      case 'item-detail':
        return this.itemDetail(firmId, p.itemId, p.from, p.to);
      case 'stock-by-category':
        return this.stockByCategory(firmId);
      case 'item-discount':
        return this.discounts(firmId, 'item', p.from, p.to);
      case 'discount':
        return this.discounts(firmId, 'party', p.from, p.to);
      case 'expense-transactions':
        return this.expenseTransactions(firmId, p.from, p.to);
      case 'expense-item':
        return this.expenseItems(firmId, p.from, p.to);
      case 'ageing':
        return this.ageing(firmId, 'sale');
      case 'ageing-payable':
        return this.ageing(firmId, 'purchase');
      case 'gstr9':
        return this.gstr9(firmId, p.from, p.to);
      case 'tcs-return':
        return this.deducteeReturn(firmId, 'tcs', p.from, p.to);
      case 'tds-return':
        return this.deducteeReturn(firmId, 'tds', p.from, p.to);
      case 'loan-statement':
        return this.loanStatement(firmId, p.from, p.to);
      default:
        throw new NotFoundException();
    }
  }

  private invoices(firmId: string, types: InvoiceType[], from: string, to: string) {
    return this.db
      .selectFrom('invoices')
      .selectAll()
      .where('firm_id', '=', firmId)
      .where('type', 'in', types)
      .where('deleted_at', 'is', null)
      .where('invoice_date', '>=', from)
      .where('invoice_date', '<=', to);
  }

  // ---------------------------------------------------------------- transaction reports

  /** Sale (or purchase) register; returns of that side are listed too and netted in the summary. */
  private async invoiceRegister(firmId: string, type: InvoiceType, returnType: InvoiceType, from: string, to: string) {
    // Paid = taken with the invoice plus later payments linked to it.
    const raw = await this.invoices(firmId, [type, returnType], from, to)
      .select(sql<string>`coalesce((select sum(a.amount) from payment_allocations a where a.invoice_id = invoices.id), 0)`.as('linked'))
      .orderBy('invoice_date')
      .orderBy('created_at')
      .execute();
    const rows = raw.map((r) => ({ ...r, received: String(r2(n(r.received) + n(r.linked))) }));
    const sign = (t: InvoiceType) => (t === type ? 1 : -1);
    const net = (pick: (r: (typeof rows)[number]) => number) => rows.reduce((s, r) => s + sign(r.type) * pick(r), 0);
    // TDS held back and loyalty points redeemed settle part of a bill without money moving.
    const unpaid = (r: (typeof rows)[number]) => r2(n(r.total) - n(r.received) - n(r.tds_amount) - n(r.loyalty_amount));
    const paid = type === 'sale' ? 'Received' : 'Paid';
    return {
      columns: [
        col('date', 'Date', 'date'), col('number', 'Number'), col('party', 'Party Name'), col('type', 'Type'),
        col('taxable', 'Taxable', 'money'), col('tax', 'Tax', 'money'), col('total', 'Total', 'money'),
        col('paid', paid, 'money'), col('balance', 'Balance', 'money'),
      ],
      rows: rows.map((r) => ({
        date: r.invoice_date, number: r.number, party: r.party_name, type: INVOICE_TYPES[r.type].label,
        taxable: n(r.taxable_amount), tax: r2(n(r.cgst) + n(r.sgst) + n(r.igst) + n(r.cess)), total: n(r.total),
        paid: n(r.received), balance: unpaid(r),
      })),
      summary: [
        money(`Total ${INVOICE_TYPES[type].label} (net of returns)`, net((r) => n(r.total))),
        money('Taxable', net((r) => n(r.taxable_amount))),
        money('Tax', net((r) => n(r.cgst) + n(r.sgst) + n(r.igst) + n(r.cess))),
        money(paid, net((r) => n(r.received))),
        money('Balance', net(unpaid)),
      ],
    };
  }

  /** Every posting document, payment and expense in the period, with the money that moved. */
  private async allTransactions(firmId: string, from: string, to: string) {
    const invoices = await this.invoices(firmId, POSTING_TYPES, from, to).execute();
    const payments = await this.db
      .selectFrom('payments as p')
      .innerJoin('parties as pa', 'pa.id', 'p.party_id')
      .select(['p.type', 'p.number', 'p.payment_date', 'p.amount', 'p.created_at', 'pa.name'])
      .where('p.firm_id', '=', firmId)
      .where('p.deleted_at', 'is', null)
      .where('p.payment_date', '>=', from)
      .where('p.payment_date', '<=', to)
      .execute();
    const expenses = await this.db
      .selectFrom('expenses as e')
      .innerJoin('expense_categories as c', 'c.id', 'e.category_id')
      .select(['e.number', 'e.expense_date', 'e.total', 'e.created_at', 'c.name'])
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null)
      .where('e.expense_date', '>=', from)
      .where('e.expense_date', '<=', to)
      .execute();

    type T = { date: string; at: Date; type: string; number: string | null; name: string; total: number; moneyIn: number; moneyOut: number };
    const all: T[] = [
      ...invoices.map((i) => {
        const flow = INVOICE_TYPES[i.type].balance * n(i.received);
        return {
          date: i.invoice_date, at: i.created_at, type: INVOICE_TYPES[i.type].label as string, number: i.number, name: i.party_name,
          total: n(i.total), moneyIn: Math.max(flow, 0), moneyOut: Math.max(-flow, 0),
        };
      }),
      ...payments.map((p) => ({
        date: p.payment_date, at: p.created_at, type: p.type === 'in' ? 'Payment-In' : 'Payment-Out', number: p.number, name: p.name,
        total: n(p.amount), moneyIn: p.type === 'in' ? n(p.amount) : 0, moneyOut: p.type === 'out' ? n(p.amount) : 0,
      })),
      ...expenses.map((e) => ({
        date: e.expense_date, at: e.created_at, type: 'Expense', number: e.number, name: e.name, total: n(e.total), moneyIn: 0, moneyOut: n(e.total),
      })),
    ].sort((a, b) => a.date.localeCompare(b.date) || a.at.getTime() - b.at.getTime());

    const moneyIn = all.reduce((s, t) => s + t.moneyIn, 0);
    const moneyOut = all.reduce((s, t) => s + t.moneyOut, 0);
    return {
      columns: [
        col('date', 'Date', 'date'), col('type', 'Type'), col('number', 'Ref No.'), col('name', 'Name'),
        col('total', 'Total', 'money'), col('moneyIn', 'Money In', 'money'), col('moneyOut', 'Money Out', 'money'),
      ],
      rows: all.map(({ at: _at, ...t }) => t),
      summary: [money('Money In', moneyIn), money('Money Out', moneyOut), money('Net', moneyIn - moneyOut)],
    };
  }

  /**
   * Stock value (quantity × purchase price) from all movements up to and including [date].
   * With [openingThrough], opening-stock entries dated up to that day are counted as well: stock
   * a business starts with is opening stock whenever it was keyed in, not profit made in the period.
   */
  private async stockValue(firmId: string, date: string, openingThrough?: string) {
    const row = await this.db
      .selectFrom('items as i')
      .innerJoin(
        (eb) =>
          eb
            .selectFrom('stock_movements')
            .select(['item_id', sql<string>`sum(qty_change)`.as('qty')])
            .where('firm_id', '=', firmId)
            .where((eb) =>
              eb.or([
                eb('movement_date', '<=', date),
                ...(openingThrough ? [eb.and([eb('type', '=', 'opening'), eb('movement_date', '<=', openingThrough)])] : []),
              ]),
            )
            .groupBy('item_id')
            .as('q'),
        (j) => j.onRef('q.item_id', '=', 'i.id'),
      )
      .select(sql<string>`coalesce(sum(q.qty * i.purchase_price), 0)`.as('value'))
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .where('i.type', '=', 'product')
      .executeTakeFirstOrThrow();
    return n(row.value);
  }

  private async profitAndLoss(firmId: string, from: string, to: string) {
    const totals = await this.invoices(firmId, POSTING_TYPES, from, to)
      .clearSelect()
      .select([
        'type', sql<string>`sum(taxable_amount)`.as('taxable'), sql<string>`sum(charges_total)`.as('charges'), sql<string>`sum(loyalty_amount)`.as('loyalty'),
      ])
      .groupBy('type')
      .execute();
    const of = (t: InvoiceType) => n(totals.find((r) => r.type === t)?.taxable);
    const chargesOf = (t: InvoiceType) => n(totals.find((r) => r.type === t)?.charges);
    // Freight, packing etc.: charged to customers (income) less charged by suppliers (cost), net of returns.
    const chargesNet = chargesOf('sale') - chargesOf('credit_note') - chargesOf('purchase') + chargesOf('debit_note');
    const loyalty = n(totals.find((r) => r.type === 'sale')?.loyalty);
    const exchange = await this.db
      .selectFrom('payments')
      .select(sql<string>`coalesce(sum(fx_gain), 0)`.as('gain'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where('payment_date', '>=', from)
      .where('payment_date', '<=', to)
      .executeTakeFirstOrThrow();
    const expenses = await this.db
      .selectFrom('expenses')
      // GST paid on expenses is input credit, not a cost — the same way sales and purchases are taken before tax.
      .select(sql<string>`coalesce(sum(total - tax_amount), 0)`.as('total'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where('expense_date', '>=', from)
      .where('expense_date', '<=', to)
      .executeTakeFirstOrThrow();
    const journal = await this.db
      .selectFrom('journal_lines as jl')
      .innerJoin('journal_entries as e', 'e.id', 'jl.entry_id')
      .innerJoin('ledger_accounts as a', 'a.id', 'jl.ledger_account_id')
      .select([
        sql<string>`coalesce(sum(jl.credit - jl.debit) filter (where a.type = 'income'), 0)`.as('income'),
        sql<string>`coalesce(sum(jl.debit - jl.credit) filter (where a.type = 'expense'), 0)`.as('expense'),
      ])
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null)
      .where('e.entry_date', '>=', from)
      .where('e.entry_date', '<=', to)
      .executeTakeFirstOrThrow();
    const loans = await this.db
      .selectFrom('loan_transactions')
      .select([
        sql<string>`coalesce(sum(interest), 0)`.as('interest'),
        sql<string>`coalesce(sum(principal) filter (where kind = 'charge'), 0)`.as('charges'),
      ])
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where('txn_date', '>=', from)
      .where('txn_date', '<=', to)
      .executeTakeFirstOrThrow();
    const dayBefore = new Date(new Date(from).getTime() - 86400000).toISOString().slice(0, 10);
    const openingStock = await this.stockValue(firmId, dayBefore, to);
    const closingStock = await this.stockValue(firmId, to);

    const netSale = of('sale') - of('credit_note');
    const netPurchase = of('purchase') - of('debit_note');
    const grossProfit = r2(netSale - netPurchase - openingStock + closingStock);
    const indirect = n(expenses.total) + n(loans.interest) + n(loans.charges) + n(journal.expense) + loyalty;
    const netProfit = r2(grossProfit - indirect + n(journal.income) + chargesNet + n(exchange.gain));

    const line = (particulars: string, amount: number | null, bold = false): Row => ({ particulars, amount, _bold: bold });
    return {
      columns: [col('particulars', 'Particulars'), col('amount', 'Amount', 'money')],
      rows: [
        line('Sale (+)', of('sale')),
        line('Credit Note / Sale Return (−)', of('credit_note')),
        line('Purchase (−)', of('purchase')),
        line('Debit Note / Purchase Return (+)', of('debit_note')),
        line('Opening Stock (−)', openingStock),
        line('Closing Stock (+)', closingStock),
        line('Gross Profit', grossProfit, true),
        line('Expenses (−)', n(expenses.total)),
        line('Loan Interest (−)', n(loans.interest)),
        line('Loan Charges (−)', n(loans.charges)),
        ...(chargesNet ? [line('Additional charges on bills, net (+)', r2(chargesNet))] : []),
        ...(loyalty ? [line('Loyalty points redeemed (−)', loyalty)] : []),
        ...(n(exchange.gain) ? [line(n(exchange.gain) >= 0 ? 'Exchange gain (+)' : 'Exchange loss (−)', Math.abs(n(exchange.gain)))] : []),
        ...(n(journal.income) || n(journal.expense)
          ? [line('Other Income, journal entries (+)', n(journal.income)), line('Other Expenses, journal entries (−)', n(journal.expense))]
          : []),
        line(netProfit >= 0 ? 'Net Profit' : 'Net Loss', netProfit, true),
      ],
      summary: [money('Gross Profit', grossProfit), money(netProfit >= 0 ? 'Net Profit' : 'Net Loss', netProfit)],
    };
  }

  /** Profit per sale invoice = taxable sale value − cost of the items at their current purchase price. */
  private async billWiseProfit(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('invoices as i')
      .leftJoin('invoice_items as l', 'l.invoice_id', 'i.id')
      .leftJoin('items as it', 'it.id', 'l.item_id')
      .select([
        'i.id', 'i.invoice_date', 'i.number', 'i.party_name', 'i.taxable_amount', 'i.created_at',
        sql<string>`coalesce(sum(l.quantity * coalesce(it.purchase_price, 0)), 0)`.as('cost'),
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.type', '=', 'sale')
      .where('i.deleted_at', 'is', null)
      .where('i.invoice_date', '>=', from)
      .where('i.invoice_date', '<=', to)
      .groupBy(['i.id', 'i.invoice_date', 'i.number', 'i.party_name', 'i.taxable_amount', 'i.created_at'])
      .orderBy('i.invoice_date')
      .orderBy('i.created_at')
      .execute();
    const data = rows.map((r) => ({
      date: r.invoice_date, number: r.number, party: r.party_name, sale: n(r.taxable_amount), cost: r2(n(r.cost)),
      profit: r2(n(r.taxable_amount) - n(r.cost)),
    }));
    return {
      columns: [
        col('date', 'Date', 'date'), col('number', 'Invoice No'), col('party', 'Party'),
        col('sale', 'Sale Amount', 'money'), col('cost', 'Cost', 'money'), col('profit', 'Profit', 'money'),
      ],
      rows: data,
      summary: [
        money('Sale Amount', data.reduce((s, r) => s + r.sale, 0)),
        money('Cost', data.reduce((s, r) => s + r.cost, 0)),
        money('Profit', data.reduce((s, r) => s + r.profit, 0)),
      ],
    };
  }

  /** Opening balance, every movement in the period with a running balance, and the closing balance. */
  private async statement(
    firmId: string,
    where: { account: 'cash' } | { bankAccountId: string; openingBalance: number },
    from: string,
    to: string,
    label: string,
  ) {
    let q = this.db.selectFrom('money_flows').selectAll().where('firm_id', '=', firmId);
    q = 'account' in where ? q.where('account', '=', 'cash') : q.where('bank_account_id', '=', where.bankAccountId);
    const flows = await q.orderBy('flow_date').orderBy('created_at').execute();

    let running = 'account' in where ? 0 : where.openingBalance;
    for (const f of flows.filter((f) => f.flow_date < from)) running += n(f.amount);
    const opening = r2(running);
    const rows: Row[] = [{ date: from, type: 'Opening Balance', name: '', moneyIn: null, moneyOut: null, balance: opening, _bold: true }];
    let totalIn = 0;
    let totalOut = 0;
    for (const f of flows.filter((f) => f.flow_date >= from && f.flow_date <= to)) {
      const amount = n(f.amount);
      running = r2(running + amount);
      if (amount >= 0) totalIn += amount;
      else totalOut -= amount;
      rows.push({
        date: f.flow_date, type: f.label, name: f.name ?? '', moneyIn: amount >= 0 ? amount : null, moneyOut: amount < 0 ? -amount : null, balance: running,
      });
    }
    rows.push({ date: to, type: 'Closing Balance', name: '', moneyIn: null, moneyOut: null, balance: r2(running), _bold: true });
    return {
      columns: [
        col('date', 'Date', 'date'), col('type', 'Type'), col('name', 'Name'),
        col('moneyIn', 'Money In', 'money'), col('moneyOut', 'Money Out', 'money'), col('balance', 'Running Balance', 'money'),
      ],
      rows,
      summary: [money(`Opening ${label}`, opening), money('Money In', totalIn), money('Money Out', totalOut), money(`Closing ${label}`, running)],
    };
  }

  private async bankStatement(firmId: string, bankAccountId: string | undefined, from: string, to: string) {
    if (!bankAccountId) throw new BadRequestException({ code: 'BANK_ACCOUNT_REQUIRED', message: 'Select a bank account.' });
    const account = await this.db
      .selectFrom('bank_accounts')
      .select(['name', 'opening_balance'])
      .where('id', '=', bankAccountId)
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    if (!account) throw new NotFoundException({ code: 'BANK_ACCOUNT_NOT_FOUND', message: 'Bank account not found.' });
    const body = await this.statement(firmId, { bankAccountId, openingBalance: n(account.opening_balance) }, from, to, 'balance');
    return { ...body, subtitle: `${account.name} · ${fmt(from)} to ${fmt(to)}` };
  }

  /** A snapshot of what the business owns and owes right now; equity is the balancing figure. */
  private async balanceSheet(firmId: string) {
    const money$ = await this.db
      .selectFrom('money_flows')
      .select([
        sql<string>`coalesce(sum(amount) filter (where account = 'cash'), 0)`.as('cash'),
        sql<string>`coalesce(sum(amount) filter (where account = 'bank'), 0)`.as('bank'),
        sql<string>`coalesce(sum(amount) filter (where account = 'cheque'), 0)`.as('cheques'),
      ])
      .where('firm_id', '=', firmId)
      .executeTakeFirstOrThrow();
    const bankOpening = await this.db
      .selectFrom('bank_accounts')
      .select(sql<string>`coalesce(sum(opening_balance), 0)`.as('total'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const balances = this.db
      .selectFrom('parties')
      .select(partyBalanceSql(sql.ref('parties.id'), sql.ref('parties.opening_balance')).as('balance'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .as('b');
    const partyTotals = await this.db
      .selectFrom(balances)
      .select([
        sql<string>`coalesce(sum(balance) filter (where balance > 0), 0)`.as('receivable'),
        sql<string>`coalesce(-sum(balance) filter (where balance < 0), 0)`.as('payable'),
      ])
      .executeTakeFirstOrThrow();
    const loans = await this.db
      .selectFrom('loan_accounts as l')
      .select(
        sql<string>`coalesce(sum(l.opening_balance + coalesce((
          select sum(case when t.kind = 'payment' then -t.principal else t.principal end)
            from loan_transactions t where t.loan_id = l.id and t.deleted_at is null), 0)), 0)`.as('total'),
      )
      .where('l.firm_id', '=', firmId)
      .where('l.deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const stock = await this.stockValue(firmId, '9999-12-31');
    const ledger = await this.ledgerBalances(firmId);
    const held = await this.db
      .selectFrom('invoices')
      .select([
        sql<string>`coalesce(sum(tds_amount) filter (where type = 'sale'), 0)`.as('tds_receivable'),
        sql<string>`coalesce(sum(tds_amount) filter (where type = 'purchase'), 0)`.as('tds_payable'),
        sql<string>`coalesce(sum(tcs_amount) filter (where type = 'purchase'), 0)`.as('tcs_receivable'),
        sql<string>`coalesce(sum(tcs_amount) filter (where type = 'sale'), 0)`.as('tcs_payable'),
      ])
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();

    const assets: Array<readonly [string, number]> = [
      ['Cash in hand', n(money$.cash)],
      ['Bank accounts', n(bankOpening.total) + n(money$.bank)],
      ['Undeposited cheques', n(money$.cheques)],
      ['Sundry debtors (receivable)', n(partyTotals.receivable)],
      ['Stock in hand', stock],
      ...(n(held.tds_receivable) ? [['TDS receivable', n(held.tds_receivable)] as const] : []),
      ...(n(held.tcs_receivable) ? [['TCS receivable', n(held.tcs_receivable)] as const] : []),
      ...ledger.filter((a) => a.type === 'asset' && a.balance !== 0).map((a) => [a.name, a.balance] as const),
    ];
    const liabilities: Array<readonly [string, number]> = [
      ['Sundry creditors (payable)', n(partyTotals.payable)],
      ['Loan accounts', n(loans.total)],
      ...(n(held.tds_payable) ? [['TDS payable', n(held.tds_payable)] as const] : []),
      ...(n(held.tcs_payable) ? [['TCS payable', n(held.tcs_payable)] as const] : []),
      ...ledger.filter((a) => a.type === 'liability' && a.balance !== 0).map((a) => [a.name, -a.balance] as const),
    ];
    const totalAssets = r2(assets.reduce((s, [, v]) => s + v, 0));
    const totalLiabilities = r2(liabilities.reduce((s, [, v]) => s + v, 0));
    const equity = r2(totalAssets - totalLiabilities);

    const line = (particulars: string, amount: number | null, bold = false): Row => ({ particulars, amount: amount === null ? null : r2(amount), _bold: bold });
    return {
      columns: [col('particulars', 'Particulars'), col('amount', 'Amount', 'money')],
      rows: [
        line('ASSETS', null, true),
        ...assets.map(([label, v]) => line(label, v)),
        line('Total Assets', totalAssets, true),
        line('LIABILITIES', null, true),
        ...liabilities.map(([label, v]) => line(label, v)),
        line('Total Liabilities', totalLiabilities, true),
        line("Owner's equity (assets − liabilities)", equity, true),
      ],
      summary: [money('Total Assets', totalAssets), money('Total Liabilities', totalLiabilities), money("Owner's Equity", equity)],
    };
  }

  // ---------------------------------------------------------------- party reports

  private async partyStatement(firmId: string, partyId: string | undefined, from: string, to: string) {
    if (!partyId) throw new BadRequestException({ code: 'PARTY_REQUIRED', message: 'Select a party.' });
    const party = await this.parties.get(firmId, partyId);
    const ledger = await this.parties.ledger(firmId, partyId);
    const opening = ledger.filter((e) => e.date < from).at(-1)?.balance ?? 0;
    const inPeriod = ledger.filter((e) => e.date >= from && e.date <= to);
    const closing = inPeriod.at(-1)?.balance ?? opening;
    // Debit = the party owes us more; credit = they owe us less.
    const rows: Row[] = [
      { date: from, type: 'Opening Balance', number: '', total: null, debit: null, credit: null, balance: opening, _bold: true },
      ...inPeriod.map((e) => ({
        date: e.date, type: e.type, number: e.number ?? '', total: e.total,
        debit: e.effect > 0 ? r2(e.effect) : null, credit: e.effect < 0 ? r2(-e.effect) : null, balance: e.balance,
      })),
      { date: to, type: 'Closing Balance', number: '', total: null, debit: null, credit: null, balance: closing, _bold: true },
    ];
    return {
      subtitle: `${party.name} · ${fmt(from)} to ${fmt(to)}`,
      columns: [
        col('date', 'Date', 'date'), col('type', 'Type'), col('number', 'Ref No.'), col('total', 'Total', 'money'),
        col('debit', 'Debit', 'money'), col('credit', 'Credit', 'money'), col('balance', 'Running Balance', 'money'),
      ],
      rows,
      summary: [
        money('Opening Balance', opening),
        money('Total Debit', inPeriod.reduce((s, e) => s + Math.max(e.effect, 0), 0)),
        money('Total Credit', inPeriod.reduce((s, e) => s + Math.max(-e.effect, 0), 0)),
        money(closing >= 0 ? 'Closing Balance (to receive)' : 'Closing Balance (to pay)', Math.abs(closing)),
      ],
    };
  }

  private async allParties(firmId: string) {
    const parties = await this.parties.list(firmId);
    const grouped = parties.some((p) => p.groupName);
    const rows = parties.map((p) => ({
      name: p.name, ...(grouped ? { group: p.groupName ?? '' } : {}), phone: p.phone ?? '', gstin: p.gstin ?? '',
      receivable: (p.balance ?? 0) > 0 ? p.balance : null, payable: (p.balance ?? 0) < 0 ? -(p.balance ?? 0) : null,
    }));
    return {
      columns: [col('name', 'Party Name'), ...(grouped ? [col('group', 'Group')] : []), col('phone', 'Phone'), col('gstin', 'GSTIN'), col('receivable', 'Receivable', 'money'), col('payable', 'Payable', 'money')],
      rows,
      summary: [
        { label: 'Parties', value: rows.length, type: 'number' as const },
        money('Total Receivable', rows.reduce((s, r) => s + (r.receivable ?? 0), 0)),
        money('Total Payable', rows.reduce((s, r) => s + (r.payable ?? 0), 0)),
      ],
    };
  }

  // ---------------------------------------------------------------- GST reports

  /** Outward supplies invoice by invoice; credit notes reduce the totals. */
  private gstr1(firmId: string, from: string, to: string) {
    return this.gstRegister(firmId, 'sale', 'credit_note', from, to);
  }

  /** Inward supplies bill by bill; debit notes (purchase returns) reduce the totals. */
  private gstr2(firmId: string, from: string, to: string) {
    return this.gstRegister(firmId, 'purchase', 'debit_note', from, to);
  }

  private async gstRegister(firmId: string, type: InvoiceType, returnType: InvoiceType, from: string, to: string) {
    const rows = await this.invoices(firmId, [type, returnType], from, to).orderBy('invoice_date').orderBy('created_at').execute();
    const sign = (t: InvoiceType) => (t === type ? 1 : -1);
    const data = rows.map((r) => ({
      date: r.invoice_date, number: r.number, type: INVOICE_TYPES[r.type].label, party: r.party_name, gstin: r.party_gstin ?? '',
      place: r.state_of_supply ? `${r.state_of_supply}-${GST_STATES[r.state_of_supply] ?? ''}` : '',
      taxable: sign(r.type) * n(r.taxable_amount), cgst: sign(r.type) * n(r.cgst), sgst: sign(r.type) * n(r.sgst),
      igst: sign(r.type) * n(r.igst), total: sign(r.type) * n(r.total),
    }));
    const sum = (k: 'taxable' | 'cgst' | 'sgst' | 'igst', filter: (r: (typeof data)[number]) => boolean = () => true) =>
      data.filter(filter).reduce((s, r) => s + r[k], 0);
    return {
      columns: [
        col('date', 'Date', 'date'), col('number', type === 'sale' ? 'Invoice No' : 'Bill No'), col('type', 'Type'), col('party', 'Party'), col('gstin', 'GSTIN'),
        col('place', 'Place of Supply'), col('taxable', 'Taxable Value', 'money'), col('cgst', 'CGST', 'money'), col('sgst', 'SGST', 'money'),
        col('igst', 'IGST', 'money'), col('total', 'Invoice Value', 'money'),
      ],
      rows: data,
      summary: [
        money(type === 'sale' ? 'B2B taxable (with GSTIN)' : 'From registered suppliers', sum('taxable', (r) => r.gstin !== '')),
        money(type === 'sale' ? 'B2C taxable (no GSTIN)' : 'From unregistered suppliers', sum('taxable', (r) => r.gstin === '')),
        money('CGST', sum('cgst')), money('SGST', sum('sgst')), money('IGST', sum('igst')),
        money('Total Tax', sum('cgst') + sum('sgst') + sum('igst')),
      ],
    };
  }

  /** Tax collected on sales against tax paid on purchases (input credit), net of returns. */
  private async gstr3b(firmId: string, from: string, to: string) {
    const totals = await this.invoices(firmId, POSTING_TYPES, from, to)
      .clearSelect()
      .select([
        'type',
        sql<string>`sum(taxable_amount)`.as('taxable'),
        sql<string>`sum(cgst)`.as('cgst'),
        sql<string>`sum(sgst)`.as('sgst'),
        sql<string>`sum(igst)`.as('igst'),
      ])
      .groupBy('type')
      .execute();
    const net = (plus: InvoiceType, minus: InvoiceType) => {
      const pick = (t: InvoiceType, k: 'taxable' | 'cgst' | 'sgst' | 'igst') => n(totals.find((r) => r.type === t)?.[k]);
      const v = (k: 'taxable' | 'cgst' | 'sgst' | 'igst') => r2(pick(plus, k) - pick(minus, k));
      return { taxable: v('taxable'), igst: v('igst'), cgst: v('cgst'), sgst: v('sgst') };
    };
    const out = net('sale', 'credit_note');
    const itc = net('purchase', 'debit_note');
    const expenseItc = await this.expenseItc(firmId, from, to);
    itc.igst = r2(itc.igst + expenseItc.igst);
    itc.cgst = r2(itc.cgst + expenseItc.cgst);
    itc.sgst = r2(itc.sgst + expenseItc.sgst);
    itc.taxable = r2(itc.taxable + expenseItc.taxable);
    const payable = { taxable: null, igst: r2(out.igst - itc.igst), cgst: r2(out.cgst - itc.cgst), sgst: r2(out.sgst - itc.sgst) };
    const withTotal = (particulars: string, v: { taxable: number | null; igst: number; cgst: number; sgst: number }, bold = false): Row => ({
      particulars, ...v, total: r2(v.igst + v.cgst + v.sgst), _bold: bold,
    });
    return {
      columns: [
        col('particulars', 'Particulars'), col('taxable', 'Taxable Value', 'money'), col('igst', 'IGST', 'money'),
        col('cgst', 'CGST', 'money'), col('sgst', 'SGST', 'money'), col('total', 'Total Tax', 'money'),
      ],
      rows: [
        withTotal('3.1 Outward taxable supplies (sales less returns)', out),
        withTotal('4. Eligible input tax credit (purchases less returns, and expenses)', itc),
        ...(expenseItc.igst + expenseItc.cgst + expenseItc.sgst ? [withTotal('    of which: GST paid on expenses', expenseItc)] : []),
        withTotal('Net GST payable (negative = credit carried forward)', payable, true),
      ],
      summary: [
        money('Output Tax', out.igst + out.cgst + out.sgst),
        money('Input Tax Credit', itc.igst + itc.cgst + itc.sgst),
        money('Net GST Payable', payable.igst + payable.cgst + payable.sgst),
      ],
    };
  }

  /**
   * GST paid on expenses in the period. An expense from a supplier in another state carries IGST; one from
   * the company's own state, or with no supplier state given, carries CGST + SGST in equal halves.
   */
  private async expenseItc(firmId: string, from: string, to: string) {
    const firm = await this.db.selectFrom('firms').select('state_code').where('id', '=', firmId).executeTakeFirstOrThrow();
    const rows = await this.db
      .selectFrom('expenses').select(['taxable_amount', 'tax_amount', 'supplier_state'])
      .where('firm_id', '=', firmId).where('deleted_at', 'is', null).where('tax_amount', '>', '0')
      .where('expense_date', '>=', from).where('expense_date', '<=', to).execute();
    const out = { taxable: 0, igst: 0, cgst: 0, sgst: 0 };
    for (const e of rows) {
      const tax = n(e.tax_amount);
      out.taxable += n(e.taxable_amount);
      if (e.supplier_state && firm.state_code && e.supplier_state !== firm.state_code) {
        out.igst += tax;
      } else {
        const half = r2(tax / 2);
        out.cgst += half;
        out.sgst += tax - half;
      }
    }
    return { taxable: r2(out.taxable), igst: r2(out.igst), cgst: r2(out.cgst), sgst: r2(out.sgst) };
  }

  /** Sale lines (less sale returns) grouped by HSN code, GST rate or item. */
  private async saleLinesBy(firmId: string, by: 'hsn' | 'sac' | 'rate' | 'item', from: string, to: string) {
    const key = by === 'hsn' || by === 'sac' ? sql<string>`coalesce(l.hsn_code, '')` : by === 'rate' ? sql<string>`l.gst_rate::text` : sql<string>`l.name`;
    const signed = (c: string) => sql<string>`sum(case when i.type = 'sale' then ${sql.ref(c)} else -${sql.ref(c)} end)`;
    const rows = await this.db
      .selectFrom('invoice_items as l')
      .innerJoin('invoices as i', 'i.id', 'l.invoice_id')
      .select([
        key.as('key'),
        signed('l.quantity').as('qty'), signed('l.taxable_value').as('taxable'), signed('l.cgst').as('cgst'),
        signed('l.sgst').as('sgst'), signed('l.igst').as('igst'), signed('l.amount').as('total'),
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.type', 'in', ['sale', 'credit_note'])
      .where('i.deleted_at', 'is', null)
      .where('i.invoice_date', '>=', from)
      .where('i.invoice_date', '<=', to)
      // The SAC report covers services only.
      .$if(by === 'sac', (q) => q.where(sql<boolean>`exists (select 1 from items it where it.id = l.item_id and it.type = 'service')`))
      .groupBy(key)
      .orderBy(key)
      .execute();
    const label = by === 'sac' ? 'SAC' : by === 'hsn' ? 'HSN/SAC' : by === 'rate' ? 'GST Rate' : 'Item';
    const data = rows.map((r) => ({
      key: by === 'rate' ? `${n(r.key)}%` : r.key || '(none)', qty: n(r.qty), taxable: n(r.taxable),
      cgst: n(r.cgst), sgst: n(r.sgst), igst: n(r.igst), total: n(r.total),
    }));
    return {
      columns: [
        col('key', label), col('qty', 'Quantity', 'qty'), col('taxable', 'Taxable Value', 'money'), col('cgst', 'CGST', 'money'),
        col('sgst', 'SGST', 'money'), col('igst', 'IGST', 'money'), col('total', 'Total', 'money'),
      ],
      rows: data,
      summary: [
        money('Taxable Value', data.reduce((s, r) => s + r.taxable, 0)),
        money('Total Tax', data.reduce((s, r) => s + r.cgst + r.sgst + r.igst, 0)),
        money('Total', data.reduce((s, r) => s + r.total, 0)),
      ],
    };
  }

  // ---------------------------------------------------------------- stock & expenses

  private async stock(firmId: string, lowOnly: boolean) {
    let q = this.db
      .selectFrom('items')
      .select(['name', 'item_code', 'unit', 'sale_price', 'purchase_price', 'stock_qty', 'min_stock'])
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where('type', '=', 'product');
    if (lowOnly) q = q.where(sql<boolean>`min_stock is not null and stock_qty <= min_stock`);
    const rows = await q.orderBy(sql`lower(name)`).execute();
    const data = rows.map((r) => ({
      name: r.name, code: r.item_code ?? '', unit: r.unit ?? '', salePrice: n(r.sale_price), purchasePrice: n(r.purchase_price),
      qty: n(r.stock_qty), ...(lowOnly ? { minStock: n(r.min_stock) } : {}), value: r2(n(r.stock_qty) * n(r.purchase_price)),
    }));
    return {
      columns: [
        col('name', 'Item Name'), col('code', 'Item Code'), col('unit', 'Unit'), col('salePrice', 'Sale Price', 'money'),
        col('purchasePrice', 'Purchase Price', 'money'), col('qty', 'Stock Qty', 'qty'),
        ...(lowOnly ? [col('minStock', 'Min Stock', 'qty')] : []), col('value', 'Stock Value', 'money'),
      ],
      rows: data,
      summary: [
        { label: 'Items', value: data.length, type: 'number' as const },
        { label: 'Total Quantity', value: data.reduce((s, r) => s + r.qty, 0), type: 'qty' as const },
        money('Stock Value', data.reduce((s, r) => s + r.value, 0)),
      ],
    };
  }

  private async expenses(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('expenses as e')
      .innerJoin('expense_categories as c', 'c.id', 'e.category_id')
      .select(['c.name', sql<string>`count(*)`.as('count'), sql<string>`sum(e.total)`.as('total')])
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null)
      .where('e.expense_date', '>=', from)
      .where('e.expense_date', '<=', to)
      .groupBy('c.name')
      .orderBy(sql`sum(e.total)`, 'desc')
      .execute();
    const data = rows.map((r) => ({ category: r.name, count: n(r.count), amount: n(r.total) }));
    return {
      columns: [col('category', 'Expense Category'), col('count', 'Entries', 'number'), col('amount', 'Amount', 'money')],
      rows: data,
      summary: [money('Total Expense', data.reduce((s, r) => s + r.amount, 0))],
    };
  }

  // ---------------------------------------------------------------- lines of posted documents

  /**
   * Every line of the sales, purchases and returns in the period. [side] says which side of the
   * business it belongs to and [sign] is −1 for returns, so sums come out net of returns.
   */
  private async lines(firmId: string, from: string, to: string, partyId?: string) {
    const rows = await this.db
      .selectFrom('invoice_items as l')
      .innerJoin('invoices as i', 'i.id', 'l.invoice_id')
      .leftJoin('items as it', 'it.id', 'l.item_id')
      .leftJoin('categories as c', 'c.id', 'it.category_id')
      .select([
        'l.name', 'l.quantity', 'l.price', 'l.taxable_value', 'l.discount_amount', 'l.bill_discount', 'l.cgst', 'l.sgst', 'l.igst', 'l.cess', 'l.amount',
        'i.type', 'i.party_id', 'i.party_name', 'it.purchase_price', 'c.name as category',
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.type', 'in', POSTING_TYPES)
      .where('i.deleted_at', 'is', null)
      .where('i.invoice_date', '>=', from)
      .where('i.invoice_date', '<=', to)
      .$if(!!partyId, (q) => q.where('i.party_id', '=', partyId!))
      .execute();
    return rows.map((r) => {
      const side: 'sale' | 'purchase' = r.type === 'sale' || r.type === 'credit_note' ? 'sale' : 'purchase';
      const sign = r.type === 'sale' || r.type === 'purchase' ? 1 : -1;
      return {
        side, sign, item: r.name, party: r.party_name, category: r.category ?? '(no category)', qty: sign * n(r.quantity),
        taxable: sign * n(r.taxable_value), tax: sign * (n(r.cgst) + n(r.sgst) + n(r.igst) + n(r.cess)), amount: sign * n(r.amount),
        // The line's own discount plus its share of any bill-level discount.
        discount: sign * (n(r.discount_amount) + n(r.bill_discount)), gross: sign * n(r.quantity) * n(r.price),
        // Cost of what was sold, at the item's current purchase price.
        cost: sign * n(r.quantity) * n(r.purchase_price),
      };
    });
  }

  private group<T, V>(rows: T[], key: (r: T) => string, make: () => V, add: (acc: V, r: T) => void): Array<[string, V]> {
    const map = new Map<string, V>();
    for (const r of rows) {
      if (!map.has(key(r))) map.set(key(r), make());
      add(map.get(key(r))!, r);
    }
    return [...map.entries()].sort((a, b) => a[0].toLowerCase().localeCompare(b[0].toLowerCase()));
  }

  /** Profit by party, item or item category: sale value before tax less the cost of what was sold. */
  private async profitBy(firmId: string, by: 'party' | 'item' | 'category', from: string, to: string) {
    const sales = (await this.lines(firmId, from, to)).filter((l) => l.side === 'sale');
    const data = this.group(sales, (l) => l[by], () => ({ qty: 0, sale: 0, cost: 0 }), (a, l) => {
      a.qty += l.qty;
      a.sale += l.taxable;
      a.cost += l.cost;
    }).map(([key, v]) => ({ key, qty: r2(v.qty), sale: r2(v.sale), cost: r2(v.cost), profit: r2(v.sale - v.cost) }));
    const label = by === 'party' ? 'Party Name' : by === 'item' ? 'Item Name' : 'Item Category';
    return {
      columns: [col('key', label), col('qty', 'Qty Sold', 'qty'), col('sale', 'Sale Amount', 'money'), col('cost', 'Cost', 'money'), col('profit', 'Profit', 'money')],
      rows: data,
      summary: [
        money('Sale Amount', data.reduce((s, r) => s + r.sale, 0)),
        money('Cost', data.reduce((s, r) => s + r.cost, 0)),
        money('Profit', data.reduce((s, r) => s + r.profit, 0)),
      ],
    };
  }

  /** Sale and purchase quantities and amounts side by side, by party, item or item category. */
  private async salePurchaseBy(firmId: string, by: 'party' | 'item' | 'category', from: string, to: string, partyId?: string) {
    const lines = await this.lines(firmId, from, to, partyId);
    const data = this.group(lines, (l) => l[by], () => ({ saleQty: 0, sale: 0, purchaseQty: 0, purchase: 0 }), (a, l) => {
      if (l.side === 'sale') {
        a.saleQty += l.qty;
        a.sale += l.amount;
      } else {
        a.purchaseQty += l.qty;
        a.purchase += l.amount;
      }
    }).map(([key, v]) => ({ key, saleQty: r2(v.saleQty), sale: r2(v.sale), purchaseQty: r2(v.purchaseQty), purchase: r2(v.purchase) }));
    const label = by === 'party' ? 'Party Name' : by === 'item' ? 'Item Name' : 'Item Category';
    let subtitle: string | undefined;
    if (partyId) subtitle = `${(await this.parties.get(firmId, partyId)).name} · ${fmt(from)} to ${fmt(to)}`;
    return {
      subtitle,
      columns: [
        col('key', label), col('saleQty', 'Sale Qty', 'qty'), col('sale', 'Sale Amount', 'money'),
        col('purchaseQty', 'Purchase Qty', 'qty'), col('purchase', 'Purchase Amount', 'money'),
      ],
      rows: data,
      summary: [money('Sale Amount', data.reduce((s, r) => s + r.sale, 0)), money('Purchase Amount', data.reduce((s, r) => s + r.purchase, 0))],
    };
  }

  /** Discount given on sales and received on purchases, by item or by party. */
  private async discounts(firmId: string, by: 'item' | 'party', from: string, to: string) {
    const lines = await this.lines(firmId, from, to);
    const data = this.group(lines, (l) => l[by], () => ({ qty: 0, gross: 0, sale: 0, purchase: 0 }), (a, l) => {
      if (l.side === 'sale') {
        a.qty += l.qty;
        a.gross += l.gross;
        a.sale += l.discount;
      } else {
        a.purchase += l.discount;
      }
    })
      .map(([key, v]) => ({
        key, qty: r2(v.qty), gross: r2(v.gross), saleDiscount: r2(v.sale), pct: v.gross ? r2((v.sale / v.gross) * 100) : 0, purchaseDiscount: r2(v.purchase),
      }))
      .filter((r) => r.saleDiscount !== 0 || r.purchaseDiscount !== 0);
    const totals = [money('Sale Discount', data.reduce((s, r) => s + r.saleDiscount, 0)), money('Purchase Discount', data.reduce((s, r) => s + r.purchaseDiscount, 0))];
    if (by === 'party') {
      return {
        columns: [col('key', 'Party Name'), col('saleDiscount', 'Sale Discount', 'money'), col('purchaseDiscount', 'Purchase Discount', 'money')],
        rows: data.map((r) => ({ key: r.key, saleDiscount: r.saleDiscount, purchaseDiscount: r.purchaseDiscount })),
        summary: totals,
      };
    }
    return {
      columns: [
        col('key', 'Item Name'), col('qty', 'Qty Sold', 'qty'), col('gross', 'Sale Before Discount', 'money'),
        col('saleDiscount', 'Discount Given', 'money'), col('pct', 'Avg Discount %', 'number'),
      ],
      rows: data.filter((r) => r.saleDiscount !== 0).map(({ purchaseDiscount: _p, ...r }) => r),
      summary: [totals[0]],
    };
  }

  /** Tax collected from and paid to each party. */
  private async gstByParty(firmId: string, from: string, to: string) {
    const lines = await this.lines(firmId, from, to);
    const data = this.group(lines, (l) => l.party, () => ({ saleTax: 0, purchaseTax: 0 }), (a, l) => {
      if (l.side === 'sale') a.saleTax += l.tax;
      else a.purchaseTax += l.tax;
    })
      .map(([key, v]) => ({ key, saleTax: r2(v.saleTax), purchaseTax: r2(v.purchaseTax) }))
      .filter((r) => r.saleTax !== 0 || r.purchaseTax !== 0);
    return {
      columns: [col('key', 'Party Name'), col('saleTax', 'Sale Tax', 'money'), col('purchaseTax', 'Purchase Tax', 'money')],
      rows: data,
      summary: [money('Tax Out (sales)', data.reduce((s, r) => s + r.saleTax, 0)), money('Tax In (purchases)', data.reduce((s, r) => s + r.purchaseTax, 0))],
    };
  }

  // ---------------------------------------------------------------- more transaction reports

  /** Estimates, orders, challans and proformas with whether each is still open. */
  private async orders(firmId: string, from: string, to: string) {
    const types = (Object.keys(INVOICE_TYPES) as InvoiceType[]).filter((t) => INVOICE_TYPES[t].balance === 0);
    const rows = await this.invoices(firmId, types, from, to).orderBy('invoice_date').orderBy('created_at').execute();
    const data = rows.map((r) => ({
      date: r.invoice_date, number: r.number, type: INVOICE_TYPES[r.type].label as string, party: r.party_name, total: n(r.total),
      status: r.converted_invoice_id ? 'Converted' : 'Open',
    }));
    return {
      columns: [col('date', 'Date', 'date'), col('number', 'Number'), col('type', 'Type'), col('party', 'Party Name'), col('total', 'Amount', 'money'), col('status', 'Status')],
      rows: data,
      summary: [
        { label: 'Open', value: data.filter((r) => r.status === 'Open').length, type: 'number' as const },
        money('Open Amount', data.filter((r) => r.status === 'Open').reduce((s, r) => s + r.total, 0)),
        { label: 'Converted', value: data.filter((r) => r.status === 'Converted').length, type: 'number' as const },
      ],
    };
  }

  /** What each user billed and collected: sales they entered and payments they received. */
  private async salesman(firmId: string, from: string, to: string) {
    const sales = await this.db
      .selectFrom('invoices as i')
      .leftJoin('users as u', 'u.id', 'i.created_by')
      .select([
        sql<string>`coalesce(u.full_name, '(not recorded)')`.as('name'),
        sql<string>`count(*)`.as('invoices'), sql<string>`sum(i.total)`.as('total'), sql<string>`sum(i.received)`.as('received'),
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.type', '=', 'sale')
      .where('i.deleted_at', 'is', null)
      .where('i.invoice_date', '>=', from)
      .where('i.invoice_date', '<=', to)
      .groupBy(sql`coalesce(u.full_name, '(not recorded)')`)
      .execute();
    const collected = await this.db
      .selectFrom('payments as p')
      .leftJoin('users as u', 'u.id', 'p.created_by')
      .select([sql<string>`coalesce(u.full_name, '(not recorded)')`.as('name'), sql<string>`sum(p.amount)`.as('amount')])
      .where('p.firm_id', '=', firmId)
      .where('p.type', '=', 'in')
      .where('p.deleted_at', 'is', null)
      .where('p.payment_date', '>=', from)
      .where('p.payment_date', '<=', to)
      .groupBy(sql`coalesce(u.full_name, '(not recorded)')`)
      .execute();
    const names = [...new Set([...sales.map((r) => r.name), ...collected.map((r) => r.name)])].sort((a, b) => a.localeCompare(b));
    const data = names.map((name) => {
      const s = sales.find((r) => r.name === name);
      const c = collected.find((r) => r.name === name);
      return {
        name, invoices: n(s?.invoices), sale: n(s?.total), received: n(s?.received), payments: n(c?.amount),
        collected: r2(n(s?.received) + n(c?.amount)),
      };
    });
    return {
      columns: [
        col('name', 'User'), col('invoices', 'Invoices', 'number'), col('sale', 'Sale Amount', 'money'), col('received', 'Received with Sale', 'money'),
        col('payments', 'Payment-In', 'money'), col('collected', 'Total Collected', 'money'),
      ],
      rows: data,
      summary: [money('Sale Amount', data.reduce((s, r) => s + r.sale, 0)), money('Total Collected', data.reduce((s, r) => s + r.collected, 0))],
    };
  }

  private async ledgerBalances(firmId: string) {
    const rows = await this.db
      .selectFrom('ledger_accounts as a')
      .select(['a.name', 'a.type'])
      .select(
        sql<string>`coalesce((select sum(jl.debit - jl.credit) from journal_lines jl join journal_entries e on e.id = jl.entry_id
                               where jl.ledger_account_id = a.id and e.deleted_at is null), 0)`.as('balance'),
      )
      .where('a.firm_id', '=', firmId)
      .where('a.deleted_at', 'is', null)
      .orderBy(sql`lower(a.name)`)
      .execute();
    return rows.map((a) => ({ name: a.name, type: a.type, balance: n(a.balance) }));
  }

  /**
   * All-time debit and credit balances of every head of account. The books are kept entry by entry
   * rather than as double-entry ledgers, so owner's capital is the figure that makes the two sides agree.
   */
  private async trialBalance(firmId: string) {
    const flows = await this.db
      .selectFrom('money_flows')
      .select([
        sql<string>`coalesce(sum(amount) filter (where account = 'cash'), 0)`.as('cash'),
        sql<string>`coalesce(sum(amount) filter (where account = 'cheque'), 0)`.as('cheques'),
      ])
      .where('firm_id', '=', firmId)
      .executeTakeFirstOrThrow();
    const banks = await this.db
      .selectFrom('bank_accounts as b')
      .select(['b.name'])
      .select(sql<string>`b.opening_balance + coalesce((select sum(f.amount) from money_flows f where f.bank_account_id = b.id and f.account = 'bank'), 0)`.as('balance'))
      .where('b.firm_id', '=', firmId)
      .where('b.deleted_at', 'is', null)
      .orderBy(sql`lower(b.name)`)
      .execute();
    const parties = await this.parties.list(firmId);
    const receivable = parties.reduce((s, p) => s + Math.max(p.balance ?? 0, 0), 0);
    const payable = parties.reduce((s, p) => s + Math.max(-(p.balance ?? 0), 0), 0);
    const totals = await this.db
      .selectFrom('invoices')
      .select([
        'type', sql<string>`sum(taxable_amount)`.as('taxable'), sql<string>`sum(cgst + sgst + igst + cess)`.as('tax'), sql<string>`sum(round_off)`.as('round_off'),
        sql<string>`sum(charges_total)`.as('charges'), sql<string>`sum(tcs_amount)`.as('tcs'), sql<string>`sum(tds_amount)`.as('tds'),
        sql<string>`sum(loyalty_amount)`.as('loyalty'),
      ])
      .where('firm_id', '=', firmId)
      .where('type', 'in', POSTING_TYPES)
      .where('deleted_at', 'is', null)
      .groupBy('type')
      .execute();
    const of = (t: InvoiceType, k: 'taxable' | 'tax' | 'round_off' | 'charges' | 'tcs' | 'tds' | 'loyalty') => n(totals.find((r) => r.type === t)?.[k]);
    const fxGain = await this.db
      .selectFrom('payments')
      .select(sql<string>`coalesce(sum(fx_gain), 0)`.as('gain'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const expenses = await this.db
      .selectFrom('expenses')
      .select([sql<string>`coalesce(sum(total - tax_amount), 0)`.as('net'), sql<string>`coalesce(sum(tax_amount), 0)`.as('tax')])
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const loanCosts = await this.db
      .selectFrom('loan_transactions')
      .select(sql<string>`coalesce(sum(interest), 0) + coalesce(sum(principal) filter (where kind = 'charge'), 0)`.as('total'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const loans = await this.db
      .selectFrom('loan_accounts as l')
      .select(
        sql<string>`coalesce(sum(l.opening_balance + coalesce((
          select sum(case when t.kind = 'payment' then -t.principal else t.principal end)
            from loan_transactions t where t.loan_id = l.id and t.deleted_at is null), 0)), 0)`.as('total'),
      )
      .where('l.firm_id', '=', firmId)
      .where('l.deleted_at', 'is', null)
      .executeTakeFirstOrThrow();
    const ledger = await this.ledgerBalances(firmId);

    const outputTax = of('sale', 'tax') - of('credit_note', 'tax');
    const inputTax = of('purchase', 'tax') - of('debit_note', 'tax') + n(expenses.tax);
    // Positive = debit balance, negative = credit balance.
    const heads: Array<[string, number]> = [
      ['Cash in hand', n(flows.cash)],
      ...banks.map((b) => [`Bank: ${b.name}`, n(b.balance)] as [string, number]),
      ['Undeposited cheques', n(flows.cheques)],
      ['Sundry debtors', receivable],
      ['Sundry creditors', -payable],
      ['Sales', -(of('sale', 'taxable') - of('credit_note', 'taxable'))],
      ['Purchases', of('purchase', 'taxable') - of('debit_note', 'taxable')],
      ['Expenses', n(expenses.net)],
      ['Loan interest and charges', n(loanCosts.total)],
      ['GST collected on sales (output tax)', -outputTax],
      ['GST paid on purchases and expenses (input tax)', inputTax],
      ['Round off', of('purchase', 'round_off') - of('debit_note', 'round_off') - of('sale', 'round_off') + of('credit_note', 'round_off')],
      ['Additional charges on bills (net)', of('purchase', 'charges') - of('debit_note', 'charges') - of('sale', 'charges') + of('credit_note', 'charges')],
      ['TCS collected on sales (payable)', -of('sale', 'tcs')],
      ['TCS paid on purchases (receivable)', of('purchase', 'tcs')],
      ['TDS deducted by customers (receivable)', of('sale', 'tds')],
      ['TDS deducted from suppliers (payable)', -of('purchase', 'tds')],
      ['Loyalty points redeemed', of('sale', 'loyalty')],
      ['Exchange gain / loss', -n(fxGain.gain)],
      ['Loan accounts', -n(loans.total)],
      ...ledger.map((a) => [a.name, a.balance] as [string, number]),
    ];
    const used = heads.map(([name, v]) => [name, r2(v)] as [string, number]).filter(([, v]) => v !== 0);
    const difference = r2(used.reduce((s, [, v]) => s + v, 0));
    if (difference !== 0) used.push(["Owner's capital and opening balances (balancing figure)", -difference]);
    const rows: Row[] = used.map(([particulars, v]) => ({ particulars, debit: v > 0 ? v : null, credit: v < 0 ? -v : null }));
    const totalDebit = r2(used.reduce((s, [, v]) => s + Math.max(v, 0), 0));
    const totalCredit = r2(used.reduce((s, [, v]) => s + Math.max(-v, 0), 0));
    rows.push({ particulars: 'Total', debit: totalDebit, credit: totalCredit, _bold: true });
    return {
      columns: [col('particulars', 'Account'), col('debit', 'Debit', 'money'), col('credit', 'Credit', 'money')],
      rows,
      summary: [money('Total Debit', totalDebit), money('Total Credit', totalCredit)],
    };
  }

  // ---------------------------------------------------------------- more stock reports

  /** Opening quantity, what came in and went out in the period, and the closing quantity of every product. */
  private async stockDetail(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('items as i')
      .leftJoin('stock_movements as m', 'm.item_id', 'i.id')
      .select([
        'i.name', 'i.unit', 'i.purchase_price',
        sql<string>`coalesce(sum(m.qty_change) filter (where m.movement_date < ${from}), 0)`.as('opening'),
        sql<string>`coalesce(sum(m.qty_change) filter (where m.movement_date between ${from} and ${to} and m.qty_change > 0), 0)`.as('qty_in'),
        sql<string>`coalesce(-sum(m.qty_change) filter (where m.movement_date between ${from} and ${to} and m.qty_change < 0), 0)`.as('qty_out'),
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .where('i.type', '=', 'product')
      .groupBy(['i.id', 'i.name', 'i.unit', 'i.purchase_price'])
      .orderBy(sql`lower(i.name)`)
      .execute();
    const data = rows.map((r) => {
      const closing = r2(n(r.opening) + n(r.qty_in) - n(r.qty_out));
      return { name: r.name, unit: r.unit ?? '', opening: n(r.opening), qtyIn: n(r.qty_in), qtyOut: n(r.qty_out), closing, value: r2(closing * n(r.purchase_price)) };
    });
    return {
      columns: [
        col('name', 'Item Name'), col('unit', 'Unit'), col('opening', 'Opening Qty', 'qty'), col('qtyIn', 'Qty In', 'qty'),
        col('qtyOut', 'Qty Out', 'qty'), col('closing', 'Closing Qty', 'qty'), col('value', 'Closing Value', 'money'),
      ],
      rows: data,
      summary: [
        { label: 'Qty In', value: r2(data.reduce((s, r) => s + r.qtyIn, 0)), type: 'qty' as const },
        { label: 'Qty Out', value: r2(data.reduce((s, r) => s + r.qtyOut, 0)), type: 'qty' as const },
        money('Closing Value', data.reduce((s, r) => s + r.value, 0)),
      ],
    };
  }

  /** One item's stock movements in the period with the quantity after each. */
  private async itemDetail(firmId: string, itemId: string | undefined, from: string, to: string) {
    if (!itemId) throw new BadRequestException({ code: 'ITEM_REQUIRED', message: 'Select an item.' });
    const item = await this.db.selectFrom('items').select(['name', 'unit']).where('id', '=', itemId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!item) throw new NotFoundException({ code: 'ITEM_NOT_FOUND', message: 'Item not found.' });
    const moves = await this.db
      .selectFrom('stock_movements as m')
      .leftJoin('invoices as i', 'i.id', 'm.invoice_id')
      .select(['m.type', 'm.qty_change', 'm.movement_date', 'm.notes', 'i.number', 'i.party_name'])
      .where('m.item_id', '=', itemId)
      .orderBy('m.movement_date')
      .orderBy(sql`m.type <> 'opening'`)
      .orderBy('m.created_at')
      .execute();
    const labels: Record<string, string> = {
      opening: 'Opening Stock', add: 'Stock Added', reduce: 'Stock Reduced', sale: 'Sale', purchase: 'Purchase', credit_note: 'Credit Note', debit_note: 'Debit Note',
      manufacture_in: 'Manufactured', manufacture_out: 'Used in Production',
    };
    let running = moves.filter((m) => m.movement_date < from).reduce((s, m) => s + n(m.qty_change), 0);
    const opening = r2(running);
    const rows: Row[] = [{ date: from, type: 'Opening Quantity', ref: '', name: '', qtyIn: null, qtyOut: null, closing: opening, _bold: true }];
    let totalIn = 0;
    let totalOut = 0;
    for (const m of moves.filter((m) => m.movement_date >= from && m.movement_date <= to)) {
      const q = n(m.qty_change);
      running = r2(running + q);
      if (q >= 0) totalIn += q;
      else totalOut -= q;
      rows.push({
        date: m.movement_date, type: labels[m.type] ?? m.type, ref: m.number ?? '', name: m.party_name ?? m.notes ?? '',
        qtyIn: q >= 0 ? q : null, qtyOut: q < 0 ? -q : null, closing: running,
      });
    }
    rows.push({ date: to, type: 'Closing Quantity', ref: '', name: '', qtyIn: null, qtyOut: null, closing: r2(running), _bold: true });
    return {
      subtitle: `${item.name}${item.unit ? ` (${item.unit})` : ''} · ${fmt(from)} to ${fmt(to)}`,
      columns: [
        col('date', 'Date', 'date'), col('type', 'Type'), col('ref', 'Ref No.'), col('name', 'Party / Notes'),
        col('qtyIn', 'Qty In', 'qty'), col('qtyOut', 'Qty Out', 'qty'), col('closing', 'Closing Qty', 'qty'),
      ],
      rows,
      summary: [
        { label: 'Opening', value: opening, type: 'qty' as const },
        { label: 'Qty In', value: r2(totalIn), type: 'qty' as const },
        { label: 'Qty Out', value: r2(totalOut), type: 'qty' as const },
        { label: 'Closing', value: r2(running), type: 'qty' as const },
      ],
    };
  }

  private async stockByCategory(firmId: string) {
    const rows = await this.db
      .selectFrom('items as i')
      .leftJoin('categories as c', 'c.id', 'i.category_id')
      .select([
        sql<string>`coalesce(c.name, '(no category)')`.as('category'), sql<string>`count(*)`.as('items'),
        sql<string>`sum(i.stock_qty)`.as('qty'), sql<string>`sum(i.stock_qty * i.purchase_price)`.as('value'),
      ])
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .where('i.type', '=', 'product')
      .groupBy(sql`coalesce(c.name, '(no category)')`)
      .orderBy(sql`lower(coalesce(c.name, '(no category)'))`)
      .execute();
    const data = rows.map((r) => ({ category: r.category, items: n(r.items), qty: n(r.qty), value: r2(n(r.value)) }));
    return {
      columns: [col('category', 'Item Category'), col('items', 'Items', 'number'), col('qty', 'Stock Qty', 'qty'), col('value', 'Stock Value', 'money')],
      rows: data,
      summary: [
        { label: 'Total Quantity', value: r2(data.reduce((s, r) => s + r.qty, 0)), type: 'qty' as const },
        money('Stock Value', data.reduce((s, r) => s + r.value, 0)),
      ],
    };
  }

  // ---------------------------------------------------------------- more expense reports

  private async expenseTransactions(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('expenses as e')
      .innerJoin('expense_categories as c', 'c.id', 'e.category_id')
      .select(['e.expense_date', 'e.number', 'e.payment_mode', 'e.taxable_amount', 'e.tax_amount', 'e.total', 'c.name'])
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null)
      .where('e.expense_date', '>=', from)
      .where('e.expense_date', '<=', to)
      .orderBy('e.expense_date')
      .orderBy('e.created_at')
      .execute();
    const data = rows.map((r) => ({
      date: r.expense_date, category: r.name, number: r.number ?? '', mode: r.payment_mode.toUpperCase(), taxable: n(r.taxable_amount), tax: n(r.tax_amount), total: n(r.total),
    }));
    return {
      columns: [
        col('date', 'Date', 'date'), col('category', 'Expense Category'), col('number', 'Exp No.'), col('mode', 'Payment'),
        col('taxable', 'Before Tax', 'money'), col('tax', 'GST', 'money'), col('total', 'Total', 'money'),
      ],
      rows: data,
      summary: [
        money('Before Tax', data.reduce((s, r) => s + r.taxable, 0)),
        money('GST', data.reduce((s, r) => s + r.tax, 0)),
        money('Total Expense', data.reduce((s, r) => s + r.total, 0)),
      ],
    };
  }

  private async expenseItems(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('expense_items as l')
      .innerJoin('expenses as e', 'e.id', 'l.expense_id')
      .select([
        sql<string>`min(l.name)`.as('name'), sql<string>`sum(l.quantity)`.as('qty'), sql<string>`sum(l.tax)`.as('tax'), sql<string>`sum(l.amount)`.as('amount'),
      ])
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null)
      .where('e.expense_date', '>=', from)
      .where('e.expense_date', '<=', to)
      .groupBy(sql`lower(l.name)`)
      .orderBy(sql`sum(l.amount)`, 'desc')
      .execute();
    const data = rows.map((r) => ({ name: r.name, qty: n(r.qty), tax: n(r.tax), amount: n(r.amount) }));
    return {
      columns: [col('name', 'Expense Item'), col('qty', 'Quantity', 'qty'), col('tax', 'GST', 'money'), col('amount', 'Amount', 'money')],
      rows: data,
      summary: [money('GST', data.reduce((s, r) => s + r.tax, 0)), money('Total', data.reduce((s, r) => s + r.amount, 0))],
    };
  }

  // ---------------------------------------------------------------- godowns, batches, serial numbers

  private async godownStock(firmId: string) {
    const rows = await sql<{ godown: string; item: string; unit: string | null; qty: string; purchase_price: string }>`
      select coalesce(g.name, 'Main Store') as godown, i.name as item, i.unit, sum(m.qty_change) as qty, i.purchase_price
        from stock_movements m join items i on i.id = m.item_id left join godowns g on g.id = m.godown_id
       where m.firm_id = ${firmId} and i.deleted_at is null and i.type = 'product'
       group by g.name, m.godown_id, i.id having sum(m.qty_change) <> 0
       order by (m.godown_id is not null), lower(coalesce(g.name, '')), lower(i.name)`.execute(this.db);
    const data = rows.rows.map((r) => ({ godown: r.godown, item: r.item, unit: r.unit ?? '', qty: n(r.qty), value: r2(n(r.qty) * n(r.purchase_price)) }));
    return {
      columns: [col('godown', 'Godown'), col('item', 'Item Name'), col('unit', 'Unit'), col('qty', 'Stock Qty', 'qty'), col('value', 'Stock Value', 'money')],
      rows: data,
      summary: [
        { label: 'Godowns', value: new Set(data.map((r) => r.godown)).size, type: 'number' as const },
        money('Stock Value', data.reduce((s, r) => s + r.value, 0)),
      ],
    };
  }

  /** Stock per batch; with [expiringOnly], just the batches already expired or expiring within 90 days. */
  private async batchStock(firmId: string, expiringOnly: boolean) {
    const rows = await sql<{ item: string; unit: string | null; batch_no: string; expiry_date: string | null; godown: string; qty: string; purchase_price: string }>`
      select i.name as item, i.unit, m.batch_no, max(m.expiry_date) as expiry_date, coalesce(g.name, 'Main Store') as godown, sum(m.qty_change) as qty, i.purchase_price
        from stock_movements m join items i on i.id = m.item_id left join godowns g on g.id = m.godown_id
       where m.firm_id = ${firmId} and i.deleted_at is null and m.batch_no is not null
       group by i.id, m.batch_no, m.godown_id, g.name having sum(m.qty_change) <> 0
       order by max(m.expiry_date) nulls last, lower(i.name), m.batch_no`.execute(this.db);
    const now = today();
    const data = rows.rows
      .map((r) => {
        const days = r.expiry_date ? Math.round((Date.parse(r.expiry_date) - Date.parse(now)) / 86400000) : null;
        return {
          item: r.item, batch: r.batch_no, expiry: r.expiry_date, godown: r.godown, qty: n(r.qty), value: r2(n(r.qty) * n(r.purchase_price)),
          status: days === null ? '' : days < 0 ? `Expired ${-days} days ago` : days === 0 ? 'Expires today' : `${days} days left`, days,
        };
      })
      .filter((r) => !expiringOnly || (r.days !== null && r.days <= 90));
    return {
      subtitle: expiringOnly ? `Expired or expiring within 90 days of ${fmt(now)}` : undefined,
      columns: [
        col('item', 'Item Name'), col('batch', 'Batch No.'), col('expiry', 'Expiry', 'date'), col('godown', 'Godown'), col('qty', 'Stock Qty', 'qty'),
        col('value', 'Stock Value', 'money'), col('status', 'Status'),
      ],
      rows: data.map(({ days: _days, ...r }) => r),
      summary: [
        { label: 'Batches', value: data.length, type: 'number' as const },
        money('Stock Value', data.reduce((s, r) => s + r.value, 0)),
        ...(expiringOnly ? [{ label: 'Already expired', value: data.filter((r) => (r.days ?? 0) < 0).length, type: 'number' as const }] : []),
      ],
    };
  }

  /** Every serial number seen, whether it is in stock, and the last document it was on. */
  private async serials(firmId: string) {
    const lines = await this.db
      .selectFrom('invoice_items as l')
      .innerJoin('invoices as i', 'i.id', 'l.invoice_id')
      .select(['l.name', 'l.serial_nos', 'i.type', 'i.number', 'i.party_name', 'i.invoice_date', 'i.created_at'])
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .where('i.type', 'in', POSTING_TYPES)
      .where('l.serial_nos', 'is not', null)
      .orderBy('i.invoice_date')
      .orderBy('i.created_at')
      .execute();
    const bySerial = new Map<string, { item: string; serial: string; net: number; date: string; doc: string; party: string }>();
    for (const l of lines) {
      const sign = INVOICE_TYPES[l.type].stock;
      for (const serial of (l.serial_nos ?? '').split(',').map((v) => v.trim()).filter(Boolean)) {
        const key = `${l.name}\u0000${serial}`;
        const entry = bySerial.get(key) ?? { item: l.name, serial, net: 0, date: '', doc: '', party: '' };
        // Lines come in date order, so the last one seen is the latest document.
        bySerial.set(key, { ...entry, net: entry.net + sign, date: l.invoice_date, doc: `${INVOICE_TYPES[l.type].label} ${l.number}`.trim(), party: l.party_name });
      }
    }
    const data = [...bySerial.values()]
      .sort((a, b) => a.item.localeCompare(b.item) || a.serial.localeCompare(b.serial))
      .map((e) => ({ item: e.item, serial: e.serial, status: e.net > 0 ? 'In stock' : 'Sold', date: e.date, doc: e.doc, party: e.party }));
    return {
      columns: [col('item', 'Item Name'), col('serial', 'Serial No.'), col('status', 'Status'), col('date', 'Last Date', 'date'), col('doc', 'Last Document'), col('party', 'Party')],
      rows: data,
      summary: [
        { label: 'In stock', value: data.filter((r) => r.status === 'In stock').length, type: 'number' as const },
        { label: 'Sold', value: data.filter((r) => r.status === 'Sold').length, type: 'number' as const },
      ],
    };
  }

  // ---------------------------------------------------------------- TCS / TDS, loyalty, exchange

  /** Bills carrying TCS (collected on sales, paid on purchases) or TDS (held back by the payer). */
  private async withheld(firmId: string, kind: 'tcs' | 'tds', from: string, to: string) {
    const rows = (await this.invoices(firmId, ['sale', 'purchase'], from, to).orderBy('invoice_date').orderBy('created_at').execute()).filter(
      (r) => n(kind === 'tcs' ? r.tcs_amount : r.tds_amount) > 0,
    );
    const data = rows.map((r) => ({
      date: r.invoice_date, number: r.number, type: INVOICE_TYPES[r.type].label as string, party: r.party_name, gstin: r.party_gstin ?? '',
      base: kind === 'tcs' ? r2(n(r.subtotal) + n(r.charges_total)) : n(r.taxable_amount),
      rate: n(kind === 'tcs' ? r.tcs_rate : r.tds_rate), amount: n(kind === 'tcs' ? r.tcs_amount : r.tds_amount),
    }));
    const of = (type: string) => data.filter((r) => r.type === type).reduce((s, r) => s + r.amount, 0);
    return {
      columns: [
        col('date', 'Date', 'date'), col('number', 'Number'), col('type', 'Type'), col('party', 'Party Name'), col('gstin', 'GSTIN'),
        col('base', kind === 'tcs' ? 'Bill Value' : 'Taxable Value', 'money'), col('rate', 'Rate %', 'number'), col('amount', kind.toUpperCase(), 'money'),
      ],
      rows: data,
      summary:
        kind === 'tcs'
          ? [money('TCS collected on sales (payable)', of('Sale')), money('TCS paid on purchases (receivable)', of('Purchase'))]
          : [money('TDS deducted by customers (receivable)', of('Sale')), money('TDS deducted from suppliers (payable)', of('Purchase'))],
    };
  }

  private async loyalty(firmId: string) {
    const rows = await sql<{ name: string; phone: string | null; opening: number; earned: string; redeemed: string; amount: string }>`
      select p.name, p.phone, p.loyalty_opening as opening, coalesce(sum(i.loyalty_earned), 0) as earned, coalesce(sum(i.loyalty_redeemed), 0) as redeemed,
             coalesce(sum(i.loyalty_amount), 0) as amount
        from parties p left join invoices i on i.party_id = p.id and i.type = 'sale' and i.deleted_at is null
       where p.firm_id = ${firmId} and p.deleted_at is null
       group by p.id having p.loyalty_opening <> 0 or coalesce(sum(i.loyalty_earned), 0) <> 0 or coalesce(sum(i.loyalty_redeemed), 0) <> 0
       order by lower(p.name)`.execute(this.db);
    const data = rows.rows.map((r) => ({
      name: r.name, phone: r.phone ?? '', opening: n(r.opening), earned: n(r.earned), redeemed: n(r.redeemed), value: n(r.amount),
      balance: n(r.opening) + n(r.earned) - n(r.redeemed),
    }));
    return {
      columns: [
        col('name', 'Party Name'), col('phone', 'Phone'), col('opening', 'Opening Points', 'number'), col('earned', 'Earned', 'number'),
        col('redeemed', 'Redeemed', 'number'), col('value', 'Redeemed Value', 'money'), col('balance', 'Points Balance', 'number'),
      ],
      rows: data,
      summary: [
        { label: 'Points outstanding', value: data.reduce((s, r) => s + r.balance, 0), type: 'number' as const },
        money('Redeemed Value', data.reduce((s, r) => s + r.value, 0)),
      ],
    };
  }

  /** Foreign-currency payments and what each gained or lost against the rates its invoices were booked at. */
  private async exchange(firmId: string, from: string, to: string) {
    const rows = await this.db
      .selectFrom('payments as p')
      .innerJoin('parties as pa', 'pa.id', 'p.party_id')
      .select(['p.payment_date', 'p.number', 'p.type', 'p.currency_code', 'p.fx_amount', 'p.exchange_rate', 'p.amount', 'p.fx_gain', 'pa.name'])
      .where('p.firm_id', '=', firmId)
      .where('p.deleted_at', 'is', null)
      .where('p.currency_code', 'is not', null)
      .where('p.payment_date', '>=', from)
      .where('p.payment_date', '<=', to)
      .orderBy('p.payment_date')
      .orderBy('p.created_at')
      .execute();
    const data = rows.map((r) => ({
      date: r.payment_date, number: r.number, type: r.type === 'in' ? 'Payment-In' : 'Payment-Out', party: r.name, currency: r.currency_code ?? '',
      fx: n(r.fx_amount), rate: n(r.exchange_rate), amount: n(r.amount), gain: n(r.fx_gain),
    }));
    const total = data.reduce((s, r) => s + r.gain, 0);
    return {
      columns: [
        col('date', 'Date', 'date'), col('number', 'Receipt No.'), col('type', 'Type'), col('party', 'Party Name'), col('currency', 'Currency'),
        col('fx', 'Amount', 'number'), col('rate', 'Rate', 'number'), col('amount', 'In Rupees', 'money'), col('gain', 'Gain (+) / Loss (−)', 'money'),
      ],
      rows: data,
      summary: [money(total >= 0 ? 'Net Exchange Gain' : 'Net Exchange Loss', Math.abs(total))],
    };
  }

  // ---------------------------------------------------------------- ageing, annual and deductee returns, loans

  /**
   * What each party still owes on unpaid invoices (or is owed on unpaid bills), by how long past the due
   * date it is. An invoice without a due date counts from its own date. Payments not linked to any invoice
   * are shown separately, since they are not set against a particular bucket.
   */
  private async ageing(firmId: string, type: 'sale' | 'purchase') {
    const rows = await sql<{ party_id: string; name: string; invoice_date: string; due_date: string | null; due: string }>`
      select p.id as party_id, p.name, i.invoice_date, i.due_date,
             i.total - i.received - i.tds_amount - i.loyalty_amount
               - coalesce((select sum(a.amount) from payment_allocations a where a.invoice_id = i.id), 0) as due
        from invoices i join parties p on p.id = i.party_id
       where i.firm_id = ${firmId} and i.type = ${type} and i.deleted_at is null and p.deleted_at is null`.execute(this.db);
    const unlinked = await sql<{ party_id: string; free: string }>`
      select pm.party_id, sum(pm.amount - coalesce((select sum(a.amount) from payment_allocations a where a.payment_id = pm.id), 0)) as free
        from payments pm where pm.firm_id = ${firmId} and pm.type = ${type === 'sale' ? 'in' : 'out'} and pm.deleted_at is null
       group by pm.party_id`.execute(this.db);
    const now = Date.parse(today());
    const blank = () => ({ party: '', notDue: 0, d30: 0, d60: 0, d90: 0, older: 0, total: 0, unlinked: 0, net: 0 });
    const by = new Map<string, ReturnType<typeof blank>>();
    for (const r of rows.rows) {
      const due = n(r.due);
      if (due <= 0) continue;
      const days = Math.round((now - Date.parse(r.due_date ?? r.invoice_date)) / 86400000);
      const e = by.get(r.party_id) ?? { ...blank(), party: r.name };
      const bucket = days <= 0 ? 'notDue' : days <= 30 ? 'd30' : days <= 60 ? 'd60' : days <= 90 ? 'd90' : 'older';
      e[bucket] = r2(e[bucket] + due);
      e.total = r2(e.total + due);
      by.set(r.party_id, e);
    }
    for (const [id, e] of by) {
      e.unlinked = r2(n(unlinked.rows.find((u) => u.party_id === id)?.free));
      e.net = r2(e.total - e.unlinked);
    }
    const data = [...by.values()].sort((a, b) => b.total - a.total);
    const sum = (k: 'notDue' | 'd30' | 'd60' | 'd90' | 'older' | 'total' | 'net') => data.reduce((s, r) => s + r[k], 0);
    return {
      columns: [
        col('party', 'Party Name'), col('notDue', 'Not Yet Due', 'money'), col('d30', '1–30 Days', 'money'), col('d60', '31–60 Days', 'money'),
        col('d90', '61–90 Days', 'money'), col('older', 'Over 90 Days', 'money'), col('total', 'Total Unpaid', 'money'),
        col('unlinked', 'Payments Not Linked', 'money'), col('net', 'Net', 'money'),
      ],
      rows: data,
      summary: [
        money('Not Yet Due', sum('notDue')), money('1–30 Days', sum('d30')), money('31–60 Days', sum('d60')), money('61–90 Days', sum('d90')),
        money('Over 90 Days', sum('older')), money(type === 'sale' ? 'Total Receivable' : 'Total Payable', sum('net')),
      ],
    };
  }

  /**
   * The figures the annual return (GSTR-9) asks for, from the books for the chosen period (use the financial year).
   * It is a working paper for filling the return on the portal, not a file the portal accepts.
   */
  private async gstr9(firmId: string, from: string, to: string) {
    const lines = await sql<{ type: InvoiceType; registered: boolean; taxed: boolean; taxable: string; igst: string; cgst: string; sgst: string; cess: string }>`
      select i.type, (i.party_gstin is not null) as registered, (l.gst_rate > 0) as taxed,
             sum(l.taxable_value) as taxable, sum(l.igst) as igst, sum(l.cgst) as cgst, sum(l.sgst) as sgst, sum(l.cess) as cess
        from invoice_items l join invoices i on i.id = l.invoice_id
       where i.firm_id = ${firmId} and i.deleted_at is null and i.type in ('sale', 'purchase', 'credit_note', 'debit_note')
         and i.invoice_date >= ${from} and i.invoice_date <= ${to}
       group by 1, 2, 3`.execute(this.db);
    type V = { taxable: number; igst: number; cgst: number; sgst: number; cess: number };
    const pick = (type: InvoiceType, taxed: boolean, registered?: boolean): V => {
      const v = { taxable: 0, igst: 0, cgst: 0, sgst: 0, cess: 0 };
      for (const l of lines.rows) {
        if (l.type !== type || l.taxed !== taxed || (registered !== undefined && l.registered !== registered)) continue;
        v.taxable += n(l.taxable); v.igst += n(l.igst); v.cgst += n(l.cgst); v.sgst += n(l.sgst); v.cess += n(l.cess);
      }
      return v;
    };
    const add = (a: V, b: V, sign = 1): V => ({
      taxable: r2(a.taxable + sign * b.taxable), igst: r2(a.igst + sign * b.igst), cgst: r2(a.cgst + sign * b.cgst), sgst: r2(a.sgst + sign * b.sgst), cess: r2(a.cess + sign * b.cess),
    });
    const zero: V = { taxable: 0, igst: 0, cgst: 0, sgst: 0, cess: 0 };
    const b2c = add(zero, pick('sale', true, false));
    const b2b = add(zero, pick('sale', true, true));
    const credit = add(zero, pick('credit_note', true));
    const outward = add(add(b2c, b2b), credit, -1);
    const exempt = add(pick('sale', false), pick('credit_note', false), -1);
    const inward = add(pick('purchase', true), pick('debit_note', true), -1);
    const expense = { ...(await this.expenseItc(firmId, from, to)), cess: 0 };
    const itc = add(inward, expense);
    const row = (table: string, particulars: string, v: V, bold = false): Row => ({ table, particulars, ...v, total: r2(v.igst + v.cgst + v.sgst + v.cess), _bold: bold });
    return {
      columns: [
        col('table', 'Table'), col('particulars', 'Particulars'), col('taxable', 'Taxable Value', 'money'), col('igst', 'IGST', 'money'),
        col('cgst', 'CGST', 'money'), col('sgst', 'SGST', 'money'), col('cess', 'Cess', 'money'), col('total', 'Total Tax', 'money'),
      ],
      rows: [
        row('4A', 'Supplies to unregistered persons (B2C)', b2c),
        row('4B', 'Supplies to registered persons (B2B)', b2b),
        row('4I', 'Credit notes for the above (−)', credit),
        row('4N', 'Supplies on which tax is payable', outward, true),
        row('5D–5F', 'Exempt, nil-rated and non-GST supplies (net of credit notes)', exempt),
        row('5N', 'Total turnover', add(outward, exempt), true),
        row('6B', 'Input tax credit on purchases (net of debit notes)', inward),
        row('6B', 'Input tax credit on expenses', expense),
        row('6O', 'Total input tax credit availed', itc, true),
        row('9', 'Tax payable for the year', { ...outward, taxable: 0 }, true),
        row('—', 'Net of input tax credit (negative = credit left over)', { ...add(outward, itc, -1), taxable: 0 }),
      ],
      summary: [
        money('Total Turnover', outward.taxable + exempt.taxable),
        money('Tax Payable', outward.igst + outward.cgst + outward.sgst + outward.cess),
        money('Input Tax Credit', itc.igst + itc.cgst + itc.sgst + itc.cess),
      ],
    };
  }

  /**
   * Party-wise details in the order the quarterly TCS return (Form 27EQ) and TDS return (Form 26Q) ask for them:
   * TCS the company collected on its sales, or TDS it deducted from its suppliers. PAN is taken from the party's
   * GSTIN. The section is the usual one for goods and must be checked against the law for the period.
   */
  private async deducteeReturn(firmId: string, kind: 'tcs' | 'tds', from: string, to: string) {
    const type: InvoiceType = kind === 'tcs' ? 'sale' : 'purchase';
    const rows = (await this.invoices(firmId, [type], from, to).orderBy('invoice_date').orderBy('created_at').execute()).filter(
      (r) => n(kind === 'tcs' ? r.tcs_amount : r.tds_amount) > 0,
    );
    const settings = await this.firms.settings(firmId);
    const partyIds = [...new Set(rows.map((r) => r.party_id).filter((x): x is string => !!x))];
    const parties = new Map(
      partyIds.length ? (await this.db.selectFrom('parties').select(['id', 'pan', 'tds_section', 'tcs_code']).where('id', 'in', partyIds).execute()).map((p) => [p.id, p] as const) : [],
    );
    const data = rows.map((r, i) => ({
      sr: i + 1,
      pan: parties.get(r.party_id ?? '')?.pan ?? (r.party_gstin ? r.party_gstin.slice(2, 12) : 'PANNOTAVBL'),
      party: r.party_name,
      section: kind === 'tcs' ? (parties.get(r.party_id ?? '')?.tcs_code ?? (settings.tcsDefaultCode || '—')) : (parties.get(r.party_id ?? '')?.tds_section ?? settings.tdsDefaultSection),
      date: r.invoice_date,
      number: r.number,
      // 27EQ asks for the amount received or debited; 26Q for the amount paid or credited, before GST.
      amount: kind === 'tcs' ? r2(n(r.total) - n(r.tcs_amount)) : n(r.taxable_amount),
      rate: n(kind === 'tcs' ? r.tcs_rate : r.tds_rate),
      tax: n(kind === 'tcs' ? r.tcs_amount : r.tds_amount),
    }));
    const missing = data.filter((r) => r.pan === 'PANNOTAVBL').length;
    return {
      subtitle: `${fmt(from)} to ${fmt(to)}${missing ? ` · ${missing} without a PAN (no GSTIN on the party)` : ''}`,
      columns: [
        col('sr', 'Sr', 'number'), col('pan', kind === 'tcs' ? 'PAN of Collectee' : 'PAN of Deductee'), col('party', 'Name'), col('section', kind === 'tcs' ? 'Collection Code' : 'Section Code'),
        col('date', kind === 'tcs' ? 'Date Received / Debited' : 'Date Paid / Credited', 'date'), col('number', 'Bill No.'),
        col('amount', kind === 'tcs' ? 'Amount Received / Debited' : 'Amount Paid / Credited', 'money'), col('rate', 'Rate %', 'number'),
        col('tax', kind === 'tcs' ? 'Tax Collected' : 'Tax Deducted', 'money'),
      ],
      rows: data,
      summary: [
        money(kind === 'tcs' ? 'Amount Received' : 'Amount Paid', data.reduce((s, r) => s + r.amount, 0)),
        money(kind === 'tcs' ? 'TCS to Deposit' : 'TDS to Deposit', data.reduce((s, r) => s + r.tax, 0)),
      ],
    };
  }

  /** Every loan's movements in the period: what was borrowed, repaid and charged, with the balance after each. */
  private async loanStatement(firmId: string, from: string, to: string) {
    const loans = await this.db.selectFrom('loan_accounts').selectAll().where('firm_id', '=', firmId).where('deleted_at', 'is', null).orderBy('created_at').execute();
    const txns = await this.db
      .selectFrom('loan_transactions').selectAll().where('firm_id', '=', firmId).where('deleted_at', 'is', null).where('txn_date', '<=', to)
      .orderBy('txn_date').orderBy('created_at').execute();
    const change = (t: (typeof txns)[number]) => (t.kind === 'payment' ? -n(t.principal) : n(t.principal));
    const rows: Row[] = [];
    let outstanding = 0;
    let paid = 0;
    let interest = 0;
    for (const l of loans) {
      const mine = txns.filter((t) => t.loan_id === l.id);
      const started = String(l.balance_date).slice(0, 10);
      let balance = (started <= to && started < from ? n(l.opening_balance) : 0) + mine.filter((t) => t.txn_date < from).reduce((s, t) => s + change(t), 0);
      rows.push({ date: null, loan: l.name, particulars: `Balance on ${fmt(from)}${l.lender ? ` · ${l.lender}` : ''}`, borrowed: null, repaid: null, interest: null, balance: r2(balance), _bold: true });
      if (started >= from && started <= to) {
        balance += n(l.opening_balance);
        rows.push({ date: started, loan: l.name, particulars: 'Loan taken', borrowed: n(l.opening_balance), repaid: null, interest: null, balance: r2(balance) });
      }
      for (const t of mine.filter((x) => x.txn_date >= from)) {
        balance += change(t);
        if (t.kind === 'payment') paid += n(t.principal);
        interest += n(t.interest);
        rows.push({
          date: t.txn_date, loan: l.name, particulars: t.description ?? { payment: 'Repayment', increase: 'More borrowed', charge: 'Charges' }[t.kind],
          borrowed: t.kind === 'payment' ? null : n(t.principal), repaid: t.kind === 'payment' ? n(t.principal) : null, interest: n(t.interest) || null, balance: r2(balance),
        });
      }
      outstanding += balance;
    }
    return {
      columns: [
        col('date', 'Date', 'date'), col('loan', 'Loan Account'), col('particulars', 'Particulars'), col('borrowed', 'Borrowed / Charged', 'money'),
        col('repaid', 'Principal Repaid', 'money'), col('interest', 'Interest Paid', 'money'), col('balance', 'Balance', 'money'),
      ],
      rows,
      summary: [money('Principal Repaid', paid), money('Interest Paid', interest), money(`Outstanding on ${fmt(to)}`, outstanding)],
    };
  }
}
