# frozen_string_literal: true

module Asaas
  module Resources
    class CreditCard < Base
      def self.resource_path = "/creditCard"

      def self.tokenize(params = {}, opts = {})
        response = client(opts).request(
          :post,
          "#{resource_path}/tokenizeCreditCard",
          params: params,
          retryable: opts.fetch(:retryable, false),
          timeout: opts[:timeout]
        )
        AsaasObject.construct_from(response)
      end
    end
  end
end
