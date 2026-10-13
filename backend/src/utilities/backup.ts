import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { sql, Transaction } from 'kysely';
import { Db } from '../database/database.module';
import { Database } from '../database/schema';

export const BACKUP_FORMAT = 'billing-backup';
export const BACKUP_VERSION = 1;

/**
 * Every table that holds a company's data, in an order that satisfies foreign keys on restore.
 * [via]: the table has no firm_id and is reached through its parent.
 */
const TABLES: Array<{ name: string; via?: { column: string; parent: string } }> = [
  { name: 'files' },
  { name: 'categories' },
  { name: 'units' },
  { name: 'party_groups' },
  { name: 'parties' },
  { name: 'bank_accounts' },
  { name: 'items' },
  { name: 'expense_categories' },
  { name: 'expense_item_defs' },
  { name: 'godowns' },
  { name: 'invoices' },
  { name: 'invoice_items', via: { column: 'invoice_id', parent: 'invoices' } },
  { name: 'invoice_payments' },
  { name: 'payments' },
  { name: 'payment_parts' },
  { name: 'payment_allocations' },
  { name: 'stock_movements' },
  { name: 'expenses' },
  { name: 'expense_items', via: { column: 'expense_id', parent: 'expenses' } },
  { name: 'expense_payments' },
  { name: 'fund_adjustments' },
  { name: 'loan_accounts' },
  { name: 'loan_transactions' },
  { name: 'tax_challans' },
  { name: 'ledger_accounts' },
  { name: 'journal_entries' },
  { name: 'journal_lines' },
  { name: 'currencies' },
  { name: 'attachments' },
  { name: 'service_reminders_done' },
];

const FIRM_COLUMNS = [
  'name', 'phone', 'gstin', 'email', 'books_start_date', 'business_type', 'business_category', 'state_code', 'pincode', 'address', 'city', 'tan', 'pan', 'settings',
  'logo_file_id', 'signature_file_id', 'books_lock_date',
] as const;

type Row = Record<string, unknown>;

/** Everything a company holds, as plain JSON (file contents base64-encoded). */
export async function exportFirm(db: Db, firmId: string) {
  const firm = (await sql<Row>`select * from firms where id = ${firmId}`.execute(db)).rows[0];
  const tables: Record<string, Row[]> = {};
  for (const t of TABLES) {
    const query = t.via
      ? sql<Row>`select c.* from ${sql.table(t.name)} c join ${sql.table(t.via.parent)} p on p.id = c.${sql.ref(t.via.column)} where p.firm_id = ${firmId}`
      : sql<Row>`select * from ${sql.table(t.name)} where firm_id = ${firmId}`;
    tables[t.name] = (await query.execute(db)).rows;
  }
  for (const f of tables.files) f.data = (f.data as Buffer).toString('base64');
  return {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt: new Date().toISOString(),
    firm: Object.fromEntries(FIRM_COLUMNS.map((c) => [c, firm[c]])),
    tables,
  };
}

const bad = (message: string) => new BadRequestException({ code: 'BAD_BACKUP', message });

/**
 * Restores a backup as a brand-new company and returns its id. Every row gets a fresh id and every
 * reference is re-pointed, so a backup can be restored any number of times, next to the original.
 * Columns the database doesn't have are dropped and a reference to anything outside the backup
 * becomes null, so a hand-edited file cannot reach another company's data.
 */
export async function restoreFirm(trx: Transaction<Database>, backup: Record<string, unknown>, name?: string): Promise<string> {
  if (backup.format !== BACKUP_FORMAT) throw bad('This is not a backup file from this app.');
  if (backup.version !== BACKUP_VERSION) throw bad('This backup was made by a newer version of the app.');
  const firm = backup.firm as Row | undefined;
  const tables = backup.tables as Record<string, unknown> | undefined;
  if (!firm || typeof firm !== 'object' || !tables || typeof tables !== 'object') throw bad('The backup file is incomplete.');

  const columns = new Map<string, Map<string, string>>();
  const info = await sql<{ table_name: string; column_name: string; data_type: string }>`
    select table_name, column_name, data_type from information_schema.columns where table_schema = current_schema()`.execute(trx);
  for (const c of info.rows) {
    if (!columns.has(c.table_name)) columns.set(c.table_name, new Map());
    columns.get(c.table_name)!.set(c.column_name, c.data_type);
  }

  // New ids for every row first, so references can point forwards as well as backwards.
  const ids = new Map<string, string>();
  const rowsOf = (table: string): Row[] => {
    const rows = tables[table] ?? [];
    if (!Array.isArray(rows)) throw bad(`The backup file is damaged (${table}).`);
    return rows as Row[];
  };
  for (const t of TABLES) {
    for (const r of rowsOf(t.name)) {
      if (!r || typeof r !== 'object') throw bad(`The backup file is damaged (${t.name}).`);
      if (typeof r.id === 'string') ids.set(r.id, randomUUID());
    }
  }
  const remap = (v: unknown) => (typeof v === 'string' ? (ids.get(v) ?? null) : null);

  const firmId = randomUUID();
  const firmName = name ?? (typeof firm.name === 'string' && firm.name.trim() ? firm.name.trim() : 'Restored company');
  await sql`insert into firms (id, name, phone, gstin, email, books_start_date, business_type, business_category, state_code, pincode, address, settings, books_lock_date)
            values (${firmId}, ${firmName}, ${firm.phone ?? null}, ${firm.gstin ?? null}, ${firm.email ?? null},
                    coalesce(${(firm.books_start_date as string) ?? null}::date, current_date), ${firm.business_type ?? null}, ${firm.business_category ?? null},
                    ${firm.state_code ?? null}, ${firm.pincode ?? null}, ${firm.address ?? null}, ${JSON.stringify(firm.settings ?? {})}::jsonb,
                    ${(firm.books_lock_date as string) ?? null}::date)`.execute(trx);

  for (const t of TABLES) {
    const known = columns.get(t.name);
    if (!known) continue;
    const rows = rowsOf(t.name).map((r) => {
      const out: Row = {};
      for (const [col, type] of known) {
        const v = r[col];
        if (v === undefined) continue;
        if (col === 'firm_id') out[col] = firmId;
        else if (col === 'id') out[col] = remap(v);
        // The document a quotation was converted into is filled in after all invoices exist.
        else if (col === 'converted_invoice_id') out[col] = null;
        // Logins are not part of a backup.
        else if (col === 'created_by') out[col] = null;
        else if (col.endsWith('_id')) out[col] = v === null ? null : remap(v);
        else if (type === 'bytea') out[col] = Buffer.from(String(v), 'base64');
        else if (type === 'jsonb' || type === 'json') out[col] = JSON.stringify(v);
        else out[col] = v;
      }
      return out;
    });
    for (let i = 0; i < rows.length; i += 200) {
      // Table and column names come from the database's own catalogue, never from the file.
      await trx.insertInto(t.name as never).values(rows.slice(i, i + 200) as never).execute();
    }
  }
  for (const r of rowsOf('invoices')) {
    const target = remap(r.converted_invoice_id);
    if (target) await trx.updateTable('invoices').set({ converted_invoice_id: target }).where('id', '=', remap(r.id)!).execute();
  }
  await trx.updateTable('firms').set({ logo_file_id: remap(firm.logo_file_id), signature_file_id: remap(firm.signature_file_id) }).where('id', '=', firmId).execute();
  return firmId;
}
