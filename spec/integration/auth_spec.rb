# frozen_string_literal: true

RSpec.describe "POST /auth/login" do
  before { container.user_repository.create(username: "admin", password: "password123", now: container.clock.now) }

  it "exchanges valid credentials for a bearer token" do
    post_json "/auth/login", username: "admin", password: "password123"

    expect(last_response.status).to eq(200)
    expect(json_body).to include("token_type" => "Bearer", "expires_in" => 3600)
    expect(json_body["token"]).to be_a(String)
    expect(container.jwt_encoder.decode(json_body["token"])["sub"]).to eq("1")
  end

  it "refuses a wrong password" do
    post_json "/auth/login", username: "admin", password: "wrong"

    expect(last_response.status).to eq(401)
    expect(json_body["error"]).to include("code" => "invalid_credentials")
  end

  it "answers an unknown user exactly as it answers a wrong password" do
    post_json "/auth/login", username: "ghost", password: "password123"
    unknown_user = [last_response.status, json_body]

    post_json "/auth/login", username: "admin", password: "wrong"

    expect(unknown_user).to eq([last_response.status, json_body])
  end
end
