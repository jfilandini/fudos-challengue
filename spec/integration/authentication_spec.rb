# frozen_string_literal: true

RSpec.describe "Authentication across the stack" do
  it_behaves_like "a protected endpoint", :get, "/jobs/any-id"

  it "answers an anonymous request before the contract inspects the payload" do
    post_json "/products", nothing_like: "the contract"

    expect(last_response.status).to eq(401)
    expect(json_body["error"]).to include("code" => "unauthorized")
  end

  it "answers a contract violation once the caller is authenticated" do
    post_json "/products", { nothing_like: "the contract" }, auth_header

    expect(last_response.status).to eq(400)
    expect(json_body["error"]).to include("code" => "invalid_request")
  end
end
