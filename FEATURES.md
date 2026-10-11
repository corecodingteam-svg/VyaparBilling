# Feature checklist

What is built and what is not, item by item, for the second feature batch (the 14 items asked for
on 2026-10-11). "Built" means: backend + app screens, covered by the automated checks described at
the end. Limits are listed next to each item so nothing is implied that is not there.

## 1. Link payments to invoices — built

- A Payment-In can be set against the party's unpaid sale invoices, a Payment-Out against unpaid
  purchase bills: type amounts per invoice, or "Auto link" (oldest first). Any remainder stays on
  account as an advance.
- The invoice shows the linked payments, its balance is total − received − linked, and the
  invoice list, sale/purchase reports, receipt PDF and reminders all use that balance.
- Deleting a payment or an invoice removes its links. Over-linking is refused.

Not built: linking a payment to a credit/debit note; linking from the invoice screen (it is done
from the payment).

## 2. Logo, signature, item images, attachments — built

- Company profile: upload a logo and a signature; both print on invoices (signature also on
  payment receipts).
- Item form: an image per item.
- Invoices, expenses and payments: attach files (PNG, JPEG, WebP, PDF, up to 5 MB each).

Limits: files are stored in the database. The item image is shown on the item form only, not in
the item list or on printed invoices.

## 3. Split payments — built

- A sale, purchase or return can be paid in several parts (e.g. cash + UPI + cheque), each to its
  own bank account. Cash/bank balances, cheques and prints show each part.

Not built: split payment on expenses, on Payment-In/Out entries, and in POS (one mode per bill).

## 4. Shipping address and credit-limit warning — built

- Shipping address on sale-side documents, filled from the party, printed as "Ship To".
- A credit sale that would take the customer past their credit limit shows a warning on the form
  and asks for confirmation before saving.

Limits: it is a warning, not a block. It applies to sale invoices only (not POS, orders, challans).

## 5. Invoice themes and thermal printing — built

- Three invoice themes (Classic, Modern, Minimal) with a choice of accent colour, picked in
  Settings and switchable in the print preview.
- Thermal receipts for 58 mm and 80 mm paper, also from the preview; POS opens the receipt directly.

Limits: receipts are PDFs printed through the browser/system print dialog; there is no direct
(ESC/POS, Bluetooth) printer driver. Themes apply to invoice-type documents; payment receipts and
reports keep one plain layout.

## 6. Reports — 38 in total (19 added)

Added: Trial Balance, Orders & Estimates, Sale by User, Party Wise Profit & Loss, Party Report by
Item, Sale Purchase by Party, GSTR-2, SAC Report, GST Report by Party, Stock Detail, Item Detail,
Stock Summary by Category, Item Wise Profit & Loss, Item Category Wise Profit & Loss, Sale Purchase
by Item Category, Item Wise Discount, Discount Report, Expense Transactions, Expense Item Report.

Limits, stated plainly:
- The books are kept entry by entry, not as double-entry ledgers. The Trial Balance therefore shows
  "Owner's capital and opening balances" as the figure that makes the two sides agree.
- Profit reports cost goods at the item's current purchase price, not FIFO/average cost.
- GSTR reports are for reading and export (CSV/PDF); there is no JSON for the GST portal.

Not built: loan statement, GSTR-9, TCS/TDS reports, batch/serial reports, ageing by bucket.

## 7. Remaining settings — built

- Transactions: number prefix per document type, preview after save, due dates and credit period.
- Party: shipping address on/off, up to four own party fields (optionally printed on invoices),
  payment reminders and their period.
- Item: stock maintenance, item-wise discount columns, quantity decimal places, default unit,
  wholesale price (applies automatically from the item's minimum quantity).
- Accounting: own ledger accounts and journal entries, included in Profit & Loss, Balance Sheet and
  Trial Balance.
- Service reminders: a follow-up period on a service item; reminders appear after each sale.
- Multi-currency: add currencies with a rate; a sale document can be made out and printed in one.

Limits: multi-currency is for the printed document only — books, party balances and reports stay in
rupees at the rate saved on the document. Reminders are lists inside the app with "open WhatsApp
with the message ready" and "copy message"; nothing is sent automatically.

Not built: passcode lock, godowns/multiple stores, batch/serial/MRP tracking, TCS/TDS, cess,
additional charges and bill-level discount, loyalty points, party groups.

## 8. Close financial year, verify my data, set up my business — built

- Close books up to a date: nothing on or before it can be added, changed or deleted; can be
  re-opened.
- Start a new year: creates a new company opening with this one's party balances, stock, bank and
  cash balances, loans and own accounts; masters, settings and users are copied.
- Verify my data: six consistency checks; "Fix" recalculates stock and received amounts.
- Set up my business: an eight-step checklist with shortcuts.

Limits: the new company opens with the position as of now, not as of a past date. Open estimates
and orders and undeposited cheques are not carried over.

## 9. Multiple companies under one login — built

Add a company, switch between companies, each with its own data and settings.

Not built: deleting a company.

## 10. Accountant access and salesman tracking — partly built

Built: users per company with roles (owner, admin, accountant, salesman). A salesman gets the sale
side only (sale documents, Payment-In, parties, POS, reminders); purchases, expenses, cash & bank,
reports, utilities and business settings are refused by the server and hidden in the menu. Sales
and payments record who entered them; the "Sale by User" report totals billing and collection per
user.

**Not built: live location / field tracking of salesmen.** Also not built: assigning parties to a
salesman — a salesman sees every party and every sale document, not only their own. The Items page
still shows add/edit buttons to a salesman; the server refuses them.

## 11. Backup and restore — built

Download everything in a company (including settings, logo and attachments) as one file; restore
a file as a new company next to the existing ones.

Not built: automatic/scheduled backup, backup to Google Drive. Logins are not part of a backup.

## 12. Expense GST and expense items — built

GST rate per expense line, prices with or without tax, saved expense items that fill price and
rate, and the tax counted as input credit in GSTR-3B and taken out of expenses in Profit & Loss.

Limit: an expense has no supplier state, so its GST is reported as CGST + SGST in equal halves.

## 13. Editing transfers, cash adjustments and loan entries — built

## 14. Quick search — built

Search button and Ctrl/Cmd+K: parties (name, phone, GSTIN), items (name, code, HSN) and documents
(number, party, phone).

Not built: searching payments and expenses.

---

## Not asked for yet

These need an account with an outside provider and have not been started: WhatsApp sending and
marketing, transaction SMS, e-invoice / e-way bill, Google Profile manager, online payments and
online store.

## How this was checked

- `backend`: 11 unit tests (invoice and GST math).
- `app`: 67 unit tests, including one file for this batch (`test/completion_test.dart`).
- `app/live_api_test`: two end-to-end runs of the app's own repositories and form logic against
  the running backend, covering every item above.
- `app/screenshots_test`: 66 screen renders, checked by eye for the new screens.

Not checked by any of these: the browser's file chooser (uploads and restore start from it), the
WhatsApp link, and printing on a physical thermal printer.
