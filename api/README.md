# BudgetSnap API

Small backend for Plaid transaction sync and legacy screenshot-to-transaction parsing.

## Setup

1. Copy the environment file:

   ```sh
   cp .env.example .env
   ```

2. Fill in `.env`:

   ```env
   OPENAI_API_KEY=sk-your-key-here
   APPLE_CLIENT_ID=firelordAP.BudgetSnap
   SESSION_SECRET=your-long-random-session-secret
   TOKEN_ENCRYPTION_KEY=your-long-random-token-encryption-key
   PORT=3000
   PLAID_CLIENT_ID=your-plaid-client-id
   PLAID_SECRET=your-plaid-sandbox-secret
   PLAID_ENV=sandbox
   ```

3. Install dependencies:

   ```sh
   npm install
   ```

4. Run the API:

   ```sh
   npm run dev
   ```

`APPLE_CLIENT_ID` must match the app bundle identifier configured for Sign in with Apple.

## Plaid endpoints

```http
POST /api/plaid/link-token
POST /api/plaid/exchange-token
GET /api/plaid/accounts
POST /api/plaid/sync
```

All Plaid endpoints require a session token returned by `POST /api/auth/apple`:

```http
Authorization: Bearer session-token
```

Plaid access tokens are written to `plaid_tokens.json` encrypted with `TOKEN_ENCRYPTION_KEY`.

## Legacy screenshot endpoint

```http
POST /api/imports/screenshots/process
```

Request body:

```json
{
  "texts": ["OCR text from a screenshot"]
}
```
