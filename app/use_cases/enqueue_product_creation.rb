# frozen_string_literal: true

module Challenge
  module UseCases
    class EnqueueProductCreation
      IdempotencyConflict = Class.new(StandardError)

      def initialize(job_repository:, clock:, delay_seconds:)
        @job_repository = job_repository
        @clock = clock
        @delay_seconds = delay_seconds
      end

      def call(name:, requested_by_user_id:, idempotency_key:)
        unless idempotency_key.is_a?(String) && idempotency_key.match?(/\A[A-Za-z0-9_-]{1,128}\z/)
          raise ArgumentError, "Invalid idempotency key"
        end
        unless requested_by_user_id.is_a?(String) && !requested_by_user_id.empty?
          raise ArgumentError, "Requester identity is required"
        end

        now = @clock.now

        job = @job_repository.create(
          id: SecureRandom.uuid,
          product_id: SecureRandom.uuid,
          product_name: name,
          requested_by_user_id: requested_by_user_id,
          idempotency_key: idempotency_key,
          run_at: now + @delay_seconds,
          now: now
        )
        # Name is the complete validated creation payload; compare it exactly.
        raise IdempotencyConflict unless job.product_name == name

        job
      end
    end
  end
end
