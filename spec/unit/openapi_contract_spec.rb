# frozen_string_literal: true

require "yaml"
require "committee"

RSpec.describe "OpenAPI contract" do
  let(:contract_path) { File.expand_path("../../openapi.yaml", __dir__) }
  let(:document) { YAML.safe_load_file(contract_path) }
  let(:public_paths) { ["/auth/login", "/health", "/openapi.yaml", "/AUTHORS"] }

  def operations(document)
    document["paths"].flat_map do |path, methods|
      methods.slice("get", "post", "put", "patch", "delete")
             .map { |verb, operation| [path, verb, operation] }
    end
  end

  it "loads as an OpenAPI 3 schema with every reference resolved" do
    expect do
      Committee::Drivers.load_from_file(contract_path, parser_options: { strict_reference_validation: true })
    end.not_to raise_error
  end

  it "targets OpenAPI 3.0" do
    expect(document["openapi"]).to start_with("3.0")
  end

  it "declares a bearer jwt security scheme" do
    expect(document.dig("components", "securitySchemes", "bearerAuth"))
      .to include("type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT")
  end

  it "protects every operation that is not public" do
    operations(document).reject { |path, _, _| public_paths.include?(path) }
                        .each do |path, verb, operation|
      expect(operation["security"]).to eq([{ "bearerAuth" => [] }]),
                                       "#{verb.upcase} #{path} is not protected"
    end
  end

  it "documents an unauthorized response on every protected operation" do
    operations(document).reject { |path, _, _| public_paths.include?(path) }
                        .each do |path, verb, operation|
      expect(operation["responses"]).to have_key("401"),
                                        "#{verb.upcase} #{path} does not document a 401"
    end
  end

  it "leaves public operations unauthenticated" do
    operations(document).select { |path, _, _| public_paths.include?(path) }
                        .each do |path, verb, operation|
      expect(operation["security"]).to be_nil, "#{verb.upcase} #{path} should be public"
    end
  end

  it "describes every failure through the shared error responses" do
    operations(document).each do |path, verb, operation|
      operation["responses"].select { |status, _| status.to_i >= 400 }
                            .each do |status, response|
        expect(response["$ref"]).to start_with("#/components/responses/"),
                                    "#{verb.upcase} #{path} #{status} does not reuse a shared error response"
      end
    end
  end

  it "renders every shared error response with the error schema" do
    document.dig("components", "responses").each do |name, response|
      expect(response.dig("content", "application/json", "schema", "$ref"))
        .to eq("#/components/schemas/Error"), "#{name} does not use the Error schema"
    end
  end
end
