# frozen_string_literal: true

module Challenge
  module Workers
    class ProductWorker
      def initialize(process_due_jobs:, interval:)
        @process_due_jobs = process_due_jobs
        @interval = interval
        @running = false
      end

      def start
        return self if running?

        @running = true
        @thread = Thread.new do
          while running?
            tick
            sleep @interval
          end
        end
        self
      end

      def tick
        @process_due_jobs.call
      rescue StandardError => e
        warn "product worker could not process jobs: #{e.message}"
        0
      end

      def stop
        @running = false
        @thread&.join(@interval + 1)
        @thread = nil
        self
      end

      def running?
        @running
      end
    end
  end
end
