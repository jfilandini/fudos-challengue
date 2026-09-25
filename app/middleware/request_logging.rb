# frozen_string_literal: true

module Challenge
  module Middleware
    class RequestLogging
      EXACT_ROUTES = %w[/auth/login /products /health /openapi.yaml /AUTHORS].freeze
      METHODS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS CONNECT TRACE].freeze

      def initialize(app, logger: nil)
        @app = app
        @logger = logger || Logger.new($stdout, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
      end

      def call(env)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        context = {
          request_id: SecureRandom.uuid,
          method: METHODS.include?(env["REQUEST_METHOD"]) ? env["REQUEST_METHOD"] : "OTHER",
          route: safe_route(env["PATH_INFO"])
        }
        emit(context.merge(event: "request_started"))
        status = 500
        begin
          response = @app.call(env)
          status = response[0]
          response
        ensure
          duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
          emit(context.merge(event: "request_completed", status: status, duration_ms: duration.round(2)))
        end
      end

      private

      # Never log raw URLs: even path segments and unknown routes can contain secrets.
      def safe_route(path)
        return path if EXACT_ROUTES.include?(path)
        return "/products/:id" if %r{\A/products/[^/]+\z}.match?(path.to_s)
        return "/jobs/:id" if %r{\A/jobs/[^/]+\z}.match?(path.to_s)

        "unmatched"
      end

      def emit(payload)
        @logger.info(JSON.generate(payload.merge(timestamp: Time.now.utc.iso8601(3))))
      rescue IOError, SystemCallError
        # A failed log output must not prevent request processing.
        nil
      end
    end
  end
end
