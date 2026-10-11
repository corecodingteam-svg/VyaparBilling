import { ColumnType, Generated } from 'kysely';
import type { InvoiceType } from '../common/invoice-types';

type Timestamp = ColumnType<Date, Date | string | undefined, Date | string>;
/** pg returns numeric as string; accept numbers on write. */
type Numeric = ColumnType<string, string | number | undefined, string | number>;
type NullableNumeric = ColumnType<string | null, string | number | null | undefined, string | number | null>;
/** DATE columns are returned as 'YYYY-MM-DD' strings (see database.module.ts). */
type DateCol = ColumnType<string, string | undefined, string>;
type Json<T> = ColumnType<T, string | undefined, string>;

/** An extra charge on a document (freight, packing, ...), added after tax. */
export interface InvoiceCharge {
  name: string;
  amount: number;
}

export interface AdditionalField {
  name: string;
  value: string;
}

export interface FirmsTable {
  id: Generated<string>;
  name: string;
  phone: string | null;
  gstin: string | null;
  email: string | null;
  books_start_date: DateCol;
  business_type: string | null;
  business_category: string | null;
  state_code: string | null;
  pincode: string | null;
  address: string | null;
  settings: ColumnType<Record<string, unknown>, string | undefined, string>;
  logo_file_id: string | null;
  signature_file_id: string | null;
  books_lock_date: string | null;
  drive_refresh_token: string | null;
  drive_email: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
}

export interface UsersTable {
  id: Generated<string>;
  firm_id: string;
  email: string;
  password_hash: string;
  full_name: string;
  role: Generated<string>;
  created_at: Timestamp;
}

export interface PartiesTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  phone: string | null;
  gstin: string | null;
  gst_type: Generated<'unregistered' | 'regular' | 'composition'>;
  state_code: string | null;
  email: string | null;
  billing_address: string | null;
  shipping_address: string | null;
  opening_balance: Numeric;
  opening_balance_date: DateCol;
  credit_limit: NullableNumeric;
  group_id: string | null;
  assigned_user_id: string | null;
  currency_code: string | null;
  loyalty_opening: Generated<number>;
  additional_fields: Json<AdditionalField[]>;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface CategoriesTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  created_at: Timestamp;
}

export interface UnitsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  short_name: string;
  created_at: Timestamp;
}

