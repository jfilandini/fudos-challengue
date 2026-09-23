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

## The asynchronous flow

```bash
BASE=http://localhost:9292

TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password123"}' | ruby -rjson -e 'puts JSON.parse(STDIN.read)["token"]')

curl -s -X POST "$BASE/products" \
  -H "Authorization: Bearer $TOKEN" \
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

[`SUMMARY.md`](SUMMARY.md) explains the decisions and their trade-offs in full.
