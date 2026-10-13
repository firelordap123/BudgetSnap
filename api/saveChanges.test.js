import test from 'node:test';
import assert from 'node:assert/strict';
import { saveChanges, validateChanges } from './saveChanges.js';

function database(failOnUpsert = false) {
  const queries = [];
  let released = false;
  const client = {
    query: async (sql, values) => {
      queries.push({ sql, values });
      if (failOnUpsert && sql.includes('jsonb_to_recordset')) throw new Error('Database unavailable');
      return { rows: [] };
    },
    release: () => { released = true; },
  };
  return { pool: { connect: async () => client }, queries, released: () => released };
}
const rowValues = (user, transaction) => [user, transaction.id, null, 'Merchant', 'MERCHANT',
  '2026-10-01', 12, 'USD', 'cat_dining', 'accepted', 'user_corrected', 1, '', false,
  'expense', 'created', 'updated', transaction];

test('one edit uses one bulk upsert, scopes writes to its owner, and keeps unrelated rows', async () => {
  const db = database();
  await saveChanges(db.pool, 'owner', { settings: {}, transactions: [{ id: 'edited' }], deletedIDs: [] }, rowValues);
  assert.equal(db.queries.length, 4);
  assert.equal(db.queries[0].sql, 'BEGIN');
  assert.match(db.queries[1].sql, /user_data\.data \|\| EXCLUDED\.data/);
  const upsert = db.queries[2];
  assert.match(upsert.sql, /ON CONFLICT \(user_id, id\) DO UPDATE/);
  assert.equal(upsert.values[0], 'owner');
  assert.deepEqual(JSON.parse(upsert.values[1]).map(row => row.id), ['edited']);
  assert.ok(!db.queries.some(query => query.sql.includes('DELETE FROM')));
  assert.equal(db.queries[3].sql, 'COMMIT');
  assert.ok(db.released());
});

test('a 5000-row import still uses four database queries', async () => {
  const db = database();
  await saveChanges(db.pool, 'owner', { settings: {}, transactions: Array.from({ length: 5000 }, (_, id) => ({ id: String(id) })), deletedIDs: [] }, rowValues);
  assert.equal(db.queries.length, 4);
  assert.equal(JSON.parse(db.queries[2].values[1]).length, 5000);
});

test('delete only removes the requested IDs for the signed-in user', async () => {
  const db = database();
  await saveChanges(db.pool, 'owner', { settings: {}, transactions: [], deletedIDs: ['removed'] }, rowValues);
  assert.match(db.queries[2].sql, /user_id = \$1 AND id = ANY\(\$2::text\[\]\)/);
  assert.deepEqual(db.queries[2].values, ['owner', ['removed']]);
});

test('failure rolls back settings and transaction changes and releases the connection', async () => {
  const db = database(true);
  await assert.rejects(saveChanges(db.pool, 'owner', { settings: { rules: [] }, transactions: [{ id: 'edited' }], deletedIDs: [] }, rowValues), /Database unavailable/);
  assert.equal(db.queries.at(-1).sql, 'ROLLBACK');
  assert.ok(db.released());
});

test('reject malformed, duplicate, and contradictory change sets', () => {
  assert.ok(validateChanges({ settings: {}, transactions: [{ id: 'a' }], deletedIDs: [] }));
  for (const body of [null, {}, { settings: { transactions: [] }, transactions: [], deletedIDs: [] },
    { settings: {}, transactions: [{ id: 'a' }, { id: 'a' }], deletedIDs: [] },
    { settings: {}, transactions: [{ id: 'a' }], deletedIDs: ['a'] },
    { settings: {}, transactions: [null], deletedIDs: [] }]) assert.equal(validateChanges(body), false);
});
