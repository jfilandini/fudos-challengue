# frozen_string_literal: true

module Challenge
  module Persistence
    class JobRepository
      InvalidTransition = Class.new(StandardError)

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

      def find_for_user(id, requested_by_user_id:)
        row = @database.execute(
          "SELECT #{COLUMNS} FROM jobs WHERE id = ? AND requested_by_user_id = ?",
          [id, requested_by_user_id]
        ).first
        row && to_job(row)
      end

      def find(id)
        row = @database.execute("SELECT #{COLUMNS} FROM jobs WHERE id = ?", [id]).first
        row && to_job(row)
      end

      # A single write statement selects and reserves one job atomically across
      # connections/processes. The reservation commits before processing begins.
      def claim_next(now)
        row = @database.execute(
          "UPDATE jobs SET status = ?, updated_at = ? " \
          "WHERE id = (SELECT id FROM jobs WHERE status = ? AND run_at <= ? " \
          "ORDER BY run_at ASC, created_at ASC, id ASC LIMIT 1) AND status = ? " \
          "RETURNING #{COLUMNS}",
          [Domain::Job::IN_PROGRESS, Support::Timestamp.serialize(now),
           Domain::Job::PENDING, Support::Timestamp.serialize(now), Domain::Job::PENDING]
        ).first
        row && to_job(row)
      end

      def mark_completed(id, now)
        raise InvalidTransition, "Job is not in progress" unless update_status(id, Domain::Job::COMPLETED, now)
      end

      def mark_failed(id, now)
        update_status(id, Domain::Job::FAILED, now)
      end

      private

      def update_status(id, status, now)
        rows = @database.execute(
          "UPDATE jobs SET status = ?, updated_at = ? " \
          "WHERE id = ? AND status = ? RETURNING id",
          [status, Support::Timestamp.serialize(now), id, Domain::Job::IN_PROGRESS]
        )
        !rows.empty?
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
