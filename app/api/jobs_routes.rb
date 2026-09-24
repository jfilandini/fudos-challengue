# frozen_string_literal: true

module Challenge
  module Api
    module JobsRoutes
      def self.registered(app)
        app.get "/jobs/:id" do
          job = container.find_job.call(
            validated_params["id"], requested_by_user_id: env.fetch(Middleware::Authentication::USER_ID_KEY)
          )
          error!(404, :not_found, "The job does not exist") unless job

          json(
            id: job.id,
            product_id: job.product_id,
            status: job.status,
            created_at: Support::Timestamp.serialize(job.created_at),
            updated_at: Support::Timestamp.serialize(job.updated_at)
          )
        end
      end
    end
  end
end
