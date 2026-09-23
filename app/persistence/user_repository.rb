# frozen_string_literal: true

module Challenge
  module Persistence
    class UserRepository
      def initialize(database)
        @database = database
      end

      def create(username:, password:, now:)
        @database.execute(
          "INSERT INTO users (username, password_digest, created_at) VALUES (?, ?, ?)",
          [username, BCrypt::Password.create(password).to_s, Support::Timestamp.serialize(now)]
        )
        find_by_username(username)
      end

      def find_by_username(username)
        row = @database.execute("SELECT id, username, password_digest FROM users WHERE username = ?", [username]).first
        return nil unless row

        Domain::User.new(id: row["id"], username: row["username"], password_digest: row["password_digest"])
      end
    end
  end
end
