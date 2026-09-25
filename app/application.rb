# frozen_string_literal: true

module Challenge
  class Application
    OPENAPI_PATH = File.expand_path("../openapi.yaml", __dir__)

    COMMITTEE_OPTIONS = {
      schema_path: OPENAPI_PATH,
      error_class: Middleware::ContractError,
      strict_reference_validation: true
    }.freeze

    def self.build(container = Container.new)
      routes = Api::Routes.for(container)
      validate_responses = validate_responses?(container.config)

      Rack::Builder.app do
        use Middleware::RequestLogging
        use Rack::Deflater
        use Rack::Static,
            root: File.dirname(OPENAPI_PATH),
            urls: { "/openapi.yaml" => "/openapi.yaml", "/AUTHORS" => "/AUTHORS" },
            header_rules: [
              [%r{\A/openapi\.yaml\z}, {
                "content-type" => "application/yaml",
                "cache-control" => "no-store, no-cache, must-revalidate",
                "pragma" => "no-cache"
              }],
              [%r{\A/AUTHORS\z}, {
                "content-type" => "text/plain",
                "cache-control" => "public, max-age=86400"
              }]
            ]
        use Committee::Middleware::ResponseValidation, **COMMITTEE_OPTIONS if validate_responses
        use Middleware::Authentication, container: container
        use Committee::Middleware::RequestValidation, **COMMITTEE_OPTIONS
        run routes
      end
    end

    def self.validate_responses?(config)
      !config.production?
    end
  end
end
