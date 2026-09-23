# frozen_string_literal: true

module Challenge
  module UseCases
    class EnqueueProductCreation
      def initialize(job_repository:, clock:, delay_seconds:)
        @job_repository = job_repository
        @clock = clock
        @delay_seconds = delay_seconds
      end

      def call(name:)
        now = @clock.now

        @job_repository.create(
          id: SecureRandom.uuid,
          product_id: SecureRandom.uuid,
          product_name: name,
          run_at: now + @delay_seconds,
          now: now
        )
      end
    end
  end
end
