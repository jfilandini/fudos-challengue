# frozen_string_literal: true

class FrozenClock
  def initialize(time = Time.utc(2026, 9, 18, 12, 0, 0))
    @time = time
  end

  attr_reader :time
  alias now time

  def advance(seconds)
    @time += seconds
    self
  end
end
