# frozen_string_literal: true

module Challenge
  module Api
    class Routes < Sinatra::Base
      configure do
        disable :show_exceptions
        disable :raise_errors
        disable :static
        disable :logging
      end

      helpers do
        def container
          settings.container
        end

        def validated_params
          env["committee.params"]
        end

        def json(payload, status_code = 200)
          content_type :json
          status status_code
          JSON.generate(payload)
        end

        def error!(status_code, code, message)
          halt status_code, { "content-type" => "application/json" }, Support::ErrorResponse.body(code, message)
        end
      end

      register AuthRoutes
      register JobsRoutes
      register MetaRoutes
      register ProductsRoutes

      not_found do
        content_type :json
        Support::ErrorResponse.body(:not_found, "The requested resource does not exist")
      end

      error do
        content_type :json
        Support::ErrorResponse.body(:internal_error, "The request could not be completed")
      end

      def self.for(container)
        Class.new(self) { set :container, container }
      end
    end
  end
end
