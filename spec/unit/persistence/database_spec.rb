# frozen_string_literal: true

require "tmpdir"

RSpec.describe Challenge::Persistence::Database do
  it "creates the query and idempotency indexes directly from the SQL schema" do
    connection = SQLite3::Database.new(":memory:")
    connection.results_as_hash = true
    connection.execute_batch(File.read(described_class::SCHEMA_PATH))

    columns = connection.execute("PRAGMA index_info(index_products_on_requester_and_order)")
    expect(columns.map { |row| row["name"] }).to eq(%w[requested_by_user_id created_at id])
    indexes = connection.execute("PRAGMA index_list(jobs)")
    expect(indexes).to include(include("name" => "index_jobs_on_requester_and_idempotency_key", "unique" => 1))
    columns = connection.execute("PRAGMA index_info(index_jobs_on_requester_and_idempotency_key)")
    expect(columns.map { |row| row["name"] }).to eq(%w[requested_by_user_id idempotency_key])
  ensure
    connection&.close
  end

  it "preserves records and job state when setup runs again or the database is reopened" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "current.sqlite3")
      database = described_class.new(path).setup!
      jobs = Challenge::Persistence::JobRepository.new(database)
      products = Challenge::Persistence::ProductRepository.new(database)
      now = FrozenClock.new.now
      products.create(id: "existing", name: "Coffee", created_at: now, requested_by_user_id: "1")
      jobs.create(id: "claimed", product_id: "future", product_name: "Tea",
                  run_at: now, now: now, requested_by_user_id: "1", idempotency_key: "original-key")
      jobs.claim_next(now)

      2.times { expect(database.setup!).to equal(database) }
      expect(products.find_for_user("existing", requested_by_user_id: "1")).to have_attributes(name: "Coffee", requested_by_user_id: "1")
      expect(jobs.find_for_user("claimed", requested_by_user_id: "1")).to have_attributes(status: "in_progress", product_id: "future")
      database.close

      database = described_class.new(path).setup!
      jobs = Challenge::Persistence::JobRepository.new(database)
      expect(jobs.find_for_user("claimed", requested_by_user_id: "1")).to be_in_progress
      expect(database.execute("SELECT idempotency_key FROM jobs").first["idempotency_key"]).to eq("original-key")
      expect(jobs.claim_next(now)).to be_nil
      expect(Challenge::Persistence::ProductRepository.new(database).find_for_user("existing", requested_by_user_id: "1").name).to eq("Coffee")
    ensure
      database&.close
    end
  end
end
