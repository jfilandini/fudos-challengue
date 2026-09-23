# frozen_string_literal: true

module Challenge
  module Domain
    class Product < Data.define(:id, :name, :created_at); end
  end
end
