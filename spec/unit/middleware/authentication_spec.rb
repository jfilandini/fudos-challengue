# frozen_string_literal: true

RSpec.describe Challenge::Middleware::Authentication do
  subject(:middleware) { described_class.new(downstream, container: container) }

  let(:container) { Challenge::Container.new }
  let(:downstream_env) { {} }
  let(:downstream) { ->(env) { downstream_env.replace(env) && [200, {}, ["reached"]] } }

  def call(path, authorization = nil)
    env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => path }
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    middleware.call(env)
  end

  def encoder_with(secret: container.config.jwt_secret, clock: FrozenClock.new(Time.now.utc))
    Challenge::Support::JwtEncoder.new(secret: secret, ttl_seconds: 3600, clock: clock)
  end

  described_class::PUBLIC_PATHS.each do |path|
    it "lets #{path} through without a token" do
      expect(call(path).first).to eq(200)
    end
  end

  it "refuses a protected path when no authorization header is sent" do
    status, _headers, body = call("/products")

    expect(status).to eq(401)
    expect(JSON.parse(body.first)["error"]).to include("code" => "unauthorized")
  end

  it "refuses an authorization header using another scheme" do
    expect(call("/products", "Basic dXNlcjpwYXNz").first).to eq(401)
  end

  it "refuses a bearer scheme carrying no token" do
    expect(call("/products", "Bearer").first).to eq(401)
  end

  it "refuses a token this api did not sign" do
    foreign = encoder_with(secret: "another-secret")

    expect(call("/products", "Bearer #{foreign.encode(1)}").first).to eq(401)
  end

  it "refuses a token whose lifetime has elapsed" do
    stale = encoder_with(clock: FrozenClock.new(Time.now.utc - 7200))

    expect(call("/products", "Bearer #{stale.encode(1)}").first).to eq(401)
  end

  it "accepts a valid token and names the caller downstream" do
    status, = call("/products", "Bearer #{container.jwt_encoder.encode(7)}")

    expect(status).to eq(200)
    expect(downstream_env[described_class::USER_ID_KEY]).to eq("7")
  end

  it "accepts the bearer scheme whatever its casing" do
    expect(call("/products", "bearer #{container.jwt_encoder.encode(7)}").first).to eq(200)
  end
end
