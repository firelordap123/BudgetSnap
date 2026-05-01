import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cors from 'cors';
import express from 'express';
import OpenAI from 'openai';
import { Configuration, PlaidApi, PlaidEnvironments, Products, CountryCode } from 'plaid';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOKENS_PATH = path.join(__dirname, 'plaid_tokens.json');

const app = express();
const port = process.env.PORT || 3000;

if (!process.env.OPENAI_API_KEY) {
  console.warn('OPENAI_API_KEY is missing. Add it to api/.env before processing imports.');
}
if (!process.env.API_SECRET) {
  console.warn('API_SECRET is missing. The import endpoint will reject all requests until it is set.');
}
if (!process.env.PLAID_CLIENT_ID || !process.env.PLAID_SECRET) {
  console.warn('PLAID_CLIENT_ID or PLAID_SECRET is missing. Plaid endpoints will fail until set.');
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

const allowedCategoryIDs = [
  'cat_housing',
  'cat_groceries',
  'cat_dining',
  'cat_coffee',
  'cat_transit',
  'cat_utilities',
  'cat_shopping',
  'cat_subscriptions',
  'cat_entertainment',
  'cat_health',
  'cat_travel',
  'cat_misc'
];

// Static map: Plaid personal_finance_category.primary → custom category ID
// null = skip this transaction (income, transfers)
const PLAID_STATIC_MAP = {
  FOOD_AND_DRINK:             'cat_dining',
  GROCERY:                    'cat_groceries',
  RENT_AND_UTILITIES:         'cat_utilities',
  HOME_IMPROVEMENT:           'cat_housing',
  LOAN_PAYMENTS:              'cat_housing',
  ENTERTAINMENT:              'cat_entertainment',
  RECREATION:                 'cat_entertainment',
  PERSONAL_CARE:              'cat_health',
  MEDICAL:                    'cat_health',
  TRANSPORTATION:             'cat_transit',
  TRAVEL:                     'cat_travel',
  GOVERNMENT_AND_NON_PROFIT:  'cat_misc',
  BANK_FEES:                  'cat_misc',
  OTHER:                      'cat_misc',
  INCOME:                     null,
  TRANSFER_IN:                null,
  TRANSFER_OUT:               null,
};

// These primaries need OpenAI to inspect the detailed sub-category
const NEEDS_AI = new Set(['GENERAL_MERCHANDISE', 'GENERAL_SERVICES', 'SUBSCRIPTION']);

const MAX_TEXTS_PER_REQUEST = 10;

function requireBearerAuth(req, res, next) {
  const secret = process.env.API_SECRET;
  if (!secret) {
    return res.status(503).json({ error: 'Server is not configured for authenticated requests.' });
  }
  const auth = req.headers['authorization'] || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (token !== secret) {
    return res.status(401).json({ error: 'Unauthorized.' });
  }
  next();
}

// ─── Token file helpers ──────────────────────────────────────────────────────

async function readTokens() {
  try {
    const raw = await fs.readFile(TOKENS_PATH, 'utf8');
    return JSON.parse(raw);
  } catch {
    return [];
  }
}

async function writeTokens(tokens) {
  await fs.writeFile(TOKENS_PATH, JSON.stringify(tokens, null, 2));
}

// ─── Plaid categorizer ───────────────────────────────────────────────────────

function buildTransactionDTO(t, categoryID, confidence) {
  const name = t.merchant_name || t.name || '';
  const normalized = name.trim().toUpperCase().replace(/[^A-Z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
  const safeCategory = allowedCategoryIDs.includes(categoryID) ? categoryID : 'cat_misc';
  return {
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

async function classifyWithOpenAI(transactions) {
  const items = transactions
    .map((t, i) => `${i + 1}. merchant="${t.merchant_name || t.name}" plaid_category="${t.personal_finance_category?.detailed ?? ''}"`)
    .join('\n');

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: plaidCategorizationPrompt() },
      { role: 'user', content: `Classify these transactions:\n${items}` }
    ]
  });

  const parsed = JSON.parse(response.choices[0].message.content);
  return (parsed.results || []).map((r, i) =>
    buildTransactionDTO(transactions[i], r.category_id, 0.85)
  );
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
    if (mapped === null) continue; // skip income/transfers
    results.push(buildTransactionDTO(t, mapped ?? 'cat_misc', 1.0));
  }

  // Batch OpenAI calls (20 per request to stay under token limit)
  const BATCH_SIZE = 20;
  for (let i = 0; i < aiQueue.length; i += BATCH_SIZE) {
    const batch = aiQueue.slice(i, i + BATCH_SIZE);
    const aiResults = await classifyWithOpenAI(batch);
    results.push(...aiResults);
  }

  return results;
}

