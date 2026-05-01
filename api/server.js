import 'dotenv/config';
import crypto from 'node:crypto';
import cors from 'cors';
import express from 'express';
import OpenAI from 'openai';

const app = express();
const port = process.env.PORT || 3000;

if (!process.env.OPENAI_API_KEY) {
  console.warn('OPENAI_API_KEY is missing. Add it to api/.env before processing imports.');
}

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

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

app.use(cors());
app.use(express.json({ limit: '25mb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'BudgetSnap API' });
});

app.post('/api/imports/screenshots/process', async (req, res) => {
  try {
    const images = req.body?.images || [];

    if (!Array.isArray(images) || images.length === 0) {
      return res.status(400).json({ error: 'No screenshots uploaded.' });
    }

    const imageInputs = images.map((base64) => ({
      type: 'input_image',
      image_url: `data:image/jpeg;base64,${base64}`
    }));

    const response = await openai.responses.create({
      model: 'gpt-5-nano',
      input: [
        {
          role: 'system',
          content: [
            {
              type: 'input_text',
              text: systemPrompt()
            }
          ]
        },
        {
          role: 'user',
          content: [
            {
              type: 'input_text',
              text: 'Extract visible financial transactions from these screenshots.'
            },
            ...imageInputs
          ]
        }
      ],
      text: {
        format: {
          type: 'json_object'
        }
      }
    });

    const parsed = JSON.parse(response.output_text);
    const transactions = normalizeTransactions(parsed.transactions || []);

    res.json({
      importBatchID: crypto.randomUUID(),
      status: 'processed',
      transactions,
      warnings: parsed.warnings || []
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: 'Could not process screenshots.'
    });
  }
});

function systemPrompt() {
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

function normalizeTransactions(transactions) {
  return transactions
    .filter((transaction) => transaction && transaction.merchant_name)
    .map((transaction) => ({
      merchantName: String(transaction.merchant_name || '').trim(),
      normalizedMerchantName: String(
        transaction.normalized_merchant_name || transaction.merchant_name || ''
      ).trim(),
      transactionDate: transaction.transaction_date || null,
      amount: Number(transaction.amount || 0),
      currency: String(transaction.currency || 'USD').toUpperCase(),
      suggestedCategoryID: allowedCategoryIDs.includes(transaction.suggested_category_id)
        ? transaction.suggested_category_id
        : 'cat_misc',
      confidence: clamp(Number(transaction.confidence ?? 0.5), 0, 1),
      rawText: String(transaction.raw_text || ''),
      transactionType: normalizeTransactionType(transaction.transaction_type),
      duplicateRisk: Boolean(transaction.duplicate_risk)
    }));
}

function normalizeTransactionType(type) {
  const allowedTypes = new Set(['expense', 'credit', 'refund', 'unknown']);
  return allowedTypes.has(type) ? type : 'unknown';
}

function clamp(value, min, max) {
  if (Number.isNaN(value)) return min;
  return Math.min(Math.max(value, min), max);
}

app.listen(port, () => {
  console.log(`BudgetSnap API running at http://localhost:${port}`);
});
