# frozen_string_literal: true

module Challenge
  class Config
    MissingSecretError = Class.new(StandardError)

    DEVELOPMENT_DATABASE_PATH = "db/development.sqlite3"
    TEST_DATABASE_PATH = ":memory:"
    DEVELOPMENT_JWT_SECRET = "development-secret"
    DEFAULT_JWT_TTL_SECONDS = 3600
    DEFAULT_PRODUCT_CREATION_DELAY_SECONDS = 5
    DEFAULT_WORKER_POLL_INTERVAL_SECONDS = 0.5
    DEFAULT_SEED_USERNAME = "admin"
    DEFAULT_SEED_PASSWORD = "password123"

    attr_reader :environment, :database_path, :jwt_secret, :jwt_ttl_seconds,
                :product_creation_delay_seconds, :worker_poll_interval_seconds,
                :seed_username, :seed_password

    def self.from_env(env = ENV)
      new(env)
    end

    def initialize(env = ENV)
      @environment = env.fetch("RACK_ENV", "development")
      @database_path = env.fetch("DATABASE_PATH") { default_database_path }
      @jwt_secret = env.fetch("JWT_SECRET") { default_jwt_secret }
      @jwt_ttl_seconds = Integer(env.fetch("JWT_TTL_SECONDS", DEFAULT_JWT_TTL_SECONDS))
      @product_creation_delay_seconds = Integer(env.fetch("PRODUCT_CREATION_DELAY_SECONDS") { default_delay })
      @worker_poll_interval_seconds = Float(env.fetch("WORKER_POLL_INTERVAL_SECONDS", DEFAULT_WORKER_POLL_INTERVAL_SECONDS))
      @seed_username = env.fetch("SEED_USERNAME", DEFAULT_SEED_USERNAME)
      @seed_password = env.fetch("SEED_PASSWORD", DEFAULT_SEED_PASSWORD)
      freeze
    end

    def test?
      environment == "test"
    end

    def production?
      environment == "production"
    end

    private

    def default_database_path
      test? ? TEST_DATABASE_PATH : DEVELOPMENT_DATABASE_PATH
    end

    def default_delay
      test? ? 0 : DEFAULT_PRODUCT_CREATION_DELAY_SECONDS
    end

    def default_jwt_secret
      raise MissingSecretError, "JWT_SECRET is required in production" if production?

      DEVELOPMENT_JWT_SECRET
    end
  end
end
