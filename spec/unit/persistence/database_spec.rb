# frozen_string_literal: true

require "tmpdir"

RSpec.describe Challenge::Persistence::Database do
  it "removes obsolete claim tokens without losing job state or idempotency keys" do
    database = described_class.new(":memory:").setup!
    database.execute("ALTER TABLE jobs ADD COLUMN claim_token TEXT")
    jobs = Challenge::Persistence::JobRepository.new(database)
    now = FrozenClock.new.now
    job = jobs.create(id: "claimed", product_id: "future", product_name: "Coffee",
                      run_at: now, now: now, requested_by_user_id: "1", idempotency_key: "original-key")
    jobs.claim_next(now)
    database.execute("UPDATE jobs SET claim_token = ? WHERE id = ?", ["old-token", job.id])

    database.setup!
    database.setup!

    expect(database.execute("PRAGMA table_info(jobs)").map { |row| row["name"] }).not_to include("claim_token")
    expect(jobs.find(job.id)).to have_attributes(status: "in_progress", product_id: "future", requested_by_user_id: "1")
    expect(database.execute("SELECT idempotency_key FROM jobs WHERE id = ?", [job.id]).first["idempotency_key"])
      .to eq("original-key")
    expect(jobs.claim_next(now)).to be_nil
    jobs.mark_completed(job.id, now)
    expect(jobs.find(job.id)).to be_completed
    database.close
  end

  it "upgrades existing tables without losing products or pending jobs and can run repeatedly" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "legacy.sqlite3")
      old = SQLite3::Database.new(path)
      schema = File.read(described_class::SCHEMA_PATH).gsub("  requested_by_user_id TEXT,\n", "").gsub("  idempotency_key TEXT,\n", "").gsub("  claim_token TEXT,\n", "")
      old.execute_batch(schema)
      timestamp = "2026-09-18T12:00:00.000Z"
      old.execute("INSERT INTO products VALUES (?, ?, ?)", ["existing", "Coffee", timestamp])
      old.execute("INSERT INTO jobs VALUES (?, ?, ?, ?, ?, ?, ?)",
                  ["pending", "future", "Tea", "pending", timestamp, timestamp, timestamp])
      old.close

      database = described_class.new(path).setup!
      database.setup!
      products = Challenge::Persistence::ProductRepository.new(database)
      jobs = Challenge::Persistence::JobRepository.new(database)
      expect(products.find("existing")).to have_attributes(name: "Coffee", requested_by_user_id: nil)
      expect(jobs.find("pending")).to have_attributes(status: "pending", requested_by_user_id: nil)

      Challenge::UseCases::ProcessDueJobs.new(
        job_repository: jobs, product_repository: products, unit_of_work: database,
        clock: FrozenClock.new
      ).call
      expect(products.find("future")).to have_attributes(name: "Tea", requested_by_user_id: nil)
      expect(jobs.find("pending")).to be_completed
      database.close

      reopened = described_class.new(path).setup!
      expect(Challenge::Persistence::ProductRepository.new(reopened).find("future").name).to eq("Tea")
      reopened.close
    end
  end
end
