# Billing app

Separate billing/accounting app (own backend, database and Flutter client), to be deployed later on a subdomain of the existing VPS.

- `backend/` – NestJS + Kysely API (port 3100), JWT email/password auth
- `database/migrations/` – node-pg-migrate migrations (own `billing` database)
- `app/` – Flutter client (web, Android, iOS), state management with **BLoC** (`flutter_bloc`)
- `reference/` – screenshots of the feature set being built (git-ignored)

## Modules

Everything in the sidebar is built:

| Area | What it does |
|---|---|
| Login / sign-up, company profile | Email + password; business details incl. GSTIN and state |
| Dashboard | Receivable, payable, cash in hand + bank balance, low stock, monthly sales chart |
| Parties | GST & address, opening balance, credit limit, additional fields, ledger with running balance |
| Items | Products, services, categories, units, pricing, opening stock, stock adjustment, stock history |
| Sale | Sale invoices (cash/credit), estimates, sale orders, delivery challans, proforma invoices, sale returns (credit notes), Payment-In, POS |
| Purchase & Expense | Purchase bills, purchase orders, purchase returns (debit notes), Payment-Out, expenses by category |
| Conversions | Estimate → sale order / sale; sale order, challan, proforma → sale; purchase order → purchase bill |
| GST | Per-line rate, with/without-tax prices, CGST+SGST or IGST by place of supply, tax invoice PDF with HSN and tax summary |
| Cash & Bank | Bank accounts, cash in hand, transfers and adjustments, cheques (open → deposited), loan accounts with EMI principal/interest |
| Reports (38) | Transaction, party, GST, item/stock and business reports incl. trial balance, GSTR-1/2/3B, party- and item-wise profit, stock detail — each with CSV export and PDF print |
| Utilities | Import items / parties from CSV, export items, bulk update items, barcode label sheets, set-up checklist, verify data, close financial year, backup & restore |
| Payments | Payments linked to invoices, split payments (cash + bank), attachments |
| Print | Three invoice themes with logo and signature, 58/80 mm thermal receipts |
| Accounting | Own ledger accounts and journal entries, currencies for printing |
| Companies & users | Several companies per login; owner / admin / accountant / salesman roles |
| Reminders | Overdue payments, service follow-ups |
| Settings | GST, number prefixes, due dates, print theme, party / item options, modules, change password |

`FEATURES.md` lists, feature by feature, exactly what is built and what is not.

Not built: WhatsApp sending / marketing, SMS, online store and payments, e-way bill / e-invoice
filing, Tally export, live salesman location, automatic backup.

## Run locally

```bash
# one-time: database
psql -d postgres -c "CREATE ROLE billing LOGIN PASSWORD 'billing'" -c "CREATE DATABASE billing OWNER billing"

cd backend
cp .env.example .env
npm install
npm run migrate:up
npm run start:dev            # http://localhost:3100/api/v1, Swagger at /api/docs

cd ../app
flutter run -d chrome        # API_BASE_URL defaults to http://localhost:3100/api/v1
```

## App architecture

```
lib/
  core/        ApiClient (Dio + token), ChangeBus, status enums, generic SubmitCubit
  data/        models + repositories (each write publishes its topics on the ChangeBus; blocs
               subscribe to what they show, e.g. a sale refreshes parties, items and the dashboard)
  features/    one folder per module: screens + bloc/ (Blocs for data, Cubits for forms)
  shell/       sidebar, top bar, NavCubit
  shared/      theme, formatting, period filter, CSV, file save/pick, common widgets
```

No `setState` or Riverpod: widget state classes only own text/tab controllers.
`InvoiceKind` / `PaymentKind` carry the per-type wording so the invoice and payment screens can be
reused for purchase bills and Payment-Out.

## Tests

```bash
cd backend && npx jest          # invoice and GST math
cd app && flutter test          # blocs, cubits, form rules, CSV, import rules, PDFs
```

Visual check of key screens (renders PNGs and an invoice PDF into `app/screenshots_test/goldens/`):

```bash
FONT_DIR=$(dirname $(dirname $(readlink -f $(which flutter))))/bin/cache/artifacts/material_fonts \
  flutter test screenshots_test --update-goldens
```

End-to-end check of the app's repositories and invoice form logic against a running backend:

```bash
flutter test live_api_test      # registers a throwaway firm on the local backend
```

