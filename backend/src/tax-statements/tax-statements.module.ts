import { BadRequestException, Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsDateString, IsIn, IsNumber, IsOptional, Matches, Max, Min } from 'class-validator';
import { sql } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { today } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';
import { buildStatement, Challan, Deductee, Form, PAN, problems, quarterOf, quarterRange, StatementInput, TCS_CODES, TDS_SECTIONS } from './fvu-file';
import { buildGstr9 } from './gstr9';

const n = (v: unknown) => Number(v ?? 0);

class ChallanDto {
  @IsIn(['tds', 'tcs']) kind: 'tds' | 'tcs';
  @Matches(/^\d{7}$/, { message: 'BSR code has 7 digits' }) bsrCode: string;
  @Matches(/^\d{1,5}$/, { message: 'Challan serial number has up to 5 digits' }) challanNo: string;
  @IsDateString() depositDate: string;
  @IsNumber({ maxDecimalPlaces: 0 }, { message: 'Tax is in whole rupees, as on the challan' }) @Min(0) @Max(1e11) tax: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 0 }) @Min(0) interest?: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 0 }) @Min(0) fee?: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 0 }) @Min(0) other?: number;
  @IsOptional() @IsIn(['200', '400']) minorHead?: string;
  /** The quarter the tax belongs to; defaults to the quarter of the deposit date. */
  @IsOptional() @Matches(/^20\d{4}$/) taxYear?: string;
  @IsOptional() @IsIn(['Q1', 'Q2', 'Q3', 'Q4']) quarter?: 'Q1' | 'Q2' | 'Q3' | 'Q4';
}

