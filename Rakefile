# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :db do
  desc "Create the database schema"
  task :setup do
    require_relative "app/boot"

    config = Challenge::Config.from_env
    Challenge::Persistence::Database.new(config.database_path).setup!
    puts "Schema ready at #{config.database_path}"
  end

  desc "Insert the seed user"
  task :seed do
    require_relative "db/seeds"
  end
end

task default: :spec
