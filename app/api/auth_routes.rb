# frozen_string_literal: true

module Challenge
  module Api
    module AuthRoutes
      def self.registered(app)
        app.post "/auth/login" do
          result = container.authenticate_user.call(
            username: validated_params["username"],
            password: validated_params["password"]
          )

          json(token: result.token, token_type: "Bearer", expires_in: result.expires_in)
        rescue UseCases::AuthenticateUser::InvalidCredentials
          error!(401, :invalid_credentials, "Username or password is invalid")
        end
      end
    end
  end
end
