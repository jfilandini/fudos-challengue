# frozen_string_literal: true

port Integer(ENV.fetch("PORT", 9292))
environment ENV.fetch("RACK_ENV", "development")
threads Integer(ENV.fetch("PUMA_MIN_THREADS", 1)), Integer(ENV.fetch("PUMA_MAX_THREADS", 5))

# Keep a simple single-process server by default. Job claiming also supports
# independent application processes sharing the same local SQLite database.
workers 0