@Injectable()
export class TaxStatementsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  async challans(firmId: string, kind: 'tds' | 'tcs', taxYear?: string, quarter?: string) {
    const rows = await this.db
      .selectFrom('tax_challans').selectAll().where('firm_id', '=', firmId).where('kind', '=', kind).where('deleted_at', 'is', null)
      .$if(!!taxYear, (q) => q.where('tax_year', '=', taxYear!)).$if(!!quarter, (q) => q.where('quarter', '=', quarter as 'Q1'))
      .orderBy('deposit_date').orderBy('created_at').execute();
    return rows.map((c) => ({
      id: c.id, kind: c.kind, taxYear: c.tax_year, quarter: c.quarter, bsrCode: c.bsr_code, challanNo: c.challan_no, depositDate: String(c.deposit_date).slice(0, 10),
      tax: n(c.tax), interest: n(c.interest), fee: n(c.fee), other: n(c.other), minorHead: c.minor_head,
    }));
  }

  async addChallan(firmId: string, dto: ChallanDto) {
    // Tax deducted in a month is deposited by the 7th of the next, so by default a challan belongs to the quarter of the month before it was paid.
    const monthBefore = new Date(Date.UTC(Number(dto.depositDate.slice(0, 4)), Number(dto.depositDate.slice(5, 7)) - 2, 15)).toISOString().slice(0, 10);
    const q = dto.taxYear && dto.quarter ? { taxYear: dto.taxYear, quarter: dto.quarter } : quarterOf(monthBefore);
    await this.db.insertInto('tax_challans').values({
      firm_id: firmId, kind: dto.kind, tax_year: q.taxYear, quarter: q.quarter, bsr_code: dto.bsrCode, challan_no: dto.challanNo, deposit_date: dto.depositDate,
      tax: dto.tax, interest: dto.interest ?? 0, fee: dto.fee ?? 0, other: dto.other ?? 0, minor_head: dto.minorHead ?? '200',
    }).execute();
    return this.challans(firmId, dto.kind, q.taxYear, q.quarter);
  }

  async removeChallan(firmId: string, id: string) {
    const res = await this.db.updateTable('tax_challans').set({ deleted_at: new Date() }).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'CHALLAN_NOT_FOUND', message: 'Challan not found.' });
  }

  /** Everything the statement for one quarter is made from. */
  private async input(firmId: string, form: Form, taxYear: string, quarter: string): Promise<{ input: StatementInput; warnings: string[] }> {
    const { from, to } = quarterRange(taxYear, quarter);
    const firm = await this.db.selectFrom('firms').selectAll().where('id', '=', firmId).executeTakeFirstOrThrow();
    const s = await this.firms.settings(firmId);
    const kind = form === '140' ? 'tds' : 'tcs';
    const bills = await this.db
      .selectFrom('invoices as i').leftJoin('parties as p', 'p.id', 'i.party_id')
      .select(['i.number', 'i.invoice_date', 'i.party_name', 'i.party_gstin', 'i.taxable_amount', 'i.total', 'i.tds_amount', 'i.tds_rate', 'i.tcs_amount', 'i.tcs_rate',
        'p.pan', 'p.gstin', 'p.tds_section', 'p.tcs_code', 'p.collectee_code'])
      .where('i.firm_id', '=', firmId).where('i.deleted_at', 'is', null).where('i.type', '=', form === '140' ? 'purchase' : 'sale')
      .where('i.invoice_date', '>=', from).where('i.invoice_date', '<=', to)
      .where(form === '140' ? 'i.tds_amount' : 'i.tcs_amount', '>', '0')
      .orderBy('i.invoice_date').execute();
    const warnings: string[] = [];
    const deductees: Deductee[] = bills.map((b) => {
      const gstin = b.party_gstin ?? b.gstin;
      let pan = b.pan ?? (gstin ? gstin.slice(2, 12) : 'PANNOTAVBL');
      if (pan !== 'PANNOTAVBL' && !PAN.test(pan)) pan = 'PANINVALID';
      if (pan === 'PANNOTAVBL' || pan === 'PANINVALID') warnings.push(`${b.number} (${b.party_name}): no valid PAN, so the statement says ${pan}. Tax is normally due at a higher rate without one.`);
      const tax = n(form === '140' ? b.tds_amount : b.tcs_amount);
      return {
        pan, name: b.party_name, ref: `Bill ${b.number}`, date: b.invoice_date, tax,
        section: form === '140' ? (b.tds_section ?? s.tdsDefaultSection) : (b.tcs_code ?? s.tcsDefaultCode),
        // TDS on purchases is on the value before GST; TCS is on the amount received from the buyer before the TCS itself.
        amount: form === '140' ? n(b.taxable_amount) : r2(n(b.total) - tax),
        rate: n(form === '140' ? b.tds_rate : b.tcs_rate),
        collecteeCode: b.collectee_code ?? undefined,
      };
    });
    const challans: Challan[] = (await this.challans(firmId, kind, taxYear, quarter)).map((c) => ({
      bsr: c.bsrCode, number: c.challanNo, date: c.depositDate, tax: c.tax, interest: c.interest, fee: c.fee, other: c.other, minorHead: c.minorHead, ref: `${c.bsrCode}/${c.challanNo}`,
    }));
    return {
      warnings,
      input: {
        form, taxYear, quarter, created: today(),
        firm: { tan: firm.tan, pan: firm.pan, name: firm.name, address: firm.address, city: firm.city, stateCode: firm.state_code, pincode: firm.pincode, email: firm.email, phone: firm.phone, gstin: firm.gstin },
        deductorType: s.deductorType,
        responsible: { name: s.responsibleName, designation: s.responsibleDesignation, pan: s.responsiblePan.toUpperCase(), mobile: s.responsibleMobile, email: s.responsibleEmail },
        previousToken: form === '140' ? s.tdsPreviousToken : s.tcsPreviousToken,
        challans, deductees,
      },
    };
  }

  /** What the quarter's statement holds, what stops it, and — when nothing does — the file itself. */
  async statement(firmId: string, form: Form, taxYear: string, quarter: string) {
    const { input, warnings } = await this.input(firmId, form, taxYear, quarter);
    const blockers = problems(input);
    const firm = input.firm;
    return {
      form, taxYear, quarter,
      deductees: input.deductees.length,
      tax: r2(input.deductees.reduce((t, d) => t + d.tax, 0)),
      deposited: r2(input.challans.reduce((t, c) => t + c.tax, 0)),
      problems: blockers,
      warnings,
      fileName: `${firm.tan ?? 'TAN'}_${form}_${quarter}_${taxYear}.txt`,
      file: blockers.length ? null : buildStatement(input, { appName: 'Billing' }),
    };
  }

  /** GSTR-9 for a financial year (e.g. '2025-26') as JSON in the GST portal's GSTR-9 structure. */
  async gstr9(firmId: string, year: string) {
    const start = Number(year.slice(0, 4));
    const from = `${start}-04-01`;
    const to = `${start + 1}-03-31`;
    const firm = await this.db.selectFrom('firms').select(['gstin', 'state_code']).where('id', '=', firmId).executeTakeFirstOrThrow();
    if (!firm.gstin) throw new BadRequestException({ code: 'NO_GSTIN', message: 'Add your GSTIN under Settings → Company first.' });
    const lines = await sql<{ type: string; registered: boolean; rate: string; hsn: string | null; unit: string | null; qty: string; taxable: string; igst: string; cgst: string; sgst: string; cess: string; service: boolean }>`
      select i.type, (i.party_gstin is not null) as registered, l.gst_rate as rate, l.hsn_code as hsn, l.unit, l.quantity as qty,
             l.taxable_value as taxable, l.igst, l.cgst, l.sgst, l.cess, coalesce(it.type = 'service', false) as service
        from invoice_items l join invoices i on i.id = l.invoice_id left join items it on it.id = l.item_id
       where i.firm_id = ${firmId} and i.deleted_at is null and i.type in ('sale', 'purchase', 'credit_note', 'debit_note')
         and i.invoice_date >= ${from} and i.invoice_date <= ${to}`.execute(this.db);
    const expenses = await sql<{ igst: string; cgst: string; sgst: string }>`
      select coalesce(sum(case when e.supplier_state is not null and e.supplier_state <> ${firm.state_code} then e.tax_amount else 0 end), 0) as igst,
             coalesce(sum(case when e.supplier_state is null or e.supplier_state = ${firm.state_code} then round(e.tax_amount / 2, 2) else 0 end), 0) as cgst,
             coalesce(sum(case when e.supplier_state is null or e.supplier_state = ${firm.state_code} then e.tax_amount - round(e.tax_amount / 2, 2) else 0 end), 0) as sgst
        from expenses e where e.firm_id = ${firmId} and e.deleted_at is null and e.expense_date >= ${from} and e.expense_date <= ${to}`.execute(this.db);
    const json = buildGstr9({
      gstin: firm.gstin, fyEnd: start + 1,
      lines: lines.rows.map((l) => ({
        type: l.type, registered: l.registered, rate: n(l.rate), hsn: l.hsn, unit: l.unit, qty: n(l.qty), service: l.service,
        taxable: n(l.taxable), igst: n(l.igst), cgst: n(l.cgst), sgst: n(l.sgst), cess: n(l.cess),
      })),
      expenseItc: { igst: n(expenses.rows[0].igst), cgst: n(expenses.rows[0].cgst), sgst: n(expenses.rows[0].sgst) },
    });
    return { fileName: `GSTR9_${firm.gstin}_${year}.json`, json };
  }

  codes() {
    return { tdsSections: TDS_SECTIONS, tcsCodes: TCS_CODES };
  }
}

