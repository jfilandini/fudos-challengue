# frozen_string_literal: true

module Challenge
  module Persistence
    class Database
      IN_MEMORY = ":memory:"
      SCHEMA_PATH = File.expand_path("../../db/schema.sql", __dir__)

      def initialize(path)
        FileUtils.mkdir_p(File.dirname(path)) unless path == IN_MEMORY
        @monitor = Monitor.new
        @connection = SQLite3::Database.new(path)
        @connection.results_as_hash = true
        @connection.busy_timeout = 5_000
      end

      def setup!
        @monitor.synchronize { @connection.execute_batch(File.read(SCHEMA_PATH)) }
        self
      end

      def execute(sql, parameters = [])
        @monitor.synchronize { @connection.execute(sql, parameters) }
      end

      def transaction(&block)
        @monitor.synchronize { @connection.transaction(&block) }
      end

      def close
        @monitor.synchronize { @connection.close }
      end
    end
  end
end
