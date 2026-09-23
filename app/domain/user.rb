# frozen_string_literal: true

module Challenge
  module Domain
    class User < Data.define(:id, :username, :password_digest)
      def authenticate?(password)
        BCrypt::Password.new(password_digest) == password
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end
  end
end
