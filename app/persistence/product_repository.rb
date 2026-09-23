# frozen_string_literal: true

module Challenge
  module Persistence
    class ProductRepository
      def initialize(database)
        @database = database
      end

      def create(id:, name:, created_at:, requested_by_user_id: nil)
        @database.execute(
          "INSERT INTO products (id, name, created_at, requested_by_user_id) VALUES (?, ?, ?, ?)",
          [id, name, Support::Timestamp.serialize(created_at), requested_by_user_id]
        )
        Domain::Product.new(id: id, name: name, created_at: created_at, requested_by_user_id: requested_by_user_id)
      end

      def find(id)
        row = @database.execute("SELECT id, name, created_at, requested_by_user_id FROM products WHERE id = ?", [id]).first
        row && to_product(row)
      end

      def paginate(limit:, offset:)
        @database.transaction do
          total = @database.execute("SELECT COUNT(*) AS total FROM products").first.fetch("total")
          rows = @database.execute(
            "SELECT id, name, created_at, requested_by_user_id FROM products ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
            [limit, offset]
          )
          { products: rows.map { |row| to_product(row) }, total: total }
        end
      end

      private

      def to_product(row)
        Domain::Product.new(id: row["id"], name: row["name"], created_at: Support::Timestamp.parse(row["created_at"]),
                            requested_by_user_id: row["requested_by_user_id"])
      end
    end
  end
end
