# frozen_string_literal: true

require_relative "../app/boot"

config = Challenge::Config.from_env
database = Challenge::Persistence::Database.new(config.database_path).setup!
users = Challenge::Persistence::UserRepository.new(database)

if users.find_by_username(config.seed_username)
  puts "User #{config.seed_username} already exists"
else
  users.create(username: config.seed_username, password: config.seed_password, now: Challenge::Support::Clock.new.now)
  puts "Created user #{config.seed_username}"
end
