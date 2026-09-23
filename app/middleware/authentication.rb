# frozen_string_literal: true

module Challenge
  module Middleware
    class Authentication
      PUBLIC_PATHS = ["/auth/login", "/health", "/openapi.yaml", "/AUTHORS"].freeze
      USER_ID_KEY = "challenge.user_id"
      BEARER_SCHEME = /\Abearer\s+(?<token>\S+)\z/i

      def initialize(app, container:)
        @app = app
        @container = container
      end

      def call(env)
        return @app.call(env) if PUBLIC_PATHS.include?(env["PATH_INFO"])

        token = BEARER_SCHEME.match(env["HTTP_AUTHORIZATION"].to_s)
        return unauthorized unless token

        env[USER_ID_KEY] = @container.jwt_encoder.decode(token[:token])["sub"]
        @app.call(env)
      rescue Support::JwtEncoder::InvalidToken
        unauthorized
      end

      private

      def unauthorized
        Support::ErrorResponse.rack(401, :unauthorized, "A valid bearer token is required")
      end
    end
  end
end