export interface ItemsTable {
  id: Generated<string>;
  firm_id: string;
  type: Generated<'product' | 'service'>;
  name: string;
  hsn_code: string | null;
  unit: string | null;
  category_id: string | null;
  item_code: string | null;
  sale_price: Numeric;
  sale_price_includes_tax: Generated<boolean>;
  sale_discount: Numeric;
  sale_discount_type: Generated<'percent' | 'amount'>;
  wholesale_price: NullableNumeric;
  wholesale_min_qty: NullableNumeric;
  purchase_price: Numeric;
  purchase_price_includes_tax: Generated<boolean>;
  gst_rate: NullableNumeric;
  opening_qty: Numeric;
  opening_price: NullableNumeric;
  opening_date: DateCol;
  min_stock: NullableNumeric;
  location: string | null;
  stock_qty: Numeric;
  image_file_id: string | null;
  service_reminder_days: number | null;
  cess_rate: NullableNumeric;
  mrp: NullableNumeric;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export type PaymentMode = 'cash' | 'bank' | 'upi' | 'cheque' | 'card';

export interface InvoicesTable {
  id: Generated<string>;
  firm_id: string;
  type: InvoiceType;
  number: string;
  invoice_date: string;
  is_cash: Generated<boolean>;
  party_id: string | null;
  party_name: string;
  phone: string | null;
  billing_address: string | null;
  state_of_supply: string | null;
  subtotal: Numeric;
  round_off: Numeric;
  total: Numeric;
  received: Numeric;
  payment_mode: Generated<PaymentMode>;
  description: string | null;
  shipping_address: string | null;
  due_date: string | null;
  currency_code: string | null;
  exchange_rate: NullableNumeric;
  created_by: string | null;
  godown_id: string | null;
  discount_pct: Numeric;
  discount_amount: Numeric;
  charges: ColumnType<InvoiceCharge[], string | undefined, string>;
  charges_total: Numeric;
  cess: Numeric;
  tcs_rate: Numeric;
  tcs_amount: Numeric;
  tds_rate: Numeric;
  tds_amount: Numeric;
  loyalty_earned: Generated<number>;
  loyalty_redeemed: Generated<number>;
  loyalty_amount: Numeric;
  fx_total: NullableNumeric;
  fx_received: NullableNumeric;
  prices_include_tax: Generated<boolean>;
  is_inter_state: Generated<boolean>;
  party_gstin: string | null;
  taxable_amount: Numeric;
  cgst: Numeric;
  sgst: Numeric;
  igst: Numeric;
  converted_invoice_id: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface InvoiceItemsTable {
  id: Generated<string>;
  invoice_id: string;
  item_id: string | null;
  name: string;
  quantity: Numeric;
  unit: string | null;
  price: Numeric;
  discount_pct: Numeric;
  discount_amount: Numeric;
  hsn_code: string | null;
  gst_rate: Numeric;
  taxable_value: Numeric;
  cgst: Numeric;
  sgst: Numeric;
  igst: Numeric;
  amount: Numeric;
  bill_discount: Numeric;
  cess_rate: Numeric;
  cess: Numeric;
  batch_no: string | null;
  mfg_date: string | null;
  expiry_date: string | null;
  mrp: NullableNumeric;
  serial_nos: string | null;
  fx_price: NullableNumeric;
  fx_amount: NullableNumeric;
  sort_order: number;
}

export interface PaymentsTable {
  id: Generated<string>;
  firm_id: string;
  type: 'in' | 'out';
  number: string;
  party_id: string;
  created_by: string | null;
  payment_date: string;
  amount: Numeric;
  payment_mode: Generated<PaymentMode>;
  description: string | null;
  bank_account_id: string | null;
  currency_code: string | null;
  exchange_rate: NullableNumeric;
  fx_amount: NullableNumeric;
  fx_gain: Numeric;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface StockMovementsTable {
  id: Generated<string>;
  firm_id: string;
  item_id: string;
  invoice_id: string | null;
  type: 'opening' | 'add' | 'reduce' | 'sale' | 'purchase' | 'credit_note' | 'debit_note' | 'transfer';
  godown_id: string | null;
  batch_no: string | null;
  expiry_date: string | null;
  qty_change: Numeric;
  price_per_unit: NullableNumeric;
  movement_date: string;
  notes: string | null;
  created_at: Timestamp;
}

export interface ExpenseCategoriesTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  created_at: Timestamp;
}

export interface ExpensesTable {
  id: Generated<string>;
  firm_id: string;
  category_id: string;
  number: string | null;
  expense_date: string;
  prices_include_tax: Generated<boolean>;
  taxable_amount: Numeric;
  tax_amount: Numeric;
  subtotal: Numeric;
  round_off: Numeric;
  total: Numeric;
  payment_mode: Generated<PaymentMode>;
  description: string | null;
  bank_account_id: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface ExpenseItemsTable {
  id: Generated<string>;
  expense_id: string;
  name: string;
  quantity: Numeric;
  price: Numeric;
  gst_rate: Numeric;
  taxable_value: Numeric;
  tax: Numeric;
  amount: Numeric;
  sort_order: number;
}

export interface BankAccountsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  opening_balance: Numeric;
  opening_date: DateCol;
  account_number: string | null;
  ifsc: string | null;
  bank_name: string | null;
  holder_name: string | null;
  upi_id: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export type FundAdjustmentKind =
  | 'cash_add' | 'cash_reduce' | 'bank_add' | 'bank_reduce' | 'bank_to_cash' | 'cash_to_bank' | 'bank_to_bank';

export interface FundAdjustmentsTable {
  id: Generated<string>;
  firm_id: string;
  kind: FundAdjustmentKind;
  bank_account_id: string | null;
  to_bank_account_id: string | null;
  amount: Numeric;
  adjustment_date: string;
  description: string | null;
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface LoanAccountsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  lender: string | null;
  account_number: string | null;
  opening_balance: Numeric;
  balance_date: DateCol;
  bank_account_id: string | null;
  interest_rate: NullableNumeric;
  term_months: number | null;
  description: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface LoanTransactionsTable {
  id: Generated<string>;
  firm_id: string;
  loan_id: string;
  kind: 'payment' | 'increase' | 'charge';
  principal: Numeric;
  interest: Numeric;
  txn_date: string;
  bank_account_id: string | null;
  description: string | null;
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

/** Read-only view: one row per movement of money (see the cash_bank migration). */
export interface MoneyFlowsView {
  firm_id: string;
  source: 'sale' | 'purchase' | 'credit_note' | 'debit_note' | 'payment_in' | 'payment_out' | 'expense' | 'adjustment' | 'loan' | 'loan_txn' | 'journal';
  source_id: string;
  label: string;
  name: string | null;
  ref_number: string | null;
  flow_date: string;
  created_at: Date;
  payment_mode: string;
  amount: string;
  account: 'cash' | 'bank' | 'cheque' | 'none';
  bank_account_id: string | null;
}

export interface InvoicePaymentsTable {
  id: Generated<string>;
  firm_id: string;
  invoice_id: string;
  payment_mode: PaymentMode;
  bank_account_id: string | null;
  amount: Numeric;
  fx_amount: NullableNumeric;
  sort_order: Generated<number>;
}

export interface PaymentAllocationsTable {
  id: Generated<string>;
  firm_id: string;
  payment_id: string;
  invoice_id: string;
  amount: Numeric;
  fx_amount: NullableNumeric;
}

/** One part of a Payment-In/Out or an expense paid in several modes. */
export interface PaymentPartsTable {
  id: Generated<string>;
  firm_id: string;
  payment_id: string;
  payment_mode: PaymentMode;
  bank_account_id: string | null;
  amount: Numeric;
  sort_order: Generated<number>;
}

export interface ExpensePaymentsTable {
  id: Generated<string>;
  firm_id: string;
  expense_id: string;
  payment_mode: PaymentMode;
  bank_account_id: string | null;
  amount: Numeric;
  sort_order: Generated<number>;
}

export interface PartyGroupsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  created_at: Timestamp;
}

export interface UserLocationsTable {
  id: Generated<string>;
  firm_id: string;
  user_id: string;
  latitude: number;
  longitude: number;
  accuracy: number | null;
  context: Generated<'ping' | 'sale' | 'payment'>;
  ref_id: string | null;
  recorded_at: Timestamp;
}

export interface GodownsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  address: string | null;
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface BackupsTable {
  id: Generated<string>;
  firm_id: string;
  file_name: string;
  size: number;
  kind: 'auto' | 'manual';
  drive_file_id: string | null;
  drive_error: string | null;
  created_at: Timestamp;
}

export interface FilesTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  mime_type: string;
  size: number;
  data: Buffer;
  created_at: Timestamp;
}

export interface AttachmentsTable {
  id: Generated<string>;
  firm_id: string;
  owner_type: 'invoice' | 'expense' | 'payment';
  owner_id: string;
  file_id: string;
  created_at: Timestamp;
}

export interface ExpenseItemDefsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  price: Numeric;
  hsn_code: string | null;
  gst_rate: NullableNumeric;
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

export type MemberRole = 'owner' | 'admin' | 'accountant' | 'salesman';

export interface FirmMembersTable {
  firm_id: string;
  user_id: string;
  role: MemberRole;
  created_at: Timestamp;
}

export interface LedgerAccountsTable {
  id: Generated<string>;
  firm_id: string;
  name: string;
  type: 'asset' | 'liability' | 'income' | 'expense' | 'equity';
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface JournalEntriesTable {
  id: Generated<string>;
  firm_id: string;
  number: string;
  entry_date: string;
  description: string | null;
  created_at: Timestamp;
  deleted_at: Timestamp | null;
}

export interface JournalLinesTable {
  id: Generated<string>;
  firm_id: string;
  entry_id: string;
  ledger_account_id: string | null;
  money_account: 'cash' | 'bank' | null;
  bank_account_id: string | null;
  debit: Numeric;
  credit: Numeric;
  sort_order: Generated<number>;
}

export interface CurrenciesTable {
  id: Generated<string>;
  firm_id: string;
  code: string;
  symbol: string;
  rate: Numeric;
  updated_at: Timestamp;
}

export interface ServiceRemindersDoneTable {
  invoice_item_id: string;
  firm_id: string;
  done_at: Timestamp;
}

export interface Database {
  firms: FirmsTable;
  users: UsersTable;
  parties: PartiesTable;
  categories: CategoriesTable;
  units: UnitsTable;
  items: ItemsTable;
  stock_movements: StockMovementsTable;
  expense_categories: ExpenseCategoriesTable;
  expenses: ExpensesTable;
  expense_items: ExpenseItemsTable;
  bank_accounts: BankAccountsTable;
  fund_adjustments: FundAdjustmentsTable;
  money_flows: MoneyFlowsView;
  loan_accounts: LoanAccountsTable;
  loan_transactions: LoanTransactionsTable;
  invoice_payments: InvoicePaymentsTable;
  payment_parts: PaymentPartsTable;
  expense_payments: ExpensePaymentsTable;
  party_groups: PartyGroupsTable;
  user_locations: UserLocationsTable;
  godowns: GodownsTable;
  backups: BackupsTable;
  payment_allocations: PaymentAllocationsTable;
  files: FilesTable;
  attachments: AttachmentsTable;
  expense_item_defs: ExpenseItemDefsTable;
  firm_members: FirmMembersTable;
  ledger_accounts: LedgerAccountsTable;
  journal_entries: JournalEntriesTable;
  journal_lines: JournalLinesTable;
  currencies: CurrenciesTable;
  service_reminders_done: ServiceRemindersDoneTable;
  invoices: InvoicesTable;
  invoice_items: InvoiceItemsTable;
  payments: PaymentsTable;
}
