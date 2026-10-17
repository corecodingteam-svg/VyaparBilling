#!/usr/bin/env node
/* Creates the master admin (the provider's single account that manages every business), or changes its email,
 * name or password. There can only ever be one.
 *
 *   MASTER_PASSWORD='a long password' node scripts/set-master-admin.js you@example.com "Your Name"
 *
 * On the server:  docker compose ... run --rm -e MASTER_PASSWORD='...' billing-backend node scripts/set-master-admin.js you@example.com "Your Name"
 * Needs DATABASE_URL (set inside the container). The password is taken from the environment so it does not land in
 * shell history as an argument; clear it afterwards. */
const { Client } = require('pg');
const bcrypt = require('bcryptjs');

const [email, ...nameParts] = process.argv.slice(2);
const name = nameParts.join(' ').trim() || 'Master admin';
const password = process.env.MASTER_PASSWORD ?? '';
const fail = (m) => { console.error(m); process.exit(1); };

if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) fail('Usage: MASTER_PASSWORD=... node scripts/set-master-admin.js <email> [full name]');
if (password.length < 10) fail('Set MASTER_PASSWORD to at least 10 characters.');
if (!process.env.DATABASE_URL) fail('DATABASE_URL is not set.');

(async () => {
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    const mail = email.trim().toLowerCase();
    // The master admin must not also be a business login, so one email always means one kind of account.
    const clash = await db.query('SELECT 1 FROM users WHERE email = $1', [mail]);
    if (clash.rowCount) fail(`${mail} is already a business user's login. Use another email for the master admin.`);
    const hash = await bcrypt.hash(password, 10);
    const before = await db.query('SELECT email FROM master_admin');
    await db.query(
      `INSERT INTO master_admin (email, full_name, password_hash) VALUES ($1, $2, $3)
       ON CONFLICT (singleton) DO UPDATE SET email = EXCLUDED.email, full_name = EXCLUDED.full_name, password_hash = EXCLUDED.password_hash, updated_at = now()`,
      [mail, name, hash],
    );
    await db.query(`INSERT INTO platform_audit (actor_email, action, target) VALUES ('server console', $1, $2)`, [
      before.rowCount ? 'master.updated' : 'master.created',
      mail,
    ]);
    console.log(before.rowCount ? `Master admin updated: ${mail} (was ${before.rows[0].email})` : `Master admin created: ${mail}`);
  } finally {
    await db.end();
  }
})().catch((e) => fail(e.message));
