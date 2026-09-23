# frozen_string_literal: true

module DatabaseHelpers
  def build_database
    Challenge::Persistence::Database.new(":memory:").setup!
  end
end

RSpec.configure { |config| config.include DatabaseHelpers }
