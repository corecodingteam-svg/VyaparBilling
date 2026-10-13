import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Matches, Max, MaxLength, Min, Validate, ValidateIf, ValidateNested,
  ValidatorConstraint, ValidatorConstraintInterface,
} from 'class-validator';

/** A custom party field defined once for the business and filled in per party. */
export interface PartyFieldDef {
  name: string;
  showInPrint: boolean;
}

/** Settings with their defaults; stored sparsely in firms.settings (only changed keys). */
export const DEFAULT_SETTINGS = {
  // ---- taxes
  /** Show GST fields and tax columns. */
  gstEnabled: true,

  // ---- transactions
  /** Put before the running number of new sale invoices, e.g. "INV-". (Kept for older data; see prefixes.) */
  invoicePrefix: '',
  /** Number prefix per document type, e.g. { sale: "INV-", estimate: "EST-", payment_in: "REC-" }. */
  prefixes: {} as Record<string, string>,
  /** New documents start with "Round Off" ticked. */
  defaultRoundOff: true,
  /** New sales start as cash sales. */
  defaultCashSale: false,
  /** Refuse a sale (or purchase return) that would take an item's stock below zero. */
  blockNegativeStock: false,
  /** Open the printable preview right after saving a document. */
  showInvoicePreview: true,
  /** Show a due date on credit invoices, defaulting to this many days after the invoice date. */
  dueDatesEnabled: false,
  defaultCreditDays: 15,

  // ---- print
  /** Printed at the bottom of invoices. */
  invoiceTerms: '',
  /** Caption under the signature space on printed documents. */
  signatureLabel: 'Authorized Signatory',
  invoiceTheme: 'classic' as 'classic' | 'modern' | 'minimal',
  /** Accent colour of the modern/minimal themes, as #RRGGBB. */
  themeColor: '#1E5EFF',
  /** Thermal receipt paper width in mm. */
  thermalWidth: 80 as 58 | 80,

  // ---- parties
  shippingAddressEnabled: true,
  /** Up to four custom party fields. */
  partyFields: [] as PartyFieldDef[],
  /** List parties whose dues are older than this many days; null = reminders off. */
  paymentReminderDays: 7 as number | null,

  // ---- items
  /** Track stock quantities for products. */
  stockMaintenance: true,
  /** Show the per-line discount columns on documents. */
  itemWiseDiscount: true,
  /** Decimal places allowed in quantities (0–3). */
  quantityDecimals: 2,
  /** Unit preselected for new items, e.g. "PCS". */
  defaultUnit: '',
  wholesalePriceEnabled: true,

  // ---- modules
  /** Own ledger accounts and journal entries. */
  accountingEnabled: false,
  serviceRemindersEnabled: false,

  // ---- salesmen
  /** A salesman sees only the parties assigned to them and the documents they entered. */
  salesmanOwnDataOnly: true,
  /** Record where salesmen are while they use the app, and with each sale or payment they enter. */
  locationTrackingEnabled: false,

  // ---- stock
  /** Several stores; every stock movement belongs to one. */
  godownsEnabled: false,
  /** Batch number and expiry per line; stock is kept per batch. */
  batchTrackingEnabled: false,
  /** Serial numbers / IMEIs per unit. */
  serialTrackingEnabled: false,
  /** MRP on items and lines. */
  mrpEnabled: false,

  // ---- taxes and charges
  cessEnabled: false,
  /** A discount on the whole bill, taken off before tax. */
  billDiscountEnabled: false,
  /** Freight, packing and the like on a bill. */
  additionalChargesEnabled: false,
  chargeNames: ['Shipping', 'Packaging'] as string[],
  /** TCS collected on sales (and paid on purchases). */
  tcsEnabled: false,
  /** TDS held back by the payer. */
  tdsEnabled: false,

  // ---- loyalty points
  loyaltyEnabled: false,
  /** Rupees of sale that earn one point. */
  loyaltyEarnPer: 100,
  /** Rupees one point is worth when redeemed. */
  loyaltyPointValue: 1,

  // ---- parties
  partyGroupsEnabled: false,

  // ---- backup
  autoBackup: 'off' as 'off' | 'daily' | 'weekly',
  /** How many automatic backups to keep. */
  autoBackupKeep: 7,

  // ---- credit limit
  /** What happens when a sale would take a customer past their credit limit: a warning, or the sale is refused. */
  creditLimitMode: 'warn' as 'warn' | 'block',

  // ---- print
  /** Show each item's picture on printed invoices. */
  itemImagesOnInvoice: false,

  // ---- messaging (needs WhatsApp or SMS set up under Integrations)
  /** Send each new sale invoice to the customer automatically. */
  autoSendInvoices: 'off' as 'off' | 'whatsapp' | 'sms',
  /** Send a receipt for each new Payment-In. */
  autoSendPayments: 'off' as 'off' | 'whatsapp' | 'sms',
  /** Wording of the messages; {customer} {number} {amount} {balance} {business} {link} are filled in. */
  invoiceMessage: 'Dear {customer}, your invoice {number} for ₹{amount} from {business} is ready. Balance due: ₹{balance}. {link}',
  paymentMessage: 'Dear {customer}, we received ₹{amount} (receipt {number}). Thank you! — {business}',
  reminderMessage: 'Dear {customer}, a payment of ₹{amount} to {business} is overdue. Please pay at your earliest. {link}',

  // ---- e-invoice and e-way bill
  einvoiceEnabled: false,
  ewayEnabled: false,
  /** Only sale invoices of at least this amount are offered for e-invoicing. */
  einvoiceMinAmount: 0,

  // ---- TDS / TCS statements (Forms 140 and 143)
  /** Section code used for TDS deducted from suppliers unless a party has its own; 1031 = purchase of goods. */
  tdsDefaultSection: '1031',
  /** Collection code for TCS unless a party has its own; empty = none (there is no general "sale of goods" code from tax year 2026-27). */
  tcsDefaultCode: '',
  /** Deductor / collector category (Annexure 4): K company, F firm, Q individual/HUF, … */
  deductorType: 'K',
  responsibleName: '',
  responsibleDesignation: '',
  responsiblePan: '',
  responsibleMobile: '',
  responsibleEmail: '',
  /** 15-digit token of the previous regular statement, when one was filed (needed by Forms 140 and 143). */
  tdsPreviousToken: '',
  tcsPreviousToken: '',

  // ---- online payments
  /** Your UPI ID; shown as a scannable QR on printed invoices. */
  upiId: '',
  upiQrOnInvoice: false,
};

