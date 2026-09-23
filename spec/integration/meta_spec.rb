# frozen_string_literal: true

require "stringio"
require "zlib"

RSpec.describe "Meta endpoints" do
  describe "GET /health" do
    it "reports that the service is up" do
      get "/health"

      expect(last_response.status).to eq(200)
      expect(json_body).to eq("status" => "ok")
    end
  end

  describe "GET /openapi.yaml" do
    before { get "/openapi.yaml" }

    it "serves the contract as yaml" do
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("application/yaml")
      expect(last_response.body).to include("openapi: 3.0.3")
    end

    it "forbids clients from caching it" do
      expect(last_response.headers["cache-control"]).to eq("no-store, no-cache, must-revalidate")
      expect(last_response.headers["pragma"]).to eq("no-cache")
    end
  end

  describe "GET /AUTHORS" do
    before { get "/AUTHORS" }

    it "serves the authors as plain text" do
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/plain")
      expect(last_response.body.strip).to eq("Juan Manuel Filandini")
    end

    it "lets clients cache it for twenty four hours" do
      expect(last_response.headers["cache-control"]).to eq("public, max-age=86400")
    end
  end

  describe "compression" do
    it "compresses the response when the client accepts gzip" do
      get "/health", {}, "HTTP_ACCEPT_ENCODING" => "gzip"

      expect(last_response.headers["content-encoding"]).to eq("gzip")
      expect(Zlib::GzipReader.new(StringIO.new(last_response.body)).read).to eq('{"status":"ok"}')
    end

    it "leaves the response untouched when the client does not accept gzip" do
      get "/health"

      expect(last_response.headers["content-encoding"]).to be_nil
      expect(last_response.body).to eq('{"status":"ok"}')
    end
  end

  describe "an unknown route" do
    it "does not disclose its absence to an anonymous caller" do
      get "/nowhere"

      expect(last_response.status).to eq(401)
    end

    it "answers an authenticated caller with the shared error envelope" do
      get "/nowhere", {}, auth_header

      expect(last_response.status).to eq(404)
      expect(json_body["error"]).to include("code" => "not_found")
    end
  end
end
