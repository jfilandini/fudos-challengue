# frozen_string_literal: true

require_relative "../app/boot"

config = Challenge::Config.from_env
mock_products = ENV.fetch("SEED_MOCK_PRODUCTS", "false") == "true"
usernames = [config.seed_username]
test_username = "testuser"
if mock_products && config.seed_username == test_username
  raise ArgumentError, "SEED_USERNAME must differ from the demo account testuser"
end
usernames << test_username if mock_products
product_names = [
  "Espresso", "Cappuccino", "Latte", "Americano", "Mocha", "Tea", "Iced Tea",
  "Orange Juice", "Lemonade", "Mineral Water", "Croissant", "Toast", "Bagel",
  "Muffin", "Brownie", "Cheesecake", "Chocolate Cake", "Sandwich", "Salad",
  "Soup", "Burger", "Pizza", "Pasta", "Fries", "Ice Cream"
].freeze

database = Challenge::Persistence::Database.new(config.database_path).setup!
users = Challenge::Persistence::UserRepository.new(database)
products = Challenge::Persistence::ProductRepository.new(database)

begin
  # Serialize seed runs so checking for existing records and inserting missing
  # ones remains safe if multiple application processes start together.
  database.transaction(mode: :immediate) do
    usernames.each do |username|
      user = users.find_by_username(username)
      if user
        puts "User #{username} already exists"
      else
        user = users.create(username: username, password: config.seed_password, now: Challenge::Support::Clock.new.now)
        puts "Created user #{username}"
      end
      next unless mock_products && username == test_username

      inserted = 0
      product_names.each_with_index do |name, index|
        id = format("mock-user-%d-product-%02d", user.id, index + 1)
        next if products.find(id)

        products.create(
          id: id, name: name, requested_by_user_id: user.id.to_s,
          created_at: Time.utc(2026, 9, 24, 10, index)
        )
        inserted += 1
      end
      puts "Created #{inserted} mock products for #{username}"
    end
  end
ensure
  database.close
end
