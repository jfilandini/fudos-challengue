# frozen_string_literal: true

module Challenge
  module Api
    module ProductsRoutes
      def self.registered(app)
        app.helpers do
          def serialize_product(product)
            { id: product.id, name: product.name, created_at: Support::Timestamp.serialize(product.created_at) }
          end
        end

        app.post "/products" do
          job = container.enqueue_product_creation.call(name: validated_params["name"])
          headers "location" => "/jobs/#{job.id}"

          json({ job_id: job.id, product_id: job.product_id, status: job.status }, 202)
        end

        app.get "/products" do
          result = container.list_products.call(
            page: validated_params.fetch("page", 1),
            per_page: validated_params.fetch("per_page", 20)
          )
          json(
            products: result.products.map { |product| serialize_product(product) },
            pagination: {
              page: result.page, per_page: result.per_page,
              total: result.total, total_pages: result.total_pages
            }
          )
        end

        app.get "/products/:id" do
          product = container.find_product.call(validated_params["id"])
          error!(404, :not_found, "The product does not exist") unless product

          json(serialize_product(product))
        end
      end
    end
  end
end
