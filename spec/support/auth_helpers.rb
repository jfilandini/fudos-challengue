# frozen_string_literal: true

module AuthHelpers
  def auth_header(user_id = 1)
    { "HTTP_AUTHORIZATION" => "Bearer #{container.jwt_encoder.encode(user_id)}" }
  end
end

RSpec.shared_examples "a protected endpoint" do |method, path|
  it "refuses a request without a token" do
    public_send(method, path)

    expect(last_response.status).to eq(401)
    expect(json_body["error"]).to include("code" => "unauthorized")
  end

  it "refuses a request whose token is not valid" do
    public_send(method, path, {}, "HTTP_AUTHORIZATION" => "Bearer nonsense")

    expect(last_response.status).to eq(401)
  end
end

RSpec.configure { |config| config.include AuthHelpers, type: :integration }
