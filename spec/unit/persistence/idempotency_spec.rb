# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Persistent idempotency" do
  def enqueue(database, key: "transaction", name: "Coffee")
    Challenge::UseCases::EnqueueProductCreation.new(
      job_repository: Challenge::Persistence::JobRepository.new(database),
      clock: FrozenClock.new, delay_seconds: 5
    ).call(name: name, requested_by_user_id: "1", idempotency_key: key)
  end

  it "survives reopening the database and enforces uniqueness on direct inserts" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "jobs.sqlite3")
      database = Challenge::Persistence::Database.new(path).setup!
      original = enqueue(database)
      database.close
      database = Challenge::Persistence::Database.new(path).setup!
      expect(enqueue(database).id).to eq(original.id)
      expect { enqueue(database, name: "Tea") }
        .to raise_error(Challenge::UseCases::EnqueueProductCreation::IdempotencyConflict)
      expect do
        database.execute(
          "INSERT INTO jobs (id, product_id, product_name, idempotency_key, requested_by_user_id, status, run_at, created_at, updated_at) " \
          "SELECT ?, product_id, product_name, idempotency_key, requested_by_user_id, " \
          "status, run_at, created_at, updated_at FROM jobs WHERE id = ?", ["duplicate", original.id]
        )
      end.to raise_error(SQLite3::ConstraintException)
      database.close
    end
  end

  it "accepts simultaneous retries through independent database connections only once" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "jobs.sqlite3")
      databases = Array.new(6) { Challenge::Persistence::Database.new(path).setup! }
      ready = Queue.new
      start = Queue.new
      threads = databases.map do |database|
        Thread.new do
          ready << true
          start.pop
          enqueue(database)
        end
      end
      6.times { ready.pop }
      6.times { start << true }
      jobs = threads.map(&:value)
      expect(jobs.map(&:id).uniq.size).to eq(1)
      expect(jobs.map(&:product_id).uniq.size).to eq(1)
      expect(databases.first.execute("SELECT COUNT(*) AS n FROM jobs").first["n"]).to eq(1)
    ensure
      databases&.each(&:close)
    end
  end
end
