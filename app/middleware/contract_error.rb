# frozen_string_literal: true

module Challenge
  module Middleware
    class ContractError < Committee::ValidationError
      CODES = {
        bad_request: "invalid_request",
        not_found: "not_found",
        invalid_response: "internal_error"
      }.freeze

      SERVER_ERROR_MESSAGE = "The request could not be completed"

      def render
        Support::ErrorResponse.rack(status, CODES.fetch(id, "invalid_request"), client_message)
      end

      private

      def client_message
        status >= 500 ? SERVER_ERROR_MESSAGE : message
      end
    end
  end
end
