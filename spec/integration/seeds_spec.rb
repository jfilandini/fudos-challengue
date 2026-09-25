# frozen_string_literal: true

require "tmpdir"
require "open3"
require "rbconfig"

RSpec.describe "Demo seeding" do
  def run_seeds(path, enabled: nil, username: "admin")
    env = {
      "RACK_ENV" => "test", "DATABASE_PATH" => path,
      "SEED_MOCK_PRODUCTS" => enabled, "SEED_USERNAME" => username,
      "SEED_PASSWORD" => "demo-password"
    }
    output, status = Open3.capture2e(
      env, RbConfig.ruby, "-rbundler/setup", File.expand_path("../../db/seeds.rb", __dir__)
    )
    expect(status.success?).to be(true), output
  end

  it "only creates the primary user when mock seeding is disabled or unset" do
    [nil, "false"].each do |flag|
      Dir.mktmpdir do |directory|
        path = File.join(directory, "seeds.sqlite3")
        run_seeds(path, enabled: flag)
        database = Challenge::Persistence::Database.new(path)
        expect(database.execute("SELECT username FROM users")).to eq([{ "username" => "admin" }])
        expect(database.execute("SELECT * FROM products")).to be_empty
        expect(database.execute("SELECT * FROM jobs")).to be_empty
        database.close
      end
    end
  end

  it "uses actual user IDs, authenticatable accounts and repeatable products without overwriting edits" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "seeds.sqlite3")
      database = Challenge::Persistence::Database.new(path).setup!
      users = Challenge::Persistence::UserRepository.new(database)
      unrelated = users.create(username: "existing", password: "existing-password", now: Time.now.utc)
      users.create(username: "reviewer", password: "keep-this-password", now: Time.now.utc)
      database.close

      run_seeds(path, enabled: "true", username: "reviewer")
      database = Challenge::Persistence::Database.new(path)
      users = Challenge::Persistence::UserRepository.new(database)
      secondary = users.find_by_username("testuser")
      expect(users.find_by_username("reviewer").authenticate?("keep-this-password")).to be(true)
      expect(secondary.authenticate?("demo-password")).to be(true)
      expect(secondary.id).not_to eq(unrelated.id)
      expect(database.execute("SELECT requested_by_user_id, COUNT(*) AS n FROM products GROUP BY requested_by_user_id"))
        .to match_array([
          { "requested_by_user_id" => secondary.id.to_s, "n" => 25 }
        ])
      id = format("mock-user-%d-product-01", secondary.id)
      database.execute("UPDATE products SET name = ? WHERE id = ?", ["Edited name", id])
      database.close

      run_seeds(path, enabled: "true", username: "reviewer")
      database = Challenge::Persistence::Database.new(path)
      expect(database.execute("SELECT COUNT(*) AS n FROM products").first["n"]).to eq(25)
      expect(database.execute("SELECT name FROM products WHERE id = ?", [id]).first["name"]).to eq("Edited name")
      expect(database.execute("SELECT COUNT(*) AS n FROM users").first["n"]).to eq(3)
      expect(database.execute("SELECT * FROM jobs")).to be_empty
      database.close
    end
  end
end
