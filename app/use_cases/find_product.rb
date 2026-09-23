# frozen_string_literal: true

module Challenge
  module UseCases
    class FindProduct
      def initialize(product_repository:)
        @product_repository = product_repository
      end

      def call(id)
        @product_repository.find(id)
      end
    end
  end
end
