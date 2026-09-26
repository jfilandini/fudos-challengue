# frozen_string_literal: true

# Run in a fresh Ruby process so no SQLite connections are inherited from RSpec.
require_relative "../../app/boot"
require_relative "../support/frozen_clock"

database = Challenge::Persistence::Database.new(ARGV.fetch(0)).setup!
clock = FrozenClock.new
jobs = Challenge::Persistence::JobRepository.new(database)
products = Challenge::Persistence::ProductRepository.new(database)
ready = IO.new(3, "w")

if ARGV.fetch(1) == "crash"
  job = jobs.claim_next(clock.now)
  database.transaction(mode: :immediate) do
    products.create(requested_by_user_id: job.requested_by_user_id, id: job.product_id, name: job.product_name, created_at: clock.now)
    ready.write("!")
    ready.flush
    sleep 30 # The parent terminates this process before the transaction commits.
  end
else
  ready.write("ready")
  ready.close
  IO.new(4, "r").read(1)
  Challenge::UseCases::ProcessDueJobs.new(
    job_repository: jobs, product_repository: products, unit_of_work: database, clock: clock
  ).call
end

database.close
