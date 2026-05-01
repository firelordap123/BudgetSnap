# BudgetSnap API

Small local backend for screenshot-to-transaction parsing.

## Setup

1. Copy the environment file:

   ```sh
   cp .env.example .env
   ```

2. Put your OpenAI API key in `.env`:

   ```env
   OPENAI_API_KEY=sk-your-key-here
   PORT=3000
   ```

3. Install dependencies:

   ```sh
   npm install
   ```

4. Run the API:

   ```sh
   npm run dev
   ```

The iOS app points to `http://localhost:3000` for simulator testing.

## Endpoint

```http
POST /api/imports/screenshots/process
```

Request body:

```json
{
  "images": ["base64-image-data"]
}
```

The API returns the shape expected by `URLSessionImportAPIClient`.
