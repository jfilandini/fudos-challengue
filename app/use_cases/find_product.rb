# frozen_string_literal: true

module Challenge
  module UseCases
    class FindProduct
      def initialize(product_repository:)
        @product_repository = product_repository
      end

      def call(id, requested_by_user_id:)
        @product_repository.find_for_user(id, requested_by_user_id: requested_by_user_id)
      end
    end
  end
end
