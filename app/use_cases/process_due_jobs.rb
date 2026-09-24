# frozen_string_literal: true

module Challenge
  module UseCases
    class ProcessDueJobs
      BATCH_SIZE = 100

      def initialize(job_repository:, product_repository:, unit_of_work:, clock:)
        @job_repository = job_repository
        @product_repository = product_repository
        @unit_of_work = unit_of_work
        @clock = clock
      end

      def call
        completed = 0
        BATCH_SIZE.times do
          job = @job_repository.claim_next(@clock.now)
          break unless job

          completed += 1 if process(job)
        end
        completed
      end

      private

      def process(job)
        now = @clock.now
        @unit_of_work.transaction(mode: :immediate) do
          @product_repository.create(
            id: job.product_id, name: job.product_name, created_at: now,
            requested_by_user_id: job.requested_by_user_id
          )
          @job_repository.mark_completed(job.id, now)
        end
        true
      rescue StandardError => error
        warn "product job #{job.id} failed (#{error.class})"
        @job_repository.mark_failed(job.id, @clock.now)
        false
      end
    end
  end
end
