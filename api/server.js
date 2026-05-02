import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cors from 'cors';
import express from 'express';
import pg from 'pg';
import OpenAI from 'openai';
import { Configuration, PlaidApi, PlaidEnvironments, Products, CountryCode } from 'plaid';
import { PLAID_STATIC_MAP, NEEDS_AI, allowedCategoryIDs } from './plaidCategoryMap.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOKENS_PATH = path.join(__dirname, 'plaid_tokens.json');

const { Pool } = pg;
const dbUrl = process.env.POSTGRES_URL || process.env.DATABASE_URL;
const pool = new Pool({ connectionString: dbUrl });

async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_data (
      user_id TEXT PRIMARY KEY,
      data    JSONB NOT NULL DEFAULT '{}',
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS plaid_tokens (
      id                     TEXT PRIMARY KEY,
      user_id                TEXT NOT NULL,
      institution_name       TEXT NOT NULL,
      institution_id         TEXT NOT NULL DEFAULT '',
      access_token_encrypted TEXT NOT NULL,
      item_id                TEXT NOT NULL,
      linked_at              TEXT NOT NULL,
      last_synced_at         TEXT,
      UNIQUE (user_id, item_id)
    );
    CREATE TABLE IF NOT EXISTS budget_transactions (
      user_id                  TEXT NOT NULL,
      id                       TEXT NOT NULL,
      external_id              TEXT,
      merchant_name            TEXT NOT NULL DEFAULT '',
      normalized_merchant_name TEXT NOT NULL DEFAULT '',
      transaction_date         TEXT NOT NULL DEFAULT '',
      amount                   NUMERIC NOT NULL DEFAULT 0,
      currency                 TEXT NOT NULL DEFAULT 'USD',
      category_id              TEXT NOT NULL DEFAULT '',
      status                   TEXT NOT NULL DEFAULT '',
      category_source          TEXT NOT NULL DEFAULT '',
      confidence               NUMERIC NOT NULL DEFAULT 0,
      raw_text                 TEXT NOT NULL DEFAULT '',
      duplicate_risk           BOOLEAN NOT NULL DEFAULT FALSE,
      transaction_type         TEXT NOT NULL DEFAULT 'expense',
      created_at               TEXT NOT NULL DEFAULT '',
      updated_at               TEXT NOT NULL DEFAULT '',
      row_data                 JSONB NOT NULL,
      PRIMARY KEY (user_id, id)
    );
  `);
  await pool.query('ALTER TABLE plaid_tokens ADD COLUMN IF NOT EXISTS last_synced_at TEXT');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_budget_transactions_user_date ON budget_transactions (user_id, transaction_date DESC)');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_budget_transactions_user_status ON budget_transactions (user_id, status)');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_budget_transactions_user_category ON budget_transactions (user_id, category_id)');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_budget_transactions_user_external ON budget_transactions (user_id, external_id)');
  console.log('Database tables ready.');
}

const app = express();
const port = process.env.PORT || 3000;

if (!process.env.OPENAI_API_KEY) {
  console.warn('OPENAI_API_KEY is missing. Add it to api/.env before processing imports.');
}
if (!process.env.APPLE_CLIENT_ID) {
  console.warn('APPLE_CLIENT_ID is missing. Sign in with Apple will fail until it is set.');
}
if (!process.env.SESSION_SECRET) {
  console.warn('SESSION_SECRET is missing. Authenticated requests will fail until it is set.');
}
if (!process.env.WEB_PASSWORD) {
  console.warn('WEB_PASSWORD is missing. Web app login will be disabled until it is set.');
}
if (!process.env.PLAID_CLIENT_ID || !process.env.PLAID_SECRET) {
  console.warn('PLAID_CLIENT_ID or PLAID_SECRET is missing. Plaid endpoints will fail until set.');
}
if (!process.env.TOKEN_ENCRYPTION_KEY) {
  console.warn('TOKEN_ENCRYPTION_KEY is missing. Plaid access tokens will not be written until it is set.');
}

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const plaidClient = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments[process.env.PLAID_ENV || 'sandbox'],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
      'PLAID-SECRET': process.env.PLAID_SECRET,
    }
  }
}));

const MAX_TEXTS_PER_REQUEST = 10;
const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
let appleKeysCache = null;
let appleKeysFetchedAt = 0;

async function requireSessionAuth(req, res, next) {
  try {
    if (!process.env.SESSION_SECRET) {
      return res.status(503).json({ error: 'Server is not configured for authenticated requests.' });
    }
    const auth = req.headers['authorization'] || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    req.user = verifySessionToken(token);
    return next();
  } catch {
    return res.status(401).json({ error: 'Unauthorized.' });
  }
}

function base64urlEncode(value) {
  return Buffer.from(JSON.stringify(value))
    .toString('base64url');
}

function base64urlDecode(value) {
  return JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
}

function signSessionToken(user) {
  if (!process.env.SESSION_SECRET) {
    throw new Error('SESSION_SECRET is required to issue sessions.');
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlEncode({ alg: 'HS256', typ: 'JWT' });
  const payload = base64urlEncode({
    sub: user.id,
    iat: now,
    exp: now + 60 * 60 * 24 * 365,
  });
  const body = `${header}.${payload}`;
  const signature = crypto
    .createHmac('sha256', process.env.SESSION_SECRET)
    .update(body)
    .digest('base64url');
  return `${body}.${signature}`;
}

function verifySessionToken(token) {
  const [header, payload, signature] = token.split('.');
  if (!header || !payload || !signature) {
    throw new Error('Invalid session token.');
  }
  const body = `${header}.${payload}`;
  const expectedSignature = crypto
    .createHmac('sha256', process.env.SESSION_SECRET)
    .update(body)
    .digest('base64url');
  const signatureBytes = Buffer.from(signature);
  const expectedBytes = Buffer.from(expectedSignature);
  if (signatureBytes.length !== expectedBytes.length || !crypto.timingSafeEqual(signatureBytes, expectedBytes)) {
    throw new Error('Invalid session signature.');
  }
  const claims = base64urlDecode(payload);
  if (!claims.sub || !claims.exp || claims.exp <= Math.floor(Date.now() / 1000)) {
    throw new Error('Expired session token.');
  }
  return { id: claims.sub };
}

function decodeJwtParts(token) {
  const [header, payload, signature] = token.split('.');
  if (!header || !payload || !signature) {
    throw new Error('Invalid JWT.');
  }
  return {
    header: base64urlDecode(header),
    payload: base64urlDecode(payload),
    signedData: `${header}.${payload}`,
    signature: Buffer.from(signature, 'base64url'),
  };
}

async function getAppleSigningKeys() {
  const cacheTTL = 1000 * 60 * 60 * 12;
  if (appleKeysCache && Date.now() - appleKeysFetchedAt < cacheTTL) {
    return appleKeysCache;
  }
  const response = await fetch(APPLE_JWKS_URL);
  if (!response.ok) {
    throw new Error('Could not fetch Apple signing keys.');
  }
  const jwks = await response.json();
  appleKeysCache = jwks.keys || [];
  appleKeysFetchedAt = Date.now();
  return appleKeysCache;
}

async function verifyAppleIdentityToken(identityToken) {
  if (!process.env.APPLE_CLIENT_ID) {
    throw new Error('APPLE_CLIENT_ID is required to verify Apple identity tokens.');
  }

  const jwt = decodeJwtParts(identityToken);
  const keys = await getAppleSigningKeys();
  const jwk = keys.find(key => key.kid === jwt.header.kid && key.alg === jwt.header.alg);
  if (!jwk) {
    throw new Error('No matching Apple signing key found.');
  }

  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const isValid = crypto.verify(
    'RSA-SHA256',
    Buffer.from(jwt.signedData),
    publicKey,
    jwt.signature
  );
  if (!isValid) {
    throw new Error('Invalid Apple identity token signature.');
  }

  const now = Math.floor(Date.now() / 1000);
  if (jwt.payload.iss !== APPLE_ISSUER || jwt.payload.aud !== process.env.APPLE_CLIENT_ID || jwt.payload.exp <= now) {
    throw new Error('Invalid Apple identity token claims.');
  }

  return { id: `apple:${jwt.payload.sub}` };
}

// ─── Token DB helpers ────────────────────────────────────────────────────────

async function readTokens() {
  const result = await pool.query('SELECT * FROM plaid_tokens ORDER BY linked_at');
  return result.rows.map(row => ({
    id: row.id,
    userID: row.user_id,
    institutionName: row.institution_name,
    institutionId: row.institution_id,
    accessToken: decryptAccessToken(row.access_token_encrypted),
    itemId: row.item_id,
    linkedAt: row.linked_at,
    lastSyncedAt: row.last_synced_at,
  }));
}

async function upsertToken(entry) {
  if (!process.env.TOKEN_ENCRYPTION_KEY) {
    throw new Error('TOKEN_ENCRYPTION_KEY is required before writing Plaid access tokens.');
  }
  await pool.query(`
    INSERT INTO plaid_tokens (id, user_id, institution_name, institution_id, access_token_encrypted, item_id, linked_at, last_synced_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    ON CONFLICT (user_id, item_id) DO UPDATE SET
      id = $1, institution_name = $3, institution_id = $4,
      access_token_encrypted = $5, linked_at = $7
  `, [entry.id, entry.userID, entry.institutionName, entry.institutionId || '',
      encryptAccessToken(entry.accessToken), entry.itemId, entry.linkedAt, entry.lastSyncedAt || null]);
}

async function updateTokenLastSynced(userID, itemID, syncedAt) {
  await pool.query(
    'UPDATE plaid_tokens SET last_synced_at = $1 WHERE user_id = $2 AND item_id = $3',
    [syncedAt, userID, itemID]
  );
}

async function deleteToken(userID, itemID) {
  const result = await pool.query(
    'DELETE FROM plaid_tokens WHERE user_id = $1 AND item_id = $2',
    [userID, itemID]
  );
  return result.rowCount > 0;
}

function encryptionKey() {
  if (!process.env.TOKEN_ENCRYPTION_KEY) {
    throw new Error('TOKEN_ENCRYPTION_KEY is required to decrypt Plaid access tokens.');
  }
  return crypto.createHash('sha256').update(process.env.TOKEN_ENCRYPTION_KEY).digest();
}

function encryptAccessToken(accessToken) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(accessToken, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString('base64'),
    tag.toString('base64'),
    encrypted.toString('base64'),
  ].join(':');
}

function decryptAccessToken(encryptedAccessToken) {
  const [ivValue, tagValue, encryptedValue] = encryptedAccessToken.split(':');
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(ivValue, 'base64')
  );
  decipher.setAuthTag(Buffer.from(tagValue, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedValue, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

function encryptTokenEntry(entry) {
  const { accessToken, ...rest } = entry;
  return {
    ...rest,
    accessTokenEncrypted: encryptAccessToken(accessToken),
  };
}

function decryptTokenEntry(entry) {
  if (entry.accessTokenEncrypted) {
    return {
      ...entry,
      accessToken: decryptAccessToken(entry.accessTokenEncrypted),
    };
  }
  return entry;
}

// ─── Plaid categorizer ───────────────────────────────────────────────────────

function buildTransactionDTO(t, categoryID, confidence) {
  const name = t.merchant_name || t.name || '';
  const normalized = name.trim().toUpperCase().replace(/[^A-Z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
  const safeCategory = allowedCategoryIDs.includes(categoryID) ? categoryID : 'cat_misc';
  return {
    externalID: t.transaction_id || null,
    merchantName: name.trim(),
    normalizedMerchantName: normalized,
    transactionDate: t.date,
    amount: t.amount,
    currency: t.iso_currency_code || 'USD',
    suggestedCategoryID: safeCategory,
    confidence,
    rawText: `${t.name} | ${t.personal_finance_category?.detailed ?? ''}`,
    transactionType: 'expense',
    duplicateRisk: false,
  };
}

function isVenmoOutflowTransaction(t) {
  if (!(t.amount > 0)) return false;
  const parts = [
    t.merchant_name,
    t.name,
    t.original_description,
    t.payment_channel,
    t.personal_finance_category?.detailed,
  ];
  return parts.some(part => String(part || '').toUpperCase().includes('VENMO'));
}

function isDateKey(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

async function classifyWithOpenAI(transactions) {
  if (!process.env.OPENAI_API_KEY) {
    return {
      transactions: transactions.map(t => buildTransactionDTO(t, 'cat_misc', 0.25)),
      warnings: [{ type: 'openai_unavailable', message: 'OpenAI API key is missing; ambiguous transactions were categorized as Miscellaneous.' }],
    };
  }

  const items = transactions
    .map((t, i) => `${i + 1}. merchant="${t.merchant_name || t.name}" plaid_category="${t.personal_finance_category?.detailed ?? ''}"`)
    .join('\n');

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: plaidCategorizationPrompt() },
        { role: 'user', content: `Classify these transactions:\n${items}` }
      ]
    });

    const parsed = JSON.parse(response.choices[0].message.content);
    return {
      transactions: (parsed.results || []).map((r, i) =>
        buildTransactionDTO(transactions[i], r.category_id, 0.85)
      ),
      warnings: [],
    };
  } catch (error) {
    console.warn('OpenAI categorization failed; falling back to Miscellaneous.', error?.message);
    return {
      transactions: transactions.map(t => buildTransactionDTO(t, 'cat_misc', 0.25)),
      warnings: [{ type: 'openai_failed', message: 'OpenAI categorization failed; ambiguous transactions were categorized as Miscellaneous.' }],
    };
  }
}

function plaidCategorizationPrompt() {
  return `You classify bank transactions into budget categories.
Return strict JSON only. No markdown.

Schema: { "results": [ { "category_id": "string" } ] }

Allowed category IDs: ${allowedCategoryIDs.join(', ')}

Rules:
- Return one result per input transaction, in the same order.
- Use cat_misc when uncertain.
- GENERAL_MERCHANDISE at a streaming service → cat_subscriptions
- GENERAL_MERCHANDISE at a coffee shop → cat_coffee
- GENERAL_SERVICES for gym or fitness → cat_health
- SUBSCRIPTION for any recurring digital service → cat_subscriptions`;
}

async function categorizePlaidTransactions(plaidTxns) {
  const results = [];
  const aiQueue = [];
  const warnings = [];

  for (const t of plaidTxns) {
    const primary = t.personal_finance_category?.primary ?? 'OTHER';
    const detailed = t.personal_finance_category?.detailed ?? '';

    // Coffee is nested under FOOD_AND_DRINK — refine using detailed
    if (primary === 'FOOD_AND_DRINK' && detailed.toUpperCase().includes('COFFEE')) {
      results.push(buildTransactionDTO(t, 'cat_coffee', 1.0));
      continue;
    }

    if (NEEDS_AI.has(primary)) {
      aiQueue.push(t);
      continue;
    }

    const mapped = PLAID_STATIC_MAP[primary];
    if (mapped === null) {
      if (isVenmoOutflowTransaction(t)) {
        results.push(buildTransactionDTO(t, 'cat_misc', 0.75));
      }
      continue; // skip other income/transfers
    }
    results.push(buildTransactionDTO(t, mapped ?? 'cat_misc', 1.0));
  }

  // Batch OpenAI calls (20 per request to stay under token limit)
  const BATCH_SIZE = 20;
  for (let i = 0; i < aiQueue.length; i += BATCH_SIZE) {
    const batch = aiQueue.slice(i, i + BATCH_SIZE);
    const aiResults = await classifyWithOpenAI(batch);
    results.push(...aiResults.transactions);
    warnings.push(...aiResults.warnings);
  }

  return { transactions: results, warnings };
}

// ─── Middleware ──────────────────────────────────────────────────────────────

const allowedOrigins = (process.env.CORS_ORIGINS || process.env.FRONTEND_ORIGIN || '')
  .split(',')
  .map(origin => origin.trim())
  .filter(Boolean);

app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error('Origin not allowed by CORS.'));
  },
}));
app.use(express.json({ limit: '25mb' }));

// ─── Health ──────────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'BudgetSnap API' });
});

// ─── User data (transactions, budgets, categories, rules) ────────────────────

function splitTransactionsFromUserData(data) {
  const incoming = data && typeof data === 'object' ? data : {};
  const transactions = Array.isArray(incoming.transactions) ? incoming.transactions : [];
  return {
    settings: { ...incoming, transactions: [] },
    transactions,
  };
}

function transactionRowValues(userID, transaction) {
  const row = transaction && typeof transaction === 'object' ? transaction : {};
  const id = String(row.id || crypto.randomUUID());
  const amount = Number(row.amount);
  return [
    userID,
    id,
    row.externalID ? String(row.externalID) : null,
    String(row.merchantName || ''),
    String(row.normalizedMerchantName || ''),
    String(row.transactionDate || ''),
    Number.isFinite(amount) ? amount : 0,
    String(row.currency || 'USD'),
    String(row.categoryID || ''),
    String(row.status || ''),
    String(row.categorySource || ''),
    Number.isFinite(Number(row.confidence)) ? Number(row.confidence) : 0,
    String(row.rawText || ''),
    Boolean(row.duplicateRisk),
    String(row.transactionType || 'expense'),
    String(row.createdAt || ''),
    String(row.updatedAt || ''),
    { ...row, id },
  ];
}

function parsePositiveInteger(value, fallback, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, max);
}

function escapeLikePattern(value) {
  return String(value).replace(/[\\%_]/g, match => `\\${match}`);
}

function buildTransactionFilters(userID, query) {
  const where = ['user_id = $1'];
  const values = [userID];

  if (query.statuses) {
    const statuses = String(query.statuses).split(',').map(v => v.trim()).filter(Boolean);
    if (statuses.length > 0) {
      values.push(statuses);
      where.push(`status = ANY($${values.length})`);
    }
  } else if (query.status && query.status !== 'all') {
    values.push(String(query.status));
    where.push(`status = $${values.length}`);
  }
  if (query.categoryID) {
    values.push(String(query.categoryID));
    where.push(`category_id = $${values.length}`);
  }
  if (query.from && isDateKey(String(query.from))) {
    values.push(String(query.from));
    where.push(`transaction_date >= $${values.length}`);
  }
  if (query.to && isDateKey(String(query.to))) {
    values.push(String(query.to));
    where.push(`transaction_date <= $${values.length}`);
  }
  if (query.min !== undefined && query.min !== '') {
    const min = Number(query.min);
    if (Number.isFinite(min)) {
      values.push(min);
      where.push(`amount >= $${values.length}`);
    }
  }
  if (query.max !== undefined && query.max !== '') {
    const max = Number(query.max);
    if (Number.isFinite(max)) {
      values.push(max);
      where.push(`amount <= $${values.length}`);
    }
  }
  if (query.search) {
    values.push(`%${escapeLikePattern(query.search)}%`);
    where.push(`(merchant_name ILIKE $${values.length} ESCAPE '\\' OR normalized_merchant_name ILIKE $${values.length} ESCAPE '\\')`);
  }

  return { where: where.join(' AND '), values };
}

function activeExpenseClause() {
  return "status = 'accepted' AND transaction_type = 'expense'";
}

function transactionSummaryFilters(userID, query, { includeDate = true } = {}) {
  const where = ['user_id = $1', activeExpenseClause()];
  const values = [userID];

  if (includeDate && query.from && isDateKey(String(query.from))) {
    values.push(String(query.from));
    where.push(`transaction_date >= $${values.length}`);
  }
  if (includeDate && query.to && isDateKey(String(query.to))) {
    values.push(String(query.to));
    where.push(`transaction_date <= $${values.length}`);
  }
  if (query.categoryIDs) {
    const categories = String(query.categoryIDs).split(',').map(v => v.trim()).filter(Boolean);
    if (categories.length > 0) {
      values.push(categories);
      where.push(`category_id = ANY($${values.length})`);
    }
  }
  if (query.merchant) {
    values.push(`%${escapeLikePattern(query.merchant)}%`);
    where.push(`(merchant_name ILIKE $${values.length} ESCAPE '\\' OR normalized_merchant_name ILIKE $${values.length} ESCAPE '\\')`);
  }
  if (query.min !== undefined && query.min !== '') {
    const min = Number(query.min);
    if (Number.isFinite(min)) {
      values.push(min);
      where.push(`amount >= $${values.length}`);
    }
  }
  if (query.max !== undefined && query.max !== '') {
    const max = Number(query.max);
    if (Number.isFinite(max)) {
      values.push(max);
      where.push(`amount <= $${values.length}`);
    }
  }

  return { where: where.join(' AND '), values };
}

function monthStartKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-01`;
}

function monthKey(date = new Date()) {
  return monthStartKey(date).slice(0, 7);
}

function isMonthKey(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}$/.test(value);
}

