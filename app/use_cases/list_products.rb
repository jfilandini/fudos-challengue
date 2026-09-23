# frozen_string_literal: true

module Challenge
  module UseCases
    class ListProducts
      Result = Data.define(:products, :page, :per_page, :total, :total_pages)

      def initialize(product_repository:)
        @product_repository = product_repository
      end

      def call(page: 1, per_page: 20)
        unless page.is_a?(Integer) && page.between?(1, 2_147_483_647) &&
               per_page.is_a?(Integer) && per_page.between?(1, 100)
          raise ArgumentError, "page must be between 1 and 2147483647 and per_page between 1 and 100"
        end

        result = @product_repository.paginate(limit: per_page, offset: (page - 1) * per_page)
        total = result.fetch(:total)
        Result.new(
          products: result.fetch(:products), page: page, per_page: per_page,
          total: total, total_pages: (total + per_page - 1) / per_page
        )
      end
    end
  end
end