export type FirmSettings = typeof DEFAULT_SETTINGS;

export const withDefaults = (stored: Partial<FirmSettings> | null | undefined): FirmSettings => ({ ...DEFAULT_SETTINGS, ...(stored ?? {}) });

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
// Letters, digits, "-" and "/" only, so a prefix is safe to use in number matching.
const PREFIX = /^[A-Za-z0-9/-]{0,10}$/;
export const PREFIX_TYPES = [
  'sale', 'estimate', 'sale_order', 'delivery_challan', 'proforma', 'credit_note', 'purchase_order', 'debit_note', 'payment_in', 'payment_out',
];

@ValidatorConstraint({ name: 'prefixes' })
class PrefixesConstraint implements ValidatorConstraintInterface {
  validate(value: unknown) {
    return (
      typeof value === 'object' &&
      value !== null &&
      Object.entries(value).every(([type, prefix]) => PREFIX_TYPES.includes(type) && typeof prefix === 'string' && PREFIX.test(prefix))
    );
  }

  defaultMessage() {
    return 'Prefixes can use letters, digits, "-" and "/" (max 10), for known document types only';
  }
}

class PartyFieldDto {
  @IsString() @MaxLength(40)
  name: string;

  @IsBoolean()
  showInPrint: boolean;
}

export class FirmSettingsDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() gstEnabled?: boolean;

  @ApiPropertyOptional() @IsOptional() @Transform(trim) @Matches(PREFIX, { message: 'Prefix can use letters, digits, "-" and "/" (max 10)' })
  invoicePrefix?: string;

  @ApiPropertyOptional({ description: 'Prefix by document type; send the whole map' }) @IsOptional() @Validate(PrefixesConstraint)
  prefixes?: Record<string, string>;

  @ApiPropertyOptional() @IsOptional() @IsBoolean() defaultRoundOff?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() defaultCashSale?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() blockNegativeStock?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() showInvoicePreview?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() dueDatesEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(365) defaultCreditDays?: number;

  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(1000) invoiceTerms?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(60) signatureLabel?: string;
  @ApiPropertyOptional() @IsOptional() @IsIn(['classic', 'modern', 'minimal']) invoiceTheme?: 'classic' | 'modern' | 'minimal';
  @ApiPropertyOptional() @IsOptional() @Matches(/^#[0-9A-Fa-f]{6}$/, { message: 'Colour must look like #1E5EFF' }) themeColor?: string;
  @ApiPropertyOptional() @IsOptional() @IsIn([58, 80]) thermalWidth?: 58 | 80;

  @ApiPropertyOptional() @IsOptional() @IsBoolean() shippingAddressEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsArray() @ArrayMaxSize(4) @ValidateNested({ each: true }) @Type(() => PartyFieldDto)
  partyFields?: PartyFieldDto[];
  @ApiPropertyOptional({ description: 'null turns payment reminders off' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(0) @Max(365)
  paymentReminderDays?: number | null;

  @ApiPropertyOptional() @IsOptional() @IsBoolean() stockMaintenance?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() itemWiseDiscount?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(3) quantityDecimals?: number;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(20) defaultUnit?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() wholesalePriceEnabled?: boolean;

  @ApiPropertyOptional() @IsOptional() @IsBoolean() accountingEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() serviceRemindersEnabled?: boolean;

  @ApiPropertyOptional() @IsOptional() @IsBoolean() salesmanOwnDataOnly?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() locationTrackingEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() godownsEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() batchTrackingEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() serialTrackingEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() mrpEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() cessEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() billDiscountEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() additionalChargesEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsArray() @ArrayMaxSize(6) @IsString({ each: true }) @MaxLength(30, { each: true }) chargeNames?: string[];
  @ApiPropertyOptional() @IsOptional() @IsBoolean() tcsEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() tdsEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() loyaltyEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(1) @Max(1e6) loyaltyEarnPer?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0.01) @Max(1e4) loyaltyPointValue?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() partyGroupsEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsIn(['off', 'daily', 'weekly']) autoBackup?: 'off' | 'daily' | 'weekly';
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(60) autoBackupKeep?: number;

  @ApiPropertyOptional() @IsOptional() @IsIn(['off', 'whatsapp', 'sms']) autoSendInvoices?: 'off' | 'whatsapp' | 'sms';
  @ApiPropertyOptional() @IsOptional() @IsIn(['off', 'whatsapp', 'sms']) autoSendPayments?: 'off' | 'whatsapp' | 'sms';
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(500) invoiceMessage?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(500) paymentMessage?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(500) reminderMessage?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() einvoiceEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() ewayEnabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11) einvoiceMinAmount?: number;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @Matches(/^([\w.-]{2,256}@[A-Za-z]{2,64})?$/, { message: 'UPI ID looks like name@bank' }) upiId?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() upiQrOnInvoice?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsIn(['warn', 'block']) creditLimitMode?: 'warn' | 'block';
  @ApiPropertyOptional() @IsOptional() @IsBoolean() itemImagesOnInvoice?: boolean;
  @ApiPropertyOptional() @IsOptional() @Matches(/^1\d{3}$/) tdsDefaultSection?: string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^(1\d{3})?$/) tcsDefaultCode?: string;
  @ApiPropertyOptional() @IsOptional() @IsIn(['A', 'S', 'D', 'E', 'G', 'H', 'L', 'N', 'K', 'M', 'P', 'T', 'J', 'B', 'Q', 'F']) deductorType?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(75) responsibleName?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(20) responsibleDesignation?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @Matches(/^([A-Za-z]{5}[0-9]{4}[A-Za-z])?$/, { message: 'PAN looks like ABCDE1234F' }) responsiblePan?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @Matches(/^([0-9]{10})?$/, { message: 'Mobile number has 10 digits' }) responsibleMobile?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(75) responsibleEmail?: string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^([0-9]{15})?$/, { message: 'Token number has 15 digits' }) tdsPreviousToken?: string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^([0-9]{15})?$/, { message: 'Token number has 15 digits' }) tcsPreviousToken?: string;
}