function monthEndKey(month) {
  const [year, monthNumber] = month.split('-').map(Number);
  const day = new Date(year, monthNumber, 0).getDate();
  return `${month}-${String(day).padStart(2, '0')}`;
}

function todayKey() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

async function readUserDataWithTransactions(userID) {
  const [dataResult, transactionsResult] = await Promise.all([
    pool.query('SELECT data FROM user_data WHERE user_id = $1', [userID]),
    pool.query('SELECT row_data FROM budget_transactions WHERE user_id = $1 ORDER BY transaction_date DESC, created_at DESC', [userID]),
  ]);
  const data = dataResult.rows[0]?.data ?? null;
  const transactions = transactionsResult.rows.map(row => row.row_data);

  if (data && transactions.length === 0 && Array.isArray(data.transactions) && data.transactions.length > 0) {
    await saveUserDataWithTransactions(userID, data);
    return data;
  }

  return data ? { ...data, transactions } : null;
}

async function ensureUserTransactionsMigrated(userID) {
  const countResult = await pool.query(
    'SELECT COUNT(*)::INT AS total FROM budget_transactions WHERE user_id = $1',
    [userID],
  );
  if ((countResult.rows[0]?.total ?? 0) > 0) return;

  const dataResult = await pool.query('SELECT data FROM user_data WHERE user_id = $1', [userID]);
  const data = dataResult.rows[0]?.data;
  if (data && Array.isArray(data.transactions) && data.transactions.length > 0) {
    await saveUserDataWithTransactions(userID, data);
  }
}

