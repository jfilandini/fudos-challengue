# frozen_string_literal: true

module Challenge
  module Support
    class Clock
      def now
        Time.now.utc
      end
    end
  end
end
