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
        @monitor.synchronize do
          @connection.transaction(:immediate) do
            @connection.execute_batch(File.read(SCHEMA_PATH))
            # Existing databases predate request attribution; preserve their rows.
            %w[jobs products].each do |table|
              columns = @connection.execute("PRAGMA table_info(#{table})").map { |row| row["name"] }
              unless columns.include?("requested_by_user_id")
                @connection.execute("ALTER TABLE #{table} ADD COLUMN requested_by_user_id TEXT")
              end
            end
            job_columns = @connection.execute("PRAGMA table_info(jobs)").map { |row| row["name"] }
            unless job_columns.include?("idempotency_key")
              @connection.execute("ALTER TABLE jobs ADD COLUMN idempotency_key TEXT")
            end
            @connection.execute(
              "CREATE UNIQUE INDEX IF NOT EXISTS index_jobs_on_requester_and_idempotency_key " \
              "ON jobs (requested_by_user_id, idempotency_key)"
            )
          end
        end
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