@ApiTags('tax-statements')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller('tax-statements')
export class TaxStatementsController {
  constructor(private readonly t: TaxStatementsService) {}

  @Get('codes')
  codes() {
    return this.t.codes();
  }

  @Get('challans')
  challans(@CurrentUser() u: JwtPayload, @Query('kind') kind: string, @Query('taxYear') taxYear?: string, @Query('quarter') quarter?: string) {
    if (kind !== 'tds' && kind !== 'tcs') throw new BadRequestException({ code: 'BAD_KIND', message: 'kind must be tds or tcs' });
    return this.t.challans(u.firmId, kind, taxYear, quarter);
  }

  @Post('challans')
  addChallan(@CurrentUser() u: JwtPayload, @Body() dto: ChallanDto) {
    return this.t.addChallan(u.firmId, dto);
  }

  @Delete('challans/:id')
  @HttpCode(204)
  removeChallan(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.t.removeChallan(u.firmId, id);
  }

  @Get('statement')
  statement(@CurrentUser() u: JwtPayload, @Query('form') form: string, @Query('taxYear') taxYear: string, @Query('quarter') quarter: string) {
    if (form !== '140' && form !== '143') throw new BadRequestException({ code: 'BAD_FORM', message: 'form must be 140 or 143' });
    if (!/^20\d{4}$/.test(taxYear ?? '') || !['Q1', 'Q2', 'Q3', 'Q4'].includes(quarter)) throw new BadRequestException({ code: 'BAD_PERIOD', message: 'Give the tax year (e.g. 202627) and quarter.' });
    return this.t.statement(u.firmId, form, taxYear, quarter);
  }

  @Get('gstr9')
  gstr9(@CurrentUser() u: JwtPayload, @Query('year') year: string) {
    if (!/^20\d{2}-\d{2}$/.test(year ?? '')) throw new BadRequestException({ code: 'BAD_YEAR', message: 'Give the financial year, e.g. 2025-26.' });
    return this.t.gstr9(u.firmId, year);
  }
}

@Module({ controllers: [TaxStatementsController], providers: [TaxStatementsService] })
export class TaxStatementsModule {}
