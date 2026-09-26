# frozen_string_literal: true

RSpec.describe "Resource ownership" do
  def login(username)
    user = container.user_repository.create(username: username, password: "password123", now: container.clock.now)
    post_json "/auth/login", username: username, password: "password123"
    expect(last_response.status).to eq(200)
    [user, { "HTTP_AUTHORIZATION" => "Bearer #{json_body.fetch('token')}" }]
  end

  def create_for(headers, name)
    post_json "/products", { name: name }, headers
    expect(last_response.status).to eq(202)
    json_body
  end

  before do
    @alice, @alice_headers = login("alice")
    @bob, @bob_headers = login("bob")
    @alice_jobs = 3.times.map { |i| create_for(@alice_headers, "Alice #{i}") }
    @bob_jobs = 2.times.map { |i| create_for(@bob_headers, "Bob #{i}") }
    container.process_due_jobs.call
  end

  it "filters both page contents and totals before pagination" do
    get "/products?page=1&per_page=2", {}, @alice_headers
    expect(last_response.status).to eq(200)
    first = json_body.fetch("products")
    expect(first.size).to eq(2)
    expect(first).to all(satisfy { |product| !product.key?("requested_by_user_id") })
    expect(json_body.fetch("pagination")).to eq("page" => 1, "per_page" => 2, "total" => 3, "total_pages" => 2)
    get "/products?page=2&per_page=2", {}, @alice_headers
    second = json_body.fetch("products")
    expect((first + second).map { |p| p.fetch("id") }).to match_array(@alice_jobs.map { |j| j.fetch("product_id") })
    get "/products", {}, @bob_headers
    expect(json_body.fetch("products").map { |p| p.fetch("id") }).to match_array(@bob_jobs.map { |j| j.fetch("product_id") })
    expect(json_body.dig("pagination", "total")).to eq(2)
    expect(last_response.headers["cache-control"]).to eq("no-store")
  end

  it "allows the owner and conceals another user's products and jobs" do
    { "products" => "product_id", "jobs" => "job_id" }.each do |route, key|
      path = "/#{route}/#{@alice_jobs.first.fetch(key)}"
      get path, {}, @alice_headers
      expect(last_response.status).to eq(200)
      get path, {}, @bob_headers
      expect(last_response.status).to eq(404)
      hidden_body = json_body
      get "/#{route}/missing", {}, @bob_headers
      expect(last_response.status).to eq(404)
      expect(json_body).to eq(hidden_body)
    end
  end

  it "does not accept ownership overrides through query parameters or headers" do
    get "/products?requested_by_user_id=#{@bob.id}&user_id=#{@bob.id}", {},
        @alice_headers.merge("HTTP_X_USER_ID" => @bob.id.to_s)
    expect(last_response.status).to eq(200)
    expect(json_body.fetch("products").map { |p| p.fetch("id") }).to match_array(@alice_jobs.map { |job| job.fetch("product_id") })
    expect(json_body.dig("pagination", "total")).to eq(3)
  end

  it "hides legacy records without ownership" do
    # Insert legacy rows directly: current creation calls always supply ownership.
    timestamp = Challenge::Support::Timestamp.serialize(container.clock.now)
    container.database.execute(
      "INSERT INTO products (id, name, created_at) VALUES (?, ?, ?)",
      ["legacy", "Unknown owner", timestamp]
    )
    container.database.execute(
      "INSERT INTO jobs (id, product_id, product_name, status, run_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["legacy-job", "legacy-product", "Unknown", "pending", timestamp, timestamp, timestamp]
    )

    get "/products/legacy", {}, @alice_headers
    expect(last_response.status).to eq(404)
    get "/jobs/legacy-job", {}, @alice_headers
    expect(last_response.status).to eq(404)
  end

  it "returns an empty collection to a user with no products" do
    _, headers = login("charlie")
    get "/products", {}, headers
    expect(json_body.fetch("products")).to eq([])
    expect(json_body.fetch("pagination")).to include("total" => 0, "total_pages" => 0)
  end
end
