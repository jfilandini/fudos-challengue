# frozen_string_literal: true

module Challenge
  module UseCases
    class ProcessDueJobs
      def initialize(job_repository:, product_repository:, unit_of_work:, clock:)
        @job_repository = job_repository
        @product_repository = product_repository
        @unit_of_work = unit_of_work
        @clock = clock
      end

      def call
        now = @clock.now

        @job_repository.due(now).count { |job| process(job, now) }
      end

      private

      def process(job, now)
        @unit_of_work.transaction do
          @product_repository.create(
            id: job.product_id, name: job.product_name, created_at: now,
            requested_by_user_id: job.requested_by_user_id
          )
          @job_repository.mark_completed(job.id, now)
        end
        true
      rescue StandardError
        @job_repository.mark_failed(job.id, now)
        false
      end
    end
  end
end
