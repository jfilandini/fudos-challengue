# frozen_string_literal: true

RSpec.describe Challenge::Persistence::UserRepository do
  subject(:repository) { described_class.new(build_database) }

  let(:now) { Time.utc(2026, 9, 18, 12, 0, 0) }

  it "stores the password as a digest rather than as given" do
    user = repository.create(username: "admin", password: "password123", now: now)

    expect(user.password_digest).not_to eq("password123")
    expect(user.authenticate?("password123")).to be(true)
  end

  it "finds a stored user by username" do
    repository.create(username: "admin", password: "password123", now: now)

    expect(repository.find_by_username("admin")).to have_attributes(username: "admin")
  end

  it "returns nothing for an unknown username" do
    expect(repository.find_by_username("ghost")).to be_nil
  end
end
