# frozen_string_literal: true

RSpec.describe Challenge::Support::Timestamp do
  let(:time) { Time.utc(2026, 9, 18, 12, 0, 0) }

  it "serialises a time as a sortable utc string" do
    expect(described_class.serialize(time)).to eq("2026-09-18T12:00:00.000Z")
  end

  it "keeps chronological order under string comparison" do
    later = described_class.serialize(time + 1)

    expect(described_class.serialize(time)).to be < later
  end

  it "round trips a serialised time" do
    expect(described_class.parse(described_class.serialize(time))).to eq(time)
  end
end
