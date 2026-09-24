# frozen_string_literal: true

module Challenge
  module Api
    module MetaRoutes
      def self.registered(app)
        app.get "/health" do
          json(status: "ok")
        end
      end
    end
  end
end
