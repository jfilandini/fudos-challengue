# frozen_string_literal: true

module Challenge
  module Domain
    class Job < Data.define(:id, :product_id, :product_name, :status, :run_at, :created_at, :updated_at)
      PENDING = "pending"
      COMPLETED = "completed"
      FAILED = "failed"

      def pending?
        status == PENDING
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