## API (all under `/api/v1`, Bearer token except auth)

- `auth/register`, `auth/login`, `auth/me`, `auth/change-password`
- `firm` (GET/PATCH, including `settings`)
- `parties` (CRUD + `/:id/transactions`, `/import`)
- `items` (CRUD + `/:id/movements`, `/:id/adjust`, `/import`, PATCH `/bulk`), `categories`, `units`
- `invoices?type=<type>&from&to` (+ `/next-number`, GET/PUT/DELETE `/:id`) where type is one of `sale`,
  `purchase`, `credit_note`, `debit_note`, `estimate`, `sale_order`, `delivery_challan`, `proforma`,
  `purchase_order`; posting a document with `fromDocumentId` marks that estimate/order converted
- `payments?type=in|out&from&to` (+ `/next-number`, GET/PUT/DELETE `/:id`)
- `expense-categories` (CRUD), `expenses?categoryId&from&to` (GET/POST, GET/PUT/DELETE `/:id`)
- `bank-accounts` (CRUD + `/:id/transactions`), `cash-in-hand`, `fund-adjustments` (POST, DELETE `/:id`),
  `cheques` (+ `/:source/:id/deposit`, `/:source/:id/reopen`)
- `loan-accounts` (CRUD + `/:id/transactions`), `loan-transactions/:id` (DELETE)
- `reports` (catalog), `reports/:id?from&to&partyId&bankAccountId`
- `dashboard?from&to`

## How the numbers work

- **Every amount is recomputed on the server** (`backend/src/invoices/invoice-math.ts`); the app's
  on-screen figures mirror the same rounding and the live test asserts they match.
- **Document types** are declared once in `backend/src/common/invoice-types.ts`: each says how it moves
  stock (sale −, purchase +, returns reverse), how it affects the party balance and cash/bank, whether
  we number it, and what it can be converted into. Quotation-like types (estimate, orders, challan,
  proforma) do none of that until converted.
- **GST**: tax is added on top of the discounted value, or taken out of it when prices are entered
  "with tax". If the place of supply differs from the business's state the tax is IGST, otherwise it is
  split into CGST and SGST (an odd paisa goes to SGST).
- **Party balance** = opening balance + unpaid sales − unpaid purchases − payments in + payments out,
  with credit/debit notes reversing their side. Parties with transactions cannot be deleted.
- **Cash and bank balances are never stored.** The `money_flows` database view lists every movement of
  money (invoices' paid amounts, payments, expenses, adjustments, both legs of transfers, loans) and
  balances are sums over it. Cash-mode money is cash in hand; bank/UPI/card money belongs to the chosen
  bank account; a cheque counts towards a bank only once deposited.
- **Profit & loss** uses taxable (pre-GST) sale and purchase values, opening and closing stock valued at
  purchase price, expenses and loan interest/charges. Opening stock always counts as opening stock,
  whenever it was entered.

## Deploying

See `../deploy/README.md` §5: `sudo ./setup-billing.sh` adds this app to the existing server on its own
subdomain (`deploy/docker-compose.billing.yml`, `deploy/sites/billing.caddy`, `app/Dockerfile.web`).

## Deploy (advaitamaa.com server)

The billing app runs as an add-on to the existing advaitamaa.com Docker stack (the InventorySystems
checkout): same Postgres server (its own `billing` database), same Caddy and certificates. The stack's
own files are not modified.

One-time:

```bash
# DNS: an A record "billing" -> the server's IP (check: getent hosts billing.advaitamaa.com)
cd /path/to/inventory-checkout            # the folder that contains deploy/docker-compose.yml
git clone https://github.com/corecodingteam-svg/VyaparBilling.git billing
cd billing/deploy
sudo ./setup-billing.sh
```

Redeploy after new code:

```bash
cd /path/to/inventory-checkout/billing && git pull && sudo ./deploy/setup-billing.sh
```

Optional settings in the stack's `deploy/.env`: `BILLING_DOMAIN` (default billing.advaitamaa.com),
and `BILLING_GOOGLE_CLIENT_ID` / `BILLING_GOOGLE_CLIENT_SECRET` to copy backups to Google Drive
(OAuth client of type "Web application", Drive API enabled, redirect URI
`https://billing.advaitamaa.com/api/v1/backups/drive/callback`). Automatic backups are kept in the
`billing_backups` Docker volume.
