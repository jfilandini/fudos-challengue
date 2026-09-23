# Products API

A Rack application in Ruby, without Rails, exposing a JSON API with authentication,
asynchronous product creation and product querying.

The OpenAPI contract in [`openapi.yaml`](openapi.yaml) is written first and enforced at
runtime: every request is validated against it before reaching a route.

## Requirements

Either Docker, or Ruby 3.2.2 with Bundler.

## Running with Docker

```bash
docker compose up
```

The API listens on <http://localhost:9292>. The schema is created and a demo user seeded
on every boot, and the SQLite file lives in a named volume so data survives a restart.

## Running locally

```bash
bundle install
bundle exec rake db:setup db:seed
bundle exec puma -C config/puma.rb
```

With `RACK_ENV` unset, both Puma and the application default to `development`,
so these commands work without setting `JWT_SECRET`. The development signing
secret is for local use only. For an explicit production launch, set
`RACK_ENV=production` and provide `JWT_SECRET`; startup fails if the secret is
missing. Docker explicitly sets `RACK_ENV=production` and Compose supplies its
configured secret.

## Credentials

The seeded user is `admin` / `password123`. Override with `SEED_USERNAME` and
`SEED_PASSWORD` before seeding.

## Tests

```bash
bundle exec rspec
```

Unit specs cover use cases, repositories and middleware without HTTP. Integration specs
drive the full Rack stack. No test waits for the creation delay.

## Endpoints

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/login` | – | Exchange credentials for a bearer token |
| POST | `/products` | Bearer | Request an asynchronous product creation |
| GET | `/products` | Bearer | List the products that exist |
| GET | `/products/{id}` | Bearer | Read one product |
| GET | `/jobs/{id}` | Bearer | Follow the progress of a creation |
| GET | `/health` | – | Liveness probe |
| GET | `/openapi.yaml` | – | The contract, never cached |
| GET | `/AUTHORS` | – | Authorship, cached for 24 hours |

Responses are gzipped whenever the client sends `Accept-Encoding: gzip`.

## Product pagination

`GET /products?page=1&per_page=20` returns only completed products, ordered by
`created_at` descending and then `id` descending for timestamp ties.

- `page`: integer from 1 to 2147483647, defaults to 1.
- `per_page`: integer from 1 to 100, defaults to 20.
- Invalid values return `400` with error code `invalid_request`.
- Pages beyond the last page return `200` with an empty `products` array.
- An empty collection has `total: 0` and `total_pages: 0`.

```bash
curl -s "$BASE/products?page=2&per_page=10" \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "products": [],
  "pagination": { "page": 2, "per_page": 10, "total": 0, "total_pages": 0 }
}
```

The response keeps the `products` array and adds `pagination`. Clients that previously
expected all products in one request must now iterate over pages. The page and total
are read in one database transaction, but separate HTTP requests do not share a
snapshot: newly created products can shift the contents of subsequent pages.

### Scaling to larger datasets

Offset pagination with exact totals is a simplicity trade-off for this challenge.
As the dataset grows, computing `COUNT(*)` on every request can become expensive,
and deep pages require the database to skip increasing numbers of rows. Returning
a next-page number alone would not remove the cost of large offsets.

For larger datasets, prefer cursor (keyset) pagination using the existing stable
order `(created_at DESC, id DESC)` and a matching composite index. An opaque cursor
would identify the last returned product's timestamp and ID, allowing the next
query to seek after that pair instead of using `OFFSET`. Fetching `per_page + 1`
rows would determine `has_more`; return at most `per_page` products and a
`next_cursor` when another page is available, without computing `total` or
`total_pages`. Clients would follow the cursor rather than jump to a page number.
This is a future alternative; the current API still uses the page-based contract
documented above.

## The asynchronous flow

```bash
BASE=http://localhost:9292

TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password123"}' | ruby -rjson -e 'puts JSON.parse(STDIN.read)["token"]')

curl -s -X POST "$BASE/products" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000' \
  -H 'Content-Type: application/json' \
  -d '{"name":"Laptop"}'
# => 202 {"job_id":"...","product_id":"...","status":"pending"}

curl -s "$BASE/jobs/$JOB_ID"     -H "Authorization: Bearer $TOKEN"   # pending
curl -s "$BASE/products/$PRODUCT_ID" -H "Authorization: Bearer $TOKEN"   # 404

