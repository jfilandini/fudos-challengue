# frozen_string_literal: true

RSpec.describe "GET /jobs/{id}" do
  def enqueue_product
    post_json "/products", { name: "Laptop" }, auth_header
    json_body
  end

  def read_job(id)
    get "/jobs/#{id}", {}, auth_header
  end

  it "reports the job as pending while the work is outstanding" do
    created = enqueue_product

    read_job(created["job_id"])

    expect(last_response.status).to eq(200)
    expect(json_body).to include("status" => "pending", "product_id" => created["product_id"])
  end

  it "exposes a claimed job as in_progress without exposing its claim token" do
    created = enqueue_product
    container.job_repository.claim_next(container.clock.now)
    read_job(created["job_id"])
    expect(last_response.status).to eq(200)
    expect(json_body).to include("status" => "in_progress")
    expect(json_body).to have_key("updated_at")
    expect(json_body).not_to have_key("claim_token")
  end

  it "reports the job as completed once the worker has run" do
    created = enqueue_product
    container.process_due_jobs.call

    read_job(created["job_id"])

    expect(json_body).to include("status" => "completed")
  end

  it "has created the product the job described" do
    created = enqueue_product
    container.process_due_jobs.call

    expect(container.product_repository.find(created["product_id"])).to have_attributes(name: "Laptop")
  end

  it "answers for a job that does not exist" do
    read_job("missing")

    expect(last_response.status).to eq(404)
    expect(json_body["error"]).to include("code" => "not_found")
  end
end
