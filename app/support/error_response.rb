# frozen_string_literal: true

module Challenge
  module Support
    module ErrorResponse
      JSON_CONTENT_TYPE = "application/json"

      module_function

      def body(code, message)
        JSON.generate(error: { code: code.to_s, message: message })
      end

      def rack(status, code, message)
        [status, { "content-type" => JSON_CONTENT_TYPE }, [body(code, message)]]
      end
    end
  end
end