async function saveUserDataWithTransactions(userID, data) {
  const { settings, transactions } = splitTransactionsFromUserData(data);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      INSERT INTO user_data (user_id, data, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (user_id) DO UPDATE SET data = $2, updated_at = NOW()
    `, [userID, settings]);
    await client.query('DELETE FROM budget_transactions WHERE user_id = $1', [userID]);
    for (const transaction of transactions) {
      await client.query(`
        INSERT INTO budget_transactions (
          user_id, id, external_id, merchant_name, normalized_merchant_name,
          transaction_date, amount, currency, category_id, status, category_source,
          confidence, raw_text, duplicate_risk, transaction_type, created_at,
          updated_at, row_data
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18
        )
      `, transactionRowValues(userID, transaction));
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

app.get('/api/userdata', requireSessionAuth, async (req, res) => {
  try {
    res.json(await readUserDataWithTransactions(req.user.id));
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load user data.' });
  }
});

app.put('/api/userdata', requireSessionAuth, async (req, res) => {
  try {
    await saveUserDataWithTransactions(req.user.id, req.body);
    res.json({ ok: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not save user data.' });
  }
});

app.get('/api/transactions', requireSessionAuth, async (req, res) => {
  try {
    await ensureUserTransactionsMigrated(req.user.id);
    const limit = parsePositiveInteger(req.query.limit, 75, 500);
    const offset = Math.max(0, Number.parseInt(String(req.query.offset ?? '0'), 10) || 0);
    const filters = buildTransactionFilters(req.user.id, req.query);
    const countResult = await pool.query(
      `SELECT COUNT(*)::INT AS total FROM budget_transactions WHERE ${filters.where}`,
      filters.values,
    );
    const values = [...filters.values, limit, offset];
    const transactionsResult = await pool.query(
      `SELECT row_data FROM budget_transactions
       WHERE ${filters.where}
       ORDER BY transaction_date DESC, created_at DESC
       LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    );
    res.json({
      total: countResult.rows[0]?.total ?? 0,
      transactions: transactionsResult.rows.map(row => row.row_data),
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load transactions.' });
  }
});

