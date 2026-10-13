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

A sale, purchase, return, Payment-In/Out, expense or POS bill can be paid in several parts (e.g. cash + UPI +
cheque), each to its own bank account. Cash and bank balances, cheques (each cheque part is deposited on its own),
the lists and the prints show each part.

## 4. Shipping address and credit-limit warning — built

- Shipping address on sale-side documents, filled from the party, printed as "Ship To".
- A credit sale that would take the customer past their credit limit shows a warning on the form
  and asks for confirmation before saving.

Limits: it is a warning, not a block. It applies to sale invoices only (not POS, orders, challans).

## 5. Invoice themes and thermal printing — built

- Three invoice themes (Classic, Modern, Minimal) with a choice of accent colour, picked in Settings and switchable in
  the print preview. They carry the logo, signature, shipping address, discount, cess, charges, TCS/TDS, loyalty
  points, batch / expiry / MRP / serial numbers and foreign-currency amounts.
- Thermal receipts for 58 mm and 80 mm paper as a PDF through the browser's print dialog, and **directly to a receipt
  printer** (ESC/POS): a network printer by IP address in the mobile and desktop apps; a USB or serial / Bluetooth-serial
  printer from Chrome or Edge on a computer, over HTTPS. POS opens the receipt straight away.

How the direct printing was checked: the receipt bytes are unit-tested; the network printer is tested against a real
local TCP socket; the browser USB and serial code is tested under Node against fake WebUSB / Web Serial objects
(`app/web_printer_test`). **Not tested on a real printer or in a real browser** — receipt printers differ, so the first
print on yours may need its paper width or code page adjusting. Not built: Bluetooth printers from the phone apps
(use the printer's network or USB mode), cash-drawer kick, QR codes and logos on the receipt, a per-printer code page.
Themes apply to invoice-type documents; payment receipts and reports keep one plain layout.

## 6. Reports — 46 in total

Beyond the 19 original ones: Trial Balance, Orders & Estimates, Sale by User, Party Wise Profit & Loss, Party Report by
Item, Sale Purchase by Party, GSTR-2, SAC Report, GST Report by Party, Stock Detail, Item Detail, Stock Summary by
Category, Item Wise Profit & Loss, Item Category Wise Profit & Loss, Sale Purchase by Item Category, Item Wise Discount,
Discount Report, Expense Transactions, Expense Item Report — and, for the newer features: Exchange Gain & Loss, TCS
Report, TDS Report, Stock by Godown, Batch Stock, Expiry Report, Serial Number Report, Loyalty Points.

Limits, stated plainly:
- The books are kept entry by entry, not as double-entry ledgers. The Trial Balance therefore shows "Owner's capital and
  opening balances" as the figure that makes the two sides agree.
- Profit reports cost goods at the item's current purchase price, not FIFO/average cost.
- GSTR reports are for reading and export (CSV/PDF); there is no JSON for the GST portal.

Not built: loan statement, GSTR-9, TCS/TDS returns in the government's format, ageing by bucket.

## 7. Remaining settings — built

- Transactions: number prefix per document type, preview after save, due dates and credit period.
- Party: shipping address on/off, up to four own party fields (optionally printed), payment reminders, **party groups**.
- Item: stock maintenance, item-wise discount, quantity decimals, default unit, wholesale price, **MRP**,
  **batch number and expiry**, **serial numbers / IMEI**, **godowns**.
- Taxes and charges: **compensation cess**, **discount on the whole bill**, **additional charges** (named, e.g. freight),
  **TCS**, **TDS**.
- **Loyalty points**: earned per ₹ of sale, redeemed against later bills at a set value.
- Accounting (journal entries), service reminders, multi-currency, **salesman settings**, **backup schedule**.
- **App lock (PIN)** (Settings → Account, on any role): a 4–6 digit PIN kept on this device only (salted hash, never sent
  anywhere). The app asks for it when opened and after being in the background for a minute; "Lock now" is in the
  sidebar; after five wrong tries each further try waits 30 s, then longer; "Forgot PIN? Sign out" clears it, because
  signing in again with the password proves it is the owner. It stops someone picking up an unlocked device — it does
  not protect against someone who can read the device's storage. The sign-in page itself is not locked.

Limits:
- Cess is one rate per item, charged on the taxable value; there are no per-state or per-HSN cess tables.
- TCS is a rate typed on the bill (no section-wise rates or thresholds); TDS is held back on the taxable value and
  settles part of the bill without money moving. Neither produces a return.
- Batch stock is per batch number; there is no batch-wise price list, and no manufacturing date on reports.
- A serial number belongs to one unit: sold once, back in stock when returned.
- Reminders are lists inside the app with "open WhatsApp with the message ready" and "copy message"; nothing is sent
  automatically.

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

## 10. Accountant access and salesman tracking — built, with one limit

- Users per company with roles (owner, admin, accountant, salesman). A salesman gets the sale side only; purchases,
  expenses, cash & bank, reports, utilities and business settings are refused by the server and hidden in the menu.
- **Parties are assigned to a salesman.** With "Salesmen see only their own" on (the default), a salesman sees only the
  parties assigned to them (a party they add is theirs) and the documents they entered or that belong to those parties —
  in lists, search, reminders, payments and the dashboard. An owner, admin or accountant sees everything.
- Sales and payments record who entered them; "Sale by User" totals billing and collection per user.
- **Location tracking** (off by default; Settings → Salesmen): while a user has the app open it records a position every
  five minutes and where each sale or payment is saved. "Where my team is" (admins) shows each user's last position, how
  much they did today and their day's trail, with links to open each point in Google Maps. The device asks the user for
  permission; a visible icon in the top bar shows when it is recording or blocked.

**The limit: it only records while the app (or its browser tab) is open.** Nothing runs in the background, so a
salesman who closes the app or locks the phone is not tracked. Continuous tracking needs a native Android/iOS app with a
background location service and the platform's background-location approval, which I could not build or test here.
There is also no live map inside the app (positions open in Google Maps), no geofencing and no route distance.

## 11. Backup and restore — built

- Download everything in a company (settings, logo and attachments included) as one file; restore a file as a new
  company next to the existing ones.
- **Automatic backups on the server** (daily or weekly; the latest N are kept; manual ones are kept until deleted),
  listed with download, restore-as-new-company and delete.
- **Google Drive**: connect a Google account and every backup is also copied to a "Billing Backups" folder (the app can
  only see files it created). **This needs a Google OAuth client** — someone creates one in Google Cloud (Web
  application, Drive API on, redirect URI `https://<your domain>/api/v1/backups/drive/callback`) and puts its ID and
  secret in the server's `.env` as `BILLING_GOOGLE_CLIENT_ID` / `BILLING_GOOGLE_CLIENT_SECRET`. Until then the screen
  says it is not set up and backups stay on the server. The Drive code is tested against a simulated Google, **not
  against Google itself**; a failed upload is shown against the backup.

Limits: backups are stored on the server's disk (a Docker volume) next to the database, so they do not protect against
losing the server — that is what the Drive copy or a downloaded file is for. Logins are not part of a backup.

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

## Still not built

- **Needs an account with an outside provider, not started:** WhatsApp sending and marketing, transaction SMS,
  e-invoice / e-way bill, Google Profile manager, online payments and online store.
- **Background location tracking** (see item 10) and **Bluetooth printers from the phone apps** (see item 5).

## How this was checked

- `backend`: 22 unit tests (invoice and document maths, Google Drive backup against a simulated Google).
- `app`: 113 unit tests, including `test/completion_test.dart`, `test/coverage_test.dart`, `test/escpos_test.dart` and `test/lock_test.dart`.
- `app/web_printer_test`: the browser printer code under Node against fake WebUSB / Web Serial (run separately).
- `app/live_api_test`: three end-to-end runs of the app's own repositories and form logic against the running backend,
  covering every item above, including restore and a new year with stores, batches and loyalty points carried over.
- `app/screenshots_test`: 79 screen renders, checked by eye for the new screens.

Not checked by any of these: the browser's file chooser (uploads and restore start from it), real browsers' location and
USB/serial permission prompts, the WhatsApp link, real receipt printers, and Google Drive itself.
