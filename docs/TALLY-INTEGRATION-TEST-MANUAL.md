# Tally integration — test manual

**What exists:** a one-way **import of Tally masters** from an XML export — customers and suppliers (Sundry Debtors / Sundry
Creditors, at any depth of grouping) and stock items. There is **no live sync with Tally, no export back to Tally, and
vouchers (invoices, payments, journals) are not imported.** Spreadsheet (.xlsx) and CSV imports share the same screens and
are covered in section 8.

**Honest status:** the reader was written from Tally's documented XML layout and tested on a sample written by us
(`docs/tally-sample-masters.xml`). It has **not been tested against a real Tally export**. Section 7 is the part that matters
most: please run it against a real export from your Tally and report anything that does not match.

Where: sidebar → **Utilities → Import Parties** and **Import Items** (`/import-parties`, `/import-items`).

---

## 0. Before you start

| You need | How |
|---|---|
| App + API running | `http://localhost:8080` and `http://localhost:3100` (or the VPS) |
| A **new, empty company** | Register a fresh account so counts are easy to read (Settings is not needed) |
| The sample file | [`docs/tally-sample-masters.xml`](tally-sample-masters.xml) |
| A real export (section 7) | From your Tally, see 7.1 |

Tip: keep a note of **Parties** and **Items** counts before each test (Parties page / Items page).

---

## 1. Import parties from the sample file

**Steps**
1. Utilities → **Import Parties**.
2. Click **Choose file** → pick `tally-sample-masters.xml`.

**Expected on screen (before importing anything)**
- A preview table with **3 rows**, in this order: `Ravi Traders & Sons`, `Mega Supplier`, `Advance Customer`.
- A note: *"2 other ledgers (banks, cash, expenses, taxes…) were left out. Check that "to receive" and "to pay" are on the right side before importing."* (HDFC Bank and Cash were skipped.)
- A **Swap receive / pay** button is visible (it only appears for Tally files).
- No row marked as having a problem. The button reads **Import 3 parties**.

**Row by row**

| Party | Opening balance | Type | State | GSTIN | Phone | Email | Address |
|---|---|---|---|---|---|---|---|
| Ravi Traders & Sons | 5000 | **receive** | 27 (Maharashtra) | 27AAACR1234C1Z5 | +919876543210 | ravi@example.com | Shop 4, Laxmi Road, Pune |
| Mega Supplier | 12000 | **pay** | 29 (Karnataka, taken from the GSTIN) | 29AAAFM1111A1Z6 | — | — | — |
| Advance Customer | 300 | **pay** (a customer who paid in advance: Tally "Cr") | — | — | — | — | — |

Why: in Tally a **debit** balance is money the party owes you (receive); a **credit** is money you owe (pay), whichever group
the ledger sits in.

3. Click **Import 3 parties**.

**Expected after importing**
- Message **"3 imported"** (no "rejected").
- Parties page lists the three parties. Balances: Ravi **₹5,000 to receive**, Mega Supplier **₹12,000 to pay**, Advance Customer **₹300 to pay**.
- Dashboard **Total Receivable ₹5,000**, **Total Payable ₹12,300**.
- Open Ravi → ledger shows an **Opening** line of ₹5,000.

---

## 2. Import items from the sample file

1. Utilities → **Import Items** → **Choose file** → the same XML.
2. Note shown: *"Tally keeps selling prices in price lists, so sale prices are empty; the purchase price is the opening rate."*

**Expected preview: 2 rows**

| Item | Unit | Category | HSN | GST % | Purchase price | Opening stock | Sale price |
|---|---|---|---|---|---|---|---|
| Basmati Rice 5kg | BAG | (none) | **10063020** | **12** | **520** | **40** | empty |
| Wheat Flour | KGS | Grocery | — | — | — | 0 | empty |

Why these values: Basmati has two GST histories in the file; the **latest** (2025) one wins — HSN `10063020` and the
**IGST** rate 12 (not the CGST 2.5 and not the older 5 %). "Primary" is Tally's root group, so it is not made a category.

3. Click **Import 2 items**.

**Expected after importing**
- "2 imported".
- Items page: Basmati Rice 5kg shows quantity **40**; stock value **₹20,800** (40 × 520).
- Wheat Flour shows quantity 0, category Grocery.
- Sale price is empty on both — set one before billing.

---

## 3. Swap receive / pay

1. Delete the three imported parties (or use a fresh company) and choose the XML again on **Import Parties**.
2. Click **Swap receive / pay**.

**Expected:** every row flips — Ravi becomes **pay**, Mega Supplier **receive**, Advance Customer **receive**. Click again and
they flip back. Importing after a swap stores the swapped side. Use this if, in your real file, customers show up as "to pay".

---

## 4. Duplicates and re-importing

1. Import the parties file a **second time** into the same company.

**Expected:** the preview still shows 3 rows; after clicking Import the result reads **"0 imported, 3 rejected"** and each
rejection says *"A party with this name already exists."* Nothing is duplicated and existing balances do not change.
2. Same for items: *"An item with this name already exists."*
3. Partial re-import: delete **Mega Supplier** only, import again → **"1 imported, 2 rejected"**.

(The sample also contains `Ravi Traders & Sons` twice — a repeated ledger. It must appear **once** in the preview.)

---

## 5. Bad files (negative tests)

