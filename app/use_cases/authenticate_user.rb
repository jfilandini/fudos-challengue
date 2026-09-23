# frozen_string_literal: true

module Challenge
  module UseCases
    class AuthenticateUser
      InvalidCredentials = Class.new(StandardError)

      class Result < Data.define(:token, :expires_in); end

      def initialize(user_repository:, jwt_encoder:)
        @user_repository = user_repository
        @jwt_encoder = jwt_encoder
      end

      def call(username:, password:)
        user = @user_repository.find_by_username(username)
        raise InvalidCredentials unless user&.authenticate?(password)

        Result.new(token: @jwt_encoder.encode(user.id), expires_in: @jwt_encoder.ttl_seconds)
      end
    end
  end
end
