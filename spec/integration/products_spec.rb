# frozen_string_literal: true

RSpec.describe "Products" do
  def enqueue_product(name: "Laptop")
    post_json "/products", { name: name }, auth_header
    json_body
  end

  def create_product(name: "Laptop")
    enqueue_product(name: name).tap { container.process_due_jobs.call }
  end

  describe "POST /products" do
    it_behaves_like "a protected endpoint", :post, "/products"

    it "accepts the request and reports it as pending" do
      enqueue_product

      expect(last_response.status).to eq(202)
      expect(json_body).to include("status" => "pending")
      expect(json_body["job_id"]).to be_a(String)
      expect(json_body["product_id"]).to be_a(String)
    end

    it "points the caller at the job that will create the product" do
      created = enqueue_product

      expect(last_response.headers["location"]).to eq("/jobs/#{created['job_id']}")
    end

    it "has not created the product by the time it answers" do
      created = enqueue_product

      expect(container.product_repository.find(created["product_id"])).to be_nil
    end

    it "refuses a name the contract does not allow" do
      post_json "/products", { name: "" }, auth_header

      expect(last_response.status).to eq(400)
      expect(json_body["error"]).to include("code" => "invalid_request")
    end
  end

  describe "GET /products" do
    it_behaves_like "a protected endpoint", :get, "/products"

    it "lists nothing before anything has been created" do
      get "/products", {}, auth_header

      expect(last_response.status).to eq(200)
      expect(json_body).to eq(
        "products" => [],
        "pagination" => { "page" => 1, "per_page" => 20, "total" => 0, "total_pages" => 0 }
      )
    end

    context "pagination" do
      before do
        now = container.clock.now
        23.times do |index|
          container.product_repository.create(
            id: format("product-%02d", index), name: "Product #{index}", created_at: now
          )
        end
        enqueue_product(name: "Still pending")
      end

      it "limits the default page and counts only completed products" do
        get "/products", {}, auth_header

        expect(last_response.status).to eq(200)
        expect(json_body["products"].size).to eq(20)
        expect(json_body["pagination"]).to eq(
          "page" => 1, "per_page" => 20, "total" => 23, "total_pages" => 2
        )
      end

      it "uses query parameters and a deterministic order when timestamps tie" do
        get "/products?page=1&per_page=10", {}, auth_header
        first_ids = json_body.fetch("products").map { |product| product["id"] }
        get "/products?page=2&per_page=10", {}, auth_header
        second_ids = json_body.fetch("products").map { |product| product["id"] }
        get "/products?page=3&per_page=10", {}, auth_header
        third_ids = json_body.fetch("products").map { |product| product["id"] }

        expect(last_response.status).to eq(200)
        expect(first_ids.size).to eq(10)
        expect(second_ids.size).to eq(10)
        expect(third_ids.size).to eq(3)
        expect(first_ids + second_ids + third_ids).to eq(
          23.times.map { |index| format("product-%02d", index) }.reverse
        )
        expect(json_body["pagination"]).to eq(
          "page" => 3, "per_page" => 10, "total" => 23, "total_pages" => 3
        )
      end

      it "returns an empty page without losing the actual totals" do
        get "/products?page=4&per_page=10", {}, auth_header

        expect(last_response.status).to eq(200)
        expect(json_body["products"]).to eq([])
        expect(json_body["pagination"]).to eq(
          "page" => 4, "per_page" => 10, "total" => 23, "total_pages" => 3
        )
      end

      it "accepts the maximum page size" do
        get "/products?per_page=100", {}, auth_header

        expect(last_response.status).to eq(200)
        expect(json_body["products"].size).to eq(23)
        expect(json_body["pagination"]).to include("per_page" => 100, "total_pages" => 1)
      end
    end

    ["page=0", "page=-1", "page=abc", "page=1.5", "page=", "page=2147483648",
     "per_page=0", "per_page=-1", "per_page=101", "per_page=abc", "per_page=1.5", "per_page="].each do |query|
      it "rejects invalid pagination: #{query}" do
        get "/products?#{query}", {}, auth_header

        expect(last_response.status).to eq(400)
        expect(json_body.dig("error", "code")).to eq("invalid_request")
      end
    end

    it "lists a product once the worker has created it" do
      created = create_product

      get "/products", {}, auth_header

      expect(json_body["products"]).to contain_exactly(
        include("id" => created["product_id"], "name" => "Laptop")
      )
    end

    it "withholds a product whose creation is still pending" do
      enqueue_product

      get "/products", {}, auth_header

      expect(json_body["products"]).to be_empty
    end

    it "lists every product that has been created" do
      first = create_product(name: "Laptop")
      second = create_product(name: "Mouse")

      get "/products", {}, auth_header

      expect(json_body["products"].map { |product| product["id"] })
        .to contain_exactly(first["product_id"], second["product_id"])
    end
  end

  describe "GET /products/{id}" do
    it_behaves_like "a protected endpoint", :get, "/products/any-id"

    it "answers that the product does not exist while its creation is pending" do
      created = enqueue_product

      get "/products/#{created['product_id']}", {}, auth_header

      expect(last_response.status).to eq(404)
      expect(json_body["error"]).to include("code" => "not_found")
    end

    it "returns the product once the worker has created it" do
      created = create_product

      get "/products/#{created['product_id']}", {}, auth_header

      expect(last_response.status).to eq(200)
      expect(json_body).to include("id" => created["product_id"], "name" => "Laptop")
    end

    it "answers that a product nobody asked for does not exist" do
      get "/products/missing", {}, auth_header

      expect(last_response.status).to eq(404)
    end
  end
end
