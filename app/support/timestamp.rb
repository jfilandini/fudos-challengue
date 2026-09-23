# frozen_string_literal: true

module Challenge
  module Support
    module Timestamp
      FORMAT_PRECISION = 3

      module_function

      def serialize(time)
        time.utc.iso8601(FORMAT_PRECISION)
      end

      def parse(value)
        Time.iso8601(value)
      end
    end
  end
end
