# frozen_string_literal: true

RSpec.describe Challenge::Support::JwtEncoder do
  subject(:encoder) { build_encoder }

  def build_encoder(secret: "secret", clock: FrozenClock.new(Time.now.utc))
    described_class.new(secret: secret, ttl_seconds: 3600, clock: clock)
  end

  it "round trips the subject it was given" do
    expect(encoder.decode(encoder.encode(42))["sub"]).to eq("42")
  end

  it "reports how long a token remains valid" do
    expect(encoder.ttl_seconds).to eq(3600)
  end

  it "refuses a token signed with a different secret" do
    foreign = build_encoder(secret: "another-secret")

    expect { encoder.decode(foreign.encode(42)) }.to raise_error(described_class::InvalidToken)
  end

  it "refuses a tampered token" do
    expect { encoder.decode("#{encoder.encode(42)}tampered") }.to raise_error(described_class::InvalidToken)
  end

  it "refuses a token whose lifetime has elapsed" do
    stale = build_encoder(clock: FrozenClock.new(Time.now.utc - 7200))

    expect { encoder.decode(stale.encode(42)) }.to raise_error(described_class::InvalidToken)
  end

  it "refuses something that is not a token at all" do
    expect { encoder.decode("nonsense") }.to raise_error(described_class::InvalidToken)
  end
end
