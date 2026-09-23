# frozen_string_literal: true

port Integer(ENV.fetch("PORT", 9292))
environment ENV.fetch("RACK_ENV", "development")
threads Integer(ENV.fetch("PUMA_MIN_THREADS", 1)), Integer(ENV.fetch("PUMA_MAX_THREADS", 5))

# The product worker runs inside this process, so a second forked worker would
# race it for the same due jobs.
workers 0
