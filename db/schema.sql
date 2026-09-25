CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_digest TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  requested_by_user_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  product_name TEXT NOT NULL,
  idempotency_key TEXT,
  requested_by_user_id TEXT,
  status TEXT NOT NULL,
  run_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_jobs_on_status_and_run_at ON jobs (status, run_at);
CREATE INDEX IF NOT EXISTS index_products_on_created_at ON products (created_at);

CREATE INDEX IF NOT EXISTS index_products_on_requester_and_order
  ON products (requested_by_user_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS index_jobs_on_requester_and_idempotency_key
  ON jobs (requested_by_user_id, idempotency_key);