# after five seconds
curl -s "$BASE/jobs/$JOB_ID"     -H "Authorization: Bearer $TOKEN"   # completed
curl -s "$BASE/products/$PRODUCT_ID" -H "Authorization: Bearer $TOKEN"   # 200
```

A Postman collection covering the same flow is in
[`postman_collection.json`](postman_collection.json); the login and creation requests
capture the token and identifiers into collection variables automatically.

## Idempotent product creation

`POST /products` requires an `Idempotency-Key` header: a client-generated transaction
ID of 1–128 ASCII letters, digits, underscores or hyphens (a UUID is suitable).
Generate a new key for each intended creation and reuse it for retries. The key is
scoped to the authenticated user's ID by a unique database index on
`jobs(requested_by_user_id, idempotency_key)`, including concurrent submissions.

- Same user, key and exact validated `name`: replay the original `202` acceptance
  body and `Location`, without inserting another job or resetting its due time.
- Same user and key, different `name`: `409` with code `idempotency_conflict`.
- Missing or invalid key: `400`; rejected requests do not reserve a key.
- Different users may reuse a key; different keys may create same-named products.

Replays retain the original acceptance status `pending`, even if the job has since
completed or failed. Follow `Location` (`GET /jobs/{id}`) to obtain current status.
Replaying a failed job does not retry it. Keys survive restarts and have no automatic
expiration; retain job records for as long as the idempotency guarantee is needed.
Existing jobs have null keys and remain processable, but cannot retroactively be
matched to retries. Database setup adds the column and unique index to existing
SQLite databases without dropping data.

This protects HTTP request retries. It does not implement multi-worker job claiming
or automatic retries of failed work; those remain separate concerns. The existing
product primary key and product/job transaction continue to protect product writes.

## Request attribution

The JWT contains the user's ID as the string `sub` claim, not their username.
The API takes that verified identity from the authentication middleware and saves
it as `requested_by_user_id` on the creation job. The worker copies it to the
product when processing that job, preserving who requested creation even though
execution happens later. Both `GET /jobs/{id}` and product query responses expose
this field. It is server-assigned; including it in a creation request is rejected.

Database setup upgrades existing SQLite tables without dropping data. Previously
stored jobs and products have a null requester because their original requester
cannot be reconstructed. Pending legacy jobs remain processable. Attribution is
not an ownership/access-control policy: authenticated users can still query all
products and jobs, as before.

## Production observability

Before operating this API under high concurrency in production, add distributed
tracing, structured logs and metrics collection, for example through an APM tool
such as New Relic. No APM agent or telemetry exporter is currently integrated.

Propagate a request/trace identifier from HTTP acceptance into the persisted job
and link the worker's execution trace to it. Correlate logs using request ID, job
ID and product ID; use the requester ID for attribution where access and retention
policies allow. Do not log passwords, bearer tokens or JWT signing secrets.

Track HTTP throughput, error rates and latency percentiles; pending/failed job
counts; scheduling lag after `run_at`; job processing duration; database query
latency and lock contention; and CPU/memory usage. Alert on sustained backlog,
worker failures and latency/error thresholds. Keep metric labels low-cardinality:
use route templates and status classes, not user, product or job IDs.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `RACK_ENV` | `development` | Response validation runs outside production |
| `DATABASE_PATH` | `db/challenge.sqlite3` | SQLite file, `:memory:` under test |
| `JWT_SECRET` | development fallback | HS256 signing key, required in production |
| `JWT_TTL_SECONDS` | `3600` | Token lifetime |
| `PRODUCT_CREATION_DELAY_SECONDS` | `5` | Creation delay, `0` under test |
| `WORKER_POLL_INTERVAL_SECONDS` | `0.5` | Worker loop interval |
| `SEED_USERNAME` / `SEED_PASSWORD` | `admin` / `password123` | Seeded user |

## Design

The application is organised as a hexagon: Sinatra is an inbound adapter, SQLite an
outbound one, and the rules live in use cases that depend on neither. Creation is
asynchronous through a jobs table drained by a worker thread.

### OpenAPI validation overhead

The `committee` gem validates incoming requests against `openapi.yaml` before
route execution. Response validation also runs in development and tests, but is
disabled in production. Request validation remains enabled in production.

Runtime schema validation adds per-request processing and allocation overhead.
Under high concurrency, this can affect latency and throughput; the impact depends
on payload size, schema complexity and available resources. This project has not
been load-tested, so Committee is a potential bottleneck, not a demonstrated
scalability limit. Benchmark representative traffic and profile validation costs
before changing this trade-off.

If validation becomes a measured bottleneck, consider focused request validators
for hot endpoints while keeping OpenAPI contract checks in CI and integration
tests. Any replacement must preserve required-field, type, size and other input
checks; removing runtime input validation entirely is not the intended optimization.

[`SUMMARY.md`](SUMMARY.md) explains the decisions and their trade-offs in full.
