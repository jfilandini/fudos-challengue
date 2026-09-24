# frozen_string_literal: true

RSpec.describe Challenge::Config do
  def config_for(env = {})
    described_class.from_env(env)
  end

  it "falls back to development defaults when nothing is configured" do
    config = config_for

    expect(config.environment).to eq("development")
    expect(config.database_path).to eq("db/development.sqlite3")
    expect(config.jwt_ttl_seconds).to eq(3600)
    expect(config.product_creation_delay_seconds).to eq(5)
    expect(config.worker_poll_interval_seconds).to eq(0.5)
    expect(config.seed_username).to eq("admin")
  end

  it "prefers explicit environment values and coerces them" do
    config = config_for(
      "DATABASE_PATH" => "/tmp/challenge.sqlite3",
      "JWT_TTL_SECONDS" => "60",
      "PRODUCT_CREATION_DELAY_SECONDS" => "2",
      "WORKER_POLL_INTERVAL_SECONDS" => "0.1"
    )

    expect(config.database_path).to eq("/tmp/challenge.sqlite3")
    expect(config.jwt_ttl_seconds).to eq(60)
    expect(config.product_creation_delay_seconds).to eq(2)
    expect(config.worker_poll_interval_seconds).to eq(0.1)
  end

  it "keeps the database in memory and removes the creation delay under test" do
    config = config_for("RACK_ENV" => "test")

    expect(config).to be_test
    expect(config.database_path).to eq(":memory:")
    expect(config.product_creation_delay_seconds).to eq(0)
  end

  it "requires a signing secret in production" do
    expect { config_for("RACK_ENV" => "production") }
      .to raise_error(described_class::MissingSecretError)
  end

  it "accepts a production configuration with a signing secret" do
    config = config_for("RACK_ENV" => "production", "JWT_SECRET" => "s3cret")

    expect(config).to be_production
    expect(config.jwt_secret).to eq("s3cret")
  end
end
