const columns = ['id', 'external_id', 'merchant_name', 'normalized_merchant_name',
  'transaction_date', 'amount', 'currency', 'category_id', 'status', 'category_source',
  'confidence', 'raw_text', 'duplicate_risk', 'transaction_type', 'created_at', 'updated_at', 'row_data'];
const definitions = columns.map(column => `${column} ${column === 'row_data' ? 'JSONB'
  : column === 'duplicate_risk' ? 'BOOLEAN' : ['amount', 'confidence'].includes(column) ? 'NUMERIC' : 'TEXT'}`).join(', ');

// All writes for a user acquire the settings-row lock first. This also keeps
// compatibility saves from interleaving with a transaction edit.
export async function saveChanges(pool, userID, changes, rowValues) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      INSERT INTO user_data (user_id, data, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (user_id) DO UPDATE SET
        data = user_data.data || EXCLUDED.data, updated_at = NOW()
    `, [userID, changes.settings]);

    if (changes.transactions.length) {
      const rows = changes.transactions.map(transaction => {
        const values = rowValues(userID, transaction).slice(1);
        return Object.fromEntries(columns.map((column, index) => [column, values[index]]));
      });
      await client.query(`
        INSERT INTO budget_transactions (user_id, ${columns.join(', ')})
        SELECT $1, ${columns.join(', ')}
        FROM jsonb_to_recordset($2::jsonb) AS incoming(${definitions})
        WHERE TRUE
        ON CONFLICT (user_id, id) DO UPDATE SET
          ${columns.filter(column => column !== 'id').map(column => `${column} = EXCLUDED.${column}`).join(', ')}
      `, [userID, JSON.stringify(rows)]);
    }
    if (changes.deletedIDs.length) {
      await client.query('DELETE FROM budget_transactions WHERE user_id = $1 AND id = ANY($2::text[])',
        [userID, changes.deletedIDs]);
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export function validateChanges(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false;
  const { settings, transactions, deletedIDs } = body;
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)
    || Object.hasOwn(settings, 'transactions')) return false;
  if (!Array.isArray(transactions) || !Array.isArray(deletedIDs)) return false;
  const ids = transactions.map(transaction => transaction?.id);
  return ids.every(id => typeof id === 'string' && id.length > 0)
    && new Set(ids).size === ids.length
    && deletedIDs.every(id => typeof id === 'string' && id.length > 0)
    && !deletedIDs.some(id => ids.includes(id));
}