app.get('/api/dashboard-summary', requireSessionAuth, async (req, res) => {
  try {
    await ensureUserTransactionsMigrated(req.user.id);
    const month = isMonthKey(req.query.month) ? req.query.month : monthKey();
    const from = `${month}-01`;
    const to = monthEndKey(month);
    const [spendResult, categoryResult, recentResult, pendingResult] = await Promise.all([
      pool.query(
        `SELECT COALESCE(SUM(amount), 0)::FLOAT AS total_spent
         FROM budget_transactions
         WHERE user_id = $1 AND ${activeExpenseClause()} AND transaction_date >= $2 AND transaction_date <= $3`,
        [req.user.id, from, to],
      ),
      pool.query(
        `SELECT category_id, COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
         FROM budget_transactions
         WHERE user_id = $1 AND ${activeExpenseClause()} AND transaction_date >= $2 AND transaction_date <= $3
         GROUP BY category_id
         ORDER BY total DESC`,
        [req.user.id, from, to],
      ),
      pool.query(
        `SELECT row_data FROM budget_transactions
         WHERE user_id = $1 AND ${activeExpenseClause()} AND transaction_date >= $2 AND transaction_date <= $3
         ORDER BY transaction_date DESC, created_at DESC
         LIMIT 5`,
        [req.user.id, from, to],
      ),
      pool.query(
        "SELECT COUNT(*)::INT AS count FROM budget_transactions WHERE user_id = $1 AND status IN ('pending_review', 'duplicate')",
        [req.user.id],
      ),
    ]);

    res.json({
      month: from,
      totalSpent: spendResult.rows[0]?.total_spent ?? 0,
      categoryTotals: categoryResult.rows.map(row => ({
        categoryID: row.category_id,
        total: row.total,
        count: row.count,
      })),
      recentTransactions: recentResult.rows.map(row => row.row_data),
      pendingReviewCount: pendingResult.rows[0]?.count ?? 0,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load dashboard summary.' });
  }
});

app.get('/api/reports/summary', requireSessionAuth, async (req, res) => {
  try {
    await ensureUserTransactionsMigrated(req.user.id);
    const filtered = transactionSummaryFilters(req.user.id, req.query);
    const nonDate = transactionSummaryFilters(req.user.id, req.query, { includeDate: false });
    const currentMonth = monthKey();
    const currentStart = `${currentMonth}-01`;
    const currentEnd = todayKey();
    const currentMonthEnd = monthEndKey(currentMonth);
    const comparisonMonth = String(req.query.comparisonMonth || currentMonth);
    const compareStart = `${comparisonMonth}-01`;
    const currentDay = Number(currentEnd.slice(-2));
    const compareEndDay = Math.min(currentDay, Number(monthEndKey(comparisonMonth).slice(-2)));
    const compareEnd = `${comparisonMonth}-${String(compareEndDay).padStart(2, '0')}`;

    const filteredTotals = await pool.query(
      `SELECT COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
       FROM budget_transactions WHERE ${filtered.where}`,
      filtered.values,
    );
    const categoryTotals = await pool.query(
      `SELECT category_id, COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
       FROM budget_transactions WHERE ${filtered.where}
       GROUP BY category_id ORDER BY total DESC`,
      filtered.values,
    );
    const topMerchants = await pool.query(
      `SELECT normalized_merchant_name, MIN(merchant_name) AS name, COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
       FROM budget_transactions WHERE ${filtered.where}
       GROUP BY normalized_merchant_name ORDER BY total DESC LIMIT 5`,
      filtered.values,
    );

    async function totalForRange(start, end) {
      const values = [...nonDate.values, start, end];
      const result = await pool.query(
        `SELECT COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
         FROM budget_transactions
         WHERE ${nonDate.where} AND transaction_date >= $${values.length - 1} AND transaction_date <= $${values.length}`,
        values,
      );
      return result.rows[0] ?? { total: 0, count: 0 };
    }

    async function categoriesForRange(start, end) {
      const values = [...nonDate.values, start, end];
      const result = await pool.query(
        `SELECT category_id, COALESCE(SUM(amount), 0)::FLOAT AS total, COUNT(*)::INT AS count
         FROM budget_transactions
         WHERE ${nonDate.where} AND transaction_date >= $${values.length - 1} AND transaction_date <= $${values.length}
         GROUP BY category_id ORDER BY total DESC`,
        values,
      );
      return result.rows.map(row => ({ categoryID: row.category_id, total: row.total, count: row.count }));
    }

    const [current, currentMonthTotal, compare, currentCategories, compareCategories] = await Promise.all([
      totalForRange(currentStart, currentEnd),
      totalForRange(currentStart, currentMonthEnd),
      totalForRange(compareStart, compareEnd),
      categoriesForRange(currentStart, currentEnd),
      categoriesForRange(compareStart, compareEnd),
    ]);

    const delta = (current.total ?? 0) - (compare.total ?? 0);
    const pct = (compare.total ?? 0) > 0 ? (delta / compare.total) * 100 : 0;
    res.json({
      filteredTotal: filteredTotals.rows[0]?.total ?? 0,
      filteredCount: filteredTotals.rows[0]?.count ?? 0,
      categoryTotals: categoryTotals.rows.map(row => ({ categoryID: row.category_id, total: row.total, count: row.count })),
      topMerchants: topMerchants.rows.map(row => ({ name: row.name, total: row.total, count: row.count })),
      comparison: {
        currentKey: currentMonth,
        comparisonMonth,
        currentTotal: current.total ?? 0,
        currentMonthTotal: currentMonthTotal.total ?? 0,
        compareTotal: compare.total ?? 0,
        delta,
        pct,
        currentStart,
        currentEnd,
        currentMonthEnd,
        compareStart,
        compareEnd,
        currentDay,
        compareEndDay,
        currentCategories,
        compareCategories,
      },
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load report summary.' });
  }
});

// ─── Auth: Password (web) ────────────────────────────────────────────────────

app.post('/api/auth/password', (req, res) => {
  try {
    if (!process.env.WEB_PASSWORD) {
      return res.status(503).json({ error: 'Web login is not configured on this server.' });
    }
    const { password } = req.body;
    if (!password || password !== process.env.WEB_PASSWORD) {
      return res.status(401).json({ error: 'Incorrect password.' });
    }
    res.json({ sessionToken: signSessionToken({ id: 'web:owner' }) });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});

// ─── Auth: Sign in with Apple ─────────────────────────────────────────────────

app.post('/api/auth/apple', async (req, res) => {
  try {
    const { identityToken } = req.body;
    if (!identityToken) {
      return res.status(400).json({ error: 'identityToken is required.' });
    }

    const user = await verifyAppleIdentityToken(identityToken);
    res.json({ sessionToken: signSessionToken(user) });
  } catch (error) {
    console.error(error);
    res.status(401).json({ error: 'Could not verify Apple sign-in.' });
  }
});

// ─── Plaid: create link token ─────────────────────────────────────────────────

app.post('/api/plaid/link-token', requireSessionAuth, async (req, res) => {
  try {
    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: req.user.id },
      client_name: 'BudgetSnap',
      products: [Products.Transactions],
      country_codes: [CountryCode.Us],
      language: 'en',
    });
    res.json({ linkToken: response.data.link_token });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not create Plaid link token.' });
  }
});

// ─── Plaid: exchange public token ─────────────────────────────────────────────

app.post('/api/plaid/exchange-token', requireSessionAuth, async (req, res) => {
  try {
    const { publicToken, institutionName, institutionId } = req.body;
    if (!publicToken) return res.status(400).json({ error: 'publicToken is required.' });

    const exchangeResponse = await plaidClient.itemPublicTokenExchange({ public_token: publicToken });
    const { access_token, item_id } = exchangeResponse.data;

    const entry = {
      id: crypto.randomUUID(),
      userID: req.user.id,
      institutionName: institutionName || 'Unknown',
      institutionId: institutionId || '',
      accessToken: access_token,
      itemId: item_id,
      linkedAt: new Date().toISOString(),
    };

    await upsertToken(entry);
    res.json({ ok: true, institutionName: entry.institutionName, itemId: item_id });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not exchange Plaid token.' });
  }
});

// ─── Plaid: list linked accounts ──────────────────────────────────────────────

app.get('/api/plaid/accounts', requireSessionAuth, async (req, res) => {
  try {
    const tokens = await readTokens();
    const accounts = tokens
      .filter(token => token.userID === req.user.id)
      .map(({ id, institutionName, institutionId, itemId, linkedAt, lastSyncedAt }) => ({
        id, institutionName, institutionId, itemId, linkedAt, lastSyncedAt,
      }));
    res.json({ accounts });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load linked accounts.' });
  }
});

// ─── Plaid: disconnect account ───────────────────────────────────────────────

app.delete('/api/plaid/accounts/:itemId', requireSessionAuth, async (req, res) => {
  try {
    const tokens = await readTokens();
    const token = tokens.find(t => t.userID === req.user.id && t.itemId === req.params.itemId);
    if (!token) return res.status(404).json({ error: 'Linked account not found.' });
    try {
      await plaidClient.itemRemove({ access_token: token.accessToken });
    } catch (error) {
      console.warn('Plaid item removal failed; deleting local token anyway.', error?.message);
    }
    const deleted = await deleteToken(req.user.id, req.params.itemId);
    if (!deleted) return res.status(404).json({ error: 'Linked account not found.' });
    res.json({ ok: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not disconnect linked account.' });
  }
});

// ─── Plaid: sync transactions ─────────────────────────────────────────────────

app.post('/api/plaid/sync', requireSessionAuth, async (req, res) => {
  try {
    const { itemId } = req.body;
    const tokens = await readTokens();
    const userTokens = tokens.filter(t => t.userID === req.user.id);
    const targets = itemId ? userTokens.filter(t => t.itemId === itemId) : userTokens;

    if (targets.length === 0) {
      return res.status(404).json({ error: 'No linked accounts found.' });
    }

    // Default to last 30 days unless a complete date range is provided.
    const now = new Date();
    const thirtyDaysAgo = new Date(now);
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const hasDateRange = Boolean(req.body.startDate || req.body.endDate);
    if (hasDateRange && (!isDateKey(req.body.startDate) || !isDateKey(req.body.endDate))) {
      return res.status(400).json({ error: 'A valid startDate and endDate are required for custom date ranges.' });
    }
    if (hasDateRange && req.body.startDate > req.body.endDate) {
      return res.status(400).json({ error: 'startDate must be before or equal to endDate.' });
    }
    const startDate = hasDateRange ? req.body.startDate : thirtyDaysAgo.toISOString().slice(0, 10);
    const endDate = hasDateRange ? req.body.endDate : now.toISOString().slice(0, 10);

    let allRaw = [];
    const syncedAt = new Date().toISOString();
    for (const token of targets) {
      let offset = 0;
      let total = 0;
      do {
        const txnResponse = await plaidClient.transactionsGet({
          access_token: token.accessToken,
          start_date: startDate,
          end_date: endDate,
          options: { count: 500, offset },
        });
        allRaw.push(...txnResponse.data.transactions);
        total = txnResponse.data.total_transactions;
        offset += txnResponse.data.transactions.length;
      } while (offset < total);
      await updateTokenLastSynced(req.user.id, token.itemId, syncedAt);
    }

    // Exclude pending and credits (Plaid: positive amount = debit/expense)
    const expenses = allRaw.filter(t => !t.pending && t.amount > 0);
    const categorized = await categorizePlaidTransactions(expenses);

    res.json({
      importBatchID: crypto.randomUUID(),
      status: 'processed',
      transactions: categorized.transactions,
      warnings: categorized.warnings,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not sync transactions.' });
  }
});

// ─── Legacy: screenshot import (kept until Plaid flow is confirmed) ───────────

app.post('/api/imports/screenshots/process', requireSessionAuth, async (req, res) => {
  try {
    const texts = req.body?.texts || [];

    if (!Array.isArray(texts) || texts.length === 0) {
      return res.status(400).json({ error: 'No screenshot text provided.' });
    }
    if (texts.length > MAX_TEXTS_PER_REQUEST) {
      return res.status(400).json({ error: `Too many screenshots. Maximum is ${MAX_TEXTS_PER_REQUEST} per request.` });
    }

    const combinedText = texts
      .map((t, i) => `--- Screenshot ${i + 1} ---\n${t}`)
      .join('\n\n');

    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: screenshotSystemPrompt() },
        { role: 'user', content: `Extract financial transactions from the following OCR text from ${texts.length} screenshot(s):\n\n${combinedText}` }
      ]
    });

    const parsed = JSON.parse(response.choices[0].message.content);
    const transactions = normalizeScreenshotTransactions(parsed.transactions || []);

    res.json({
      importBatchID: crypto.randomUUID(),
      status: 'processed',
      transactions,
      warnings: parsed.warnings || []
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not process screenshots.' });
  }
});

function screenshotSystemPrompt() {
  return `You extract transaction records from financial screenshots for a budgeting app.

Return strict JSON only. No markdown. No prose.

Schema:
{
  "transactions": [
    {
      "merchant_name": "string",
      "normalized_merchant_name": "string",
      "transaction_date": "YYYY-MM-DD or null",
      "amount": 0,
      "currency": "USD",
      "transaction_type": "expense | payment_out | payment_in | credit | refund | unknown",
      "suggested_category_id": "string",
      "confidence": 0,
      "raw_text": "string",
      "duplicate_risk": false
    }
  ],
  "warnings": [
    {
      "type": "string",
      "message": "string"
    }
  ]
}

Allowed category IDs:
${allowedCategoryIDs.join(', ')}

Rules:
- Extract only visible transactions.
- Do not invent missing transactions.
- Preserve dates as accurately as possible.
- Use null when a date is not visible.
- Treat expenses as positive spending values.
- Identify payments, credits, and refunds separately when visible.
- Use USD unless another currency is visible.
- Use cat_misc if no category is clear.
- Confidence must be between 0 and 1.
- Include raw source text for traceability.
- Mark possible overlapping/repeated rows with duplicate_risk true.`;
}

function normalizeScreenshotTransactions(transactions) {
  return transactions
    .filter((t) => t && t.merchant_name)
    .map((t) => ({
      merchantName: String(t.merchant_name || '').trim(),
      normalizedMerchantName: String(t.normalized_merchant_name || t.merchant_name || '').trim(),
      transactionDate: t.transaction_date || null,
      amount: Number(t.amount || 0),
      currency: String(t.currency || 'USD').toUpperCase(),
      suggestedCategoryID: allowedCategoryIDs.includes(t.suggested_category_id) ? t.suggested_category_id : 'cat_misc',
      confidence: clamp(Number(t.confidence ?? 0.5), 0, 1),
      rawText: String(t.raw_text || ''),
      transactionType: normalizeTransactionType(t.transaction_type),
      duplicateRisk: Boolean(t.duplicate_risk),
    }));
}

function normalizeTransactionType(type) {
  const allowed = new Set(['expense', 'payment_out', 'payment_in', 'credit', 'refund', 'unknown']);
  return allowed.has(type) ? type : 'unknown';
}

function clamp(value, min, max) {
  if (Number.isNaN(value)) return min;
  return Math.min(Math.max(value, min), max);
}

initDB()
  .then(() => app.listen(port, () => console.log(`BudgetSnap API running at http://localhost:${port}`)))
  .catch(err => { console.error('Failed to initialize database:', err); process.exit(1); });
