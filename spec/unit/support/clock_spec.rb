# frozen_string_literal: true

RSpec.describe Challenge::Support::Clock do
  subject(:clock) { described_class.new }

  it "reports the current time in utc" do
    expect(clock.now).to be_within(5).of(Time.now.utc)
    expect(clock.now.utc?).to be(true)
  end
end
