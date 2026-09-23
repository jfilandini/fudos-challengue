# frozen_string_literal: true

module Challenge
  module Persistence
    class JobRepository
      COLUMNS = "id, product_id, product_name, status, run_at, created_at, updated_at, requested_by_user_id, idempotency_key"

      def initialize(database)
        @database = database
      end

      def create(id:, product_id:, product_name:, run_at:, now:, requested_by_user_id: nil, idempotency_key: nil)
        @database.execute(
          "INSERT INTO jobs (#{COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) " \
          "ON CONFLICT(requested_by_user_id, idempotency_key) DO NOTHING",
          [id, product_id, product_name, Domain::Job::PENDING,
           Support::Timestamp.serialize(run_at), Support::Timestamp.serialize(now), Support::Timestamp.serialize(now), requested_by_user_id, idempotency_key]
        )
        if idempotency_key
          row = @database.execute(
            "SELECT #{COLUMNS} FROM jobs WHERE requested_by_user_id = ? AND idempotency_key = ?",
            [requested_by_user_id, idempotency_key]
          ).first
          to_job(row)
        else
          find(id)
        end
      end

      def find(id)
        row = @database.execute("SELECT #{COLUMNS} FROM jobs WHERE id = ?", [id]).first
        row && to_job(row)
      end

      def due(now)
        @database.execute(
          "SELECT #{COLUMNS} FROM jobs WHERE status = ? AND run_at <= ? ORDER BY run_at ASC",
          [Domain::Job::PENDING, Support::Timestamp.serialize(now)]
        ).map { |row| to_job(row) }
      end

      def mark_completed(id, now)
        update_status(id, Domain::Job::COMPLETED, now)
      end

      def mark_failed(id, now)
        update_status(id, Domain::Job::FAILED, now)
      end

      private

      def update_status(id, status, now)
        @database.execute(
          "UPDATE jobs SET status = ?, updated_at = ? WHERE id = ?",
          [status, Support::Timestamp.serialize(now), id]
        )
      end

      def to_job(row)
        Domain::Job.new(
          id: row["id"],
          requested_by_user_id: row["requested_by_user_id"],
          product_id: row["product_id"],
          product_name: row["product_name"],
          status: row["status"],
          run_at: Support::Timestamp.parse(row["run_at"]),
          created_at: Support::Timestamp.parse(row["created_at"]),
          updated_at: Support::Timestamp.parse(row["updated_at"])
        )
      end
    end
  end
end
