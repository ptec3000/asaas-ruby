# frozen_string_literal: true

module Asaas
  module Resources
    class Base
      extend HasClient

      def self.resource_path
        raise NotImplementedError, "#{name} must define resource_path"
      end

      def self.create(params = {}, opts = {})
        response = client(opts).request(
          :post,
          resource_path,
          params: params,
          retryable: opts.fetch(:retryable, true),
          timeout: opts[:timeout],
          idempotency_key: opts[:idempotency_key]
        )
        AsaasObject.construct_from(response)
      end

      def self.retrieve(id, opts = {})
        response = client(opts).request(:get, "#{resource_path}/#{id}")
        AsaasObject.construct_from(response)
      end

      def self.update(id, params = {}, opts = {})
        response = client(opts).request(:put, "#{resource_path}/#{id}", params: params)
        AsaasObject.construct_from(response)
      end

      def self.delete(id, opts = {})
        response = client(opts).request(:delete, "#{resource_path}/#{id}")
        AsaasObject.construct_from(response)
      end

      def self.list(params = {}, opts = {})
        response = client(opts).request(:get, resource_path, params: params)
        ListObject.construct_from(response, client: client(opts), path: resource_path, params: params)
      end
    end
  end
end
