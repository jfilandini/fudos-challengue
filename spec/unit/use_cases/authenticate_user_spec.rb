# frozen_string_literal: true

RSpec.describe Challenge::UseCases::AuthenticateUser do
  subject(:authenticate) { described_class.new(user_repository: users, jwt_encoder: encoder) }

  let(:users) { Challenge::Persistence::UserRepository.new(build_database) }
  let(:encoder) do
    Challenge::Support::JwtEncoder.new(secret: "secret", ttl_seconds: 3600, clock: FrozenClock.new(Time.now.utc))
  end

  def failure_from
    yield
    nil
  rescue StandardError => e
    e
  end

  before { users.create(username: "admin", password: "password123", now: Time.now.utc) }

  it "issues a token identifying the authenticated user" do
    result = authenticate.call(username: "admin", password: "password123")

    expect(encoder.decode(result.token)["sub"]).to eq(users.find_by_username("admin").id.to_s)
    expect(result.expires_in).to eq(3600)
  end

  it "refuses a wrong password" do
    expect { authenticate.call(username: "admin", password: "wrong") }
      .to raise_error(described_class::InvalidCredentials)
  end

  it "refuses an unknown user" do
    expect { authenticate.call(username: "ghost", password: "password123") }
      .to raise_error(described_class::InvalidCredentials)
  end

  it "fails identically whether the user or the password is wrong" do
    unknown_user = failure_from { authenticate.call(username: "ghost", password: "password123") }
    wrong_password = failure_from { authenticate.call(username: "admin", password: "wrong") }

    expect(unknown_user.class).to eq(wrong_password.class)
    expect(unknown_user.message).to eq(wrong_password.message)
  end
end