// ─── Middleware ──────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json({ limit: '25mb' }));

// ─── Health ──────────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'BudgetSnap API' });
});

// ─── Plaid: create link token ─────────────────────────────────────────────────

app.post('/api/plaid/link-token', requireBearerAuth, async (req, res) => {
  try {
    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: 'budgetsnap-user' },
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

app.post('/api/plaid/exchange-token', requireBearerAuth, async (req, res) => {
  try {
    const { publicToken, institutionName, institutionId } = req.body;
    if (!publicToken) return res.status(400).json({ error: 'publicToken is required.' });

    const exchangeResponse = await plaidClient.itemPublicTokenExchange({ public_token: publicToken });
    const { access_token, item_id } = exchangeResponse.data;

    const tokens = await readTokens();
    const existingIndex = tokens.findIndex(t => t.itemId === item_id);
    const entry = {
      id: crypto.randomUUID(),
      institutionName: institutionName || 'Unknown',
      institutionId: institutionId || '',
      accessToken: access_token,
      itemId: item_id,
      linkedAt: new Date().toISOString(),
    };

    if (existingIndex >= 0) {
      tokens[existingIndex] = entry;
    } else {
      tokens.push(entry);
    }

    await writeTokens(tokens);
    res.json({ ok: true, institutionName: entry.institutionName, itemId: item_id });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not exchange Plaid token.' });
  }
});

// ─── Plaid: list linked accounts ──────────────────────────────────────────────

app.get('/api/plaid/accounts', requireBearerAuth, async (req, res) => {
  try {
    const tokens = await readTokens();
    const accounts = tokens.map(({ id, institutionName, institutionId, itemId, linkedAt }) => ({
      id, institutionName, institutionId, itemId, linkedAt,
    }));
    res.json({ accounts });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not load linked accounts.' });
  }
});

// ─── Plaid: sync transactions ─────────────────────────────────────────────────

app.post('/api/plaid/sync', requireBearerAuth, async (req, res) => {
  try {
    const { itemId } = req.body;
    const tokens = await readTokens();
    const targets = itemId ? tokens.filter(t => t.itemId === itemId) : tokens;

    if (targets.length === 0) {
      return res.status(404).json({ error: 'No linked accounts found.' });
    }

    // Default to current calendar month
    const now = new Date();
    const startDate = req.body.startDate || new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
    const endDate = req.body.endDate || now.toISOString().slice(0, 10);

    let allRaw = [];
    for (const token of targets) {
      const txnResponse = await plaidClient.transactionsGet({
        access_token: token.accessToken,
        start_date: startDate,
        end_date: endDate,
        options: { count: 500, offset: 0 },
      });
      allRaw.push(...txnResponse.data.transactions);
    }

    // Exclude pending and credits (Plaid: positive amount = debit/expense)
    const expenses = allRaw.filter(t => !t.pending && t.amount > 0);
    const transactions = await categorizePlaidTransactions(expenses);

    res.json({
      importBatchID: crypto.randomUUID(),
      status: 'processed',
      transactions,
      warnings: [],
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Could not sync transactions.' });
  }
});

// ─── Legacy: screenshot import (kept until Plaid flow is confirmed) ───────────

app.post('/api/imports/screenshots/process', requireBearerAuth, async (req, res) => {
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
      "transaction_type": "expense | credit | refund | unknown",
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
- Identify credits and refunds separately when visible.
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
  const allowed = new Set(['expense', 'credit', 'refund', 'unknown']);
  return allowed.has(type) ? type : 'unknown';
}

function clamp(value, min, max) {
  if (Number.isNaN(value)) return min;
  return Math.min(Math.max(value, min), max);
}

app.listen(port, () => {
  console.log(`BudgetSnap API running at http://localhost:${port}`);
});
