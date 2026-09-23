# frozen_string_literal: true

module Challenge
  module UseCases
    class FindJob
      def initialize(job_repository:)
        @job_repository = job_repository
      end

      def call(id)
        @job_repository.find(id)
      end
    end
  end
end
