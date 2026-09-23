# frozen_string_literal: true

RSpec.describe Challenge::Domain::User do
  subject(:user) do
    described_class.new(id: 1, username: "admin", password_digest: BCrypt::Password.create("password123"))
  end

  it "accepts the password it was created with" do
    expect(user.authenticate?("password123")).to be(true)
  end

  it "rejects any other password" do
    expect(user.authenticate?("wrong")).to be(false)
  end
end
