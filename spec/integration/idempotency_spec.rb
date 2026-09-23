# frozen_string_literal: true

RSpec.describe "Product creation idempotency" do
  def submit(name: "Coffee", key: "transaction-123", user_id: 1)
    post_json "/products", { name: name }, auth_header(user_id).merge("HTTP_IDEMPOTENCY_KEY" => key)
  end

  it "replays the original acceptance without rescheduling or creating another product" do
    submit
    original = json_body
    location = last_response.headers["location"]
    job = container.job_repository.find(original.fetch("job_id"))
    submit
    expect(last_response.status).to eq(202)
    expect(json_body).to eq(original)
    expect(last_response.headers["location"]).to eq(location)
    expect(container.job_repository.find(job.id).run_at).to eq(job.run_at)
    expect(container.database.execute("SELECT COUNT(*) AS n FROM jobs").first["n"]).to eq(1)

    container.process_due_jobs.call
    submit
    expect(last_response.status).to eq(202)
    expect(json_body).to eq(original)
    get location, {}, auth_header
    expect(json_body.fetch("status")).to eq("completed")
    expect(container.database.execute("SELECT COUNT(*) AS n FROM products").first["n"]).to eq(1)
  end

  it "rejects conflicting payloads without changing the original job" do
    submit
    original = json_body
    submit(name: "Tea")
    expect(last_response.status).to eq(409)
    expect(json_body.dig("error", "code")).to eq("idempotency_conflict")
    expect(container.job_repository.find(original.fetch("job_id")).product_name).to eq("Coffee")
    expect(container.database.execute("SELECT COUNT(*) AS n FROM jobs").first["n"]).to eq(1)
  end

  it "scopes keys to the requester and allows distinct keys for the same name" do
    submit
    first = json_body.fetch("job_id")
    submit(user_id: 2)
    second = json_body.fetch("job_id")
    submit(key: "another-transaction")
    expect([first, second, json_body.fetch("job_id")].uniq.size).to eq(3)
  end

  it "does not restart failed jobs on replay" do
    submit
    original = json_body
    container.job_repository.mark_failed(original.fetch("job_id"), container.clock.now)
    submit
    expect(json_body).to eq(original)
    expect(container.job_repository.find(original.fetch("job_id"))).to be_failed
    expect(container.process_due_jobs.call).to eq(0)
  end

  [nil, "", " ", "a" * 129, "invalid key", "invalid/key"].each do |key|
    it "rejects a missing or invalid key #{key.inspect} via the OpenAPI contract" do
      submit(key: key)
      expect(last_response.status).to eq(400)
      expect(json_body.dig("error", "code")).to eq("invalid_request")
      expect(container.database.execute("SELECT COUNT(*) AS n FROM jobs").first["n"]).to eq(0)
    end
  end

  it "accepts a key at the length limit" do
    submit(key: "a" * 128)
    expect(last_response.status).to eq(202)
  end
end
