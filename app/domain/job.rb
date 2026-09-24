# frozen_string_literal: true

module Challenge
  module Domain
    class Job < Data.define(:id, :product_id, :product_name, :status, :run_at, :created_at, :updated_at, :requested_by_user_id)
      PENDING = "pending"
      IN_PROGRESS = "in_progress"
      COMPLETED = "completed"
      FAILED = "failed"

      def pending?
        status == PENDING
      end

      def in_progress?
        status == IN_PROGRESS
      end

      def completed?
        status == COMPLETED
      end

      def failed?
        status == FAILED
      end
    end
  end
end
