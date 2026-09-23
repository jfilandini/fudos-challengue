# frozen_string_literal: true

require "rack/test"

module ApiHelpers
  include Rack::Test::Methods

  def container
    @container ||= Challenge::Container.new
  end

  def app
    @app ||= Challenge::Application.build(container)
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def post_json(path, payload, headers = {})
    defaults = { "CONTENT_TYPE" => "application/json" }
    defaults["HTTP_IDEMPOTENCY_KEY"] = SecureRandom.uuid if path == "/products"
    post(path, JSON.generate(payload), defaults.merge(headers))
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :integration
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end
end
