# frozen_string_literal: true

module Challenge
  module Api
    module MetaRoutes
      CONTRACT_PATH = File.expand_path("../../openapi.yaml", __dir__)
      AUTHORS_PATH = File.expand_path("../../AUTHORS", __dir__)
      CONTRACT_CACHE_CONTROL = "no-store, no-cache, must-revalidate"
      AUTHORS_CACHE_CONTROL = "public, max-age=86400"

      def self.registered(app)
        app.get "/health" do
          json(status: "ok")
        end

        app.get "/openapi.yaml" do
          content_type "application/yaml"
          headers "cache-control" => CONTRACT_CACHE_CONTROL, "pragma" => "no-cache"
          File.read(CONTRACT_PATH)
        end

        app.get "/AUTHORS" do
          content_type "text/plain"
          headers "cache-control" => AUTHORS_CACHE_CONTROL
          File.read(AUTHORS_PATH)
        end
      end
    end
  end
end
