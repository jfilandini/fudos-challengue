# frozen_string_literal: true

module Challenge
  module Support
    class JwtEncoder
      ALGORITHM = "HS256"

      InvalidToken = Class.new(StandardError)

      attr_reader :ttl_seconds

      def initialize(secret:, ttl_seconds:, clock:)
        @secret = secret
        @ttl_seconds = ttl_seconds
        @clock = clock
      end

      def encode(subject)
        issued_at = @clock.now.to_i

        JWT.encode({ sub: subject.to_s, iat: issued_at, exp: issued_at + ttl_seconds }, @secret, ALGORITHM)
      end

      def decode(token)
        JWT.decode(token, @secret, true, algorithm: ALGORITHM).first
      rescue JWT::DecodeError
        raise InvalidToken
      end
    end
  end
end
