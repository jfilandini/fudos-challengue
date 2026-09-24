# frozen_string_literal: true

module Challenge
  module UseCases
    class FindJob
      def initialize(job_repository:)
        @job_repository = job_repository
      end

      def call(id, requested_by_user_id:)
        @job_repository.find_for_user(id, requested_by_user_id: requested_by_user_id)
      end
    end
  end
end
