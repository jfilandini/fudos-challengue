# frozen_string_literal: true

module Challenge
  module Domain
    class Product < Data.define(:id, :name, :created_at, :requested_by_user_id); end
  end
end