| Test | File | Expected message |
|---|---|---|
| Not XML | a text file renamed `x.xml` containing `not xml <` | *"That file is not valid XML (…)"* — nothing imported |
| XML but not a Tally master export | a file containing only `<ENVELOPE><BODY/></ENVELOPE>` | *"No ledgers or stock items found. In Tally use Display → List of Accounts → Export (XML), or Gateway → Export → Masters."* |
| Items file on the parties screen | an XML holding only `<STOCKITEM>`s, on **Import Parties** | *"The Tally file has no customers or suppliers."* |
| Parties-only XML on the items screen | opposite | *"The Tally file has no stock items."* |
| Empty file | 0-byte `.xml` | a readable error, not a crash or "Something went wrong" |
| Cancel the file dialog | press Cancel | nothing changes |

The error shows in a red box on the import page and the **Choose file** button stays usable.

---

## 6. Row-level validation after reading Tally data

Edit a copy of the sample, then import and check the preview marks the row (it is **skipped**, others still import):

| Change in the XML | Expected |
|---|---|
| `PARTYGSTIN` → `27AAACR1234` (too short) | row flagged *"GSTIN is not valid"*, "1 with problems (skipped)" |
| `LEDGERMOBILE` → `+91 12345` | imports; phone kept digits-only (`+9112345`) |
| Remove `<OPENINGBALANCE>` | imports with balance 0 and **no** receive/pay type |
| `OPENINGBALANCE` `1,25,000.50 Dr` | **125000.50**, receive (Indian comma grouping accepted) |
| A stock item `BASEUNITS` `Nos` | unit `NOS` |
| Stock item with no GST block | GST % empty (not 0) |
| An odd character `&#4;` inside a name/parent | file still reads (Tally writes these) |

---

## 7. Test with YOUR real Tally export (the important one)

### 7.1 Make the export
- **Tally Prime:** Gateway of Tally → *Export* → *Masters* (or Display → **List of Accounts** → export), format **XML**, include **Ledgers**, **Groups** and **Stock Items**.
- **Tally ERP 9:** Gateway of Tally → Display → Account Books/List of Accounts → *Export* → XML.
Save the file with an `.xml` extension. Note the **count of Sundry Debtors, Sundry Creditors and stock items** in Tally.

### 7.2 Compare
1. Import into a **fresh test company** (never your live one first).
2. Check, and write down any mismatch:
   - Preview party count = Tally debtors + creditors (banks, cash, tax and expense ledgers are *intentionally* excluded; the note says how many).
   - Pick **5 parties** and compare balance, side (receive/pay), GSTIN, state, phone, address with Tally.
   - Pick **5 stock items** and compare unit, HSN, GST %, opening quantity and opening rate with Tally.
   - Sum of "to receive" = Tally's Sundry Debtors closing/opening total; sum of "to pay" = Sundry Creditors.
   - If **all customers show "pay"**, use **Swap receive / pay**.
3. Things most likely to differ in a real file (report these): ledgers under custom group names that are *not* under Sundry Debtors/Creditors (they are skipped), parties with GST registered under a second name, multiple addresses, items with **bill-wise/price-list** sale prices (not imported), **batch-wise** opening stock, **alternate units** (only the base unit is read), an item whose GST is set at the *group* level rather than the item.
4. Large file: a 5,000-ledger export should preview in a few seconds and import without freezing; note timings.

### 7.3 After a real import
- Run **Reports → Party → Receivables Ageing** and **Payables Ageing**: totals should equal the Tally totals.
- Run **Reports → Item / Stock → Stock Summary**: quantity and value should equal Tally's closing stock (value is quantity × the imported opening rate).
- Utilities → **Verify My Data**: should report no problems.

---

## 8. Spreadsheet / CSV route (same screens)

Use this when Tally gives you Excel instead of XML.
1. Utilities → Import Parties/Items → **Download sample file** to see the layout.
2. **Choose file** with a `.xlsx` or `.csv`. Columns are matched by name (Vyapar/Tally/Busy-style headings such as *Party Name, Mobile, Opening Balance, Dr/Cr, Item name\*, Tax rate* are recognised). If the name column is not found the screen lets you pick the column.
3. Check values are cleaned: `₹ 1,500.50` → 1500.50, `(300)` → −300 (pay), `29-Karnataka` → state 29, `To Receive`/`Payable`/`Cr` map to receive/pay.
4. Old `.xls` files and Vyapar `.vyp` backups are **not** readable — the screen says so (save as `.xlsx` first).

---

## 9. Verify through the API (optional)

```bash
TOKEN=...   # from POST /api/v1/auth/login
curl -s http://localhost:3100/api/v1/parties -H "authorization: Bearer $TOKEN" | jq '.[] | {name, balance}'
curl -s "http://localhost:3100/api/v1/items?type=product" -H "authorization: Bearer $TOKEN" | jq '.[] | {name, stockQty, hsnCode, gstRate}'
```
Server logs: `tail -f` the API log while importing; a failed row logs nothing special — rejections are returned to the screen.

---

## 10. Result sheet

| # | Test | Pass / Fail | Notes |
|---|---|---|---|
| 1 | Parties from sample: 3 rows, values match table | | |
| 2 | Parties imported, balances, dashboard totals | | |
| 3 | Items from sample: 2 rows, latest HSN/IGST | | |
| 4 | Items imported, stock value ₹20,800 | | |
| 5 | Swap receive / pay flips both ways | | |
| 6 | Re-import: all rejected as duplicates | | |
| 7 | Bad files give readable errors (5 cases) | | |
| 8 | Row validation edits (7 cases) | | |
| 9 | Real Tally export: counts and 5+5 spot checks | | |
| 10 | Ageing / stock summary totals equal Tally | | |
| 11 | .xlsx / .csv route | | |

**Known limits to keep in mind:** masters only (no vouchers or opening bills); sale prices, price lists, batches and alternate units
are not imported; only the base unit and IGST rate are read; banks, cash and expense ledgers are not created.
