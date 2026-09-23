# frozen_string_literal: true

RSpec.describe "OpenAPI contract enforcement" do
  describe "incoming requests" do
    it "rejects a payload whose types do not match the contract" do
      post_json "/auth/login", username: 42, password: "password123"

      expect(last_response.status).to eq(400)
      expect(json_body["error"]).to include("code" => "invalid_request")
    end

    it "rejects a payload that omits a required field" do
      post_json "/auth/login", username: "admin"

      expect(last_response.status).to eq(400)
    end

    it "rejects a payload carrying fields the contract does not declare" do
      post_json "/auth/login", username: "admin", password: "password123", role: "root"

      expect(last_response.status).to eq(400)
    end

    it "rejects a body that is not json" do
      post "/auth/login", "not json", "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(400)
      expect(json_body["error"]).to include("code" => "invalid_request")
    end
  end

  describe "outgoing responses" do
    let(:off_contract_app) do
      Rack::Builder.app do
        use Committee::Middleware::ResponseValidation, **Challenge::Application::COMMITTEE_OPTIONS
        run ->(_env) { [200, { "content-type" => "application/json" }, ['{"status":"broken"}']] }
      end
    end

    it "refuses to return a response the contract does not allow" do
      session = Rack::Test::Session.new(off_contract_app)
      session.get("/health")

      expect(session.last_response.status).to eq(500)
      expect(JSON.parse(session.last_response.body)["error"]).to include("code" => "internal_error")
    end

    it "does not leak contract internals through a server error" do
      session = Rack::Test::Session.new(off_contract_app)
      session.get("/health")

      expect(JSON.parse(session.last_response.body).dig("error", "message")).not_to include("#/components")
    end
  end

  describe "where response validation runs" do
    it "validates responses outside production" do
      expect(Challenge::Application.validate_responses?(Challenge::Config.from_env("RACK_ENV" => "test")))
        .to be(true)
    end

    it "leaves production responses unvalidated" do
      production = Challenge::Config.from_env("RACK_ENV" => "production", "JWT_SECRET" => "secret")

      expect(Challenge::Application.validate_responses?(production)).to be(false)
    end
  end
end
