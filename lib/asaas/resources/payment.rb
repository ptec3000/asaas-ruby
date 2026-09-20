# frozen_string_literal: true

module Asaas
  module Resources
    class Payment < Base
      def self.resource_path = "/payments"

      def self.restore(id, opts = {})
        response = client(opts).request(:post, "#{resource_path}/#{id}/restore")
        AsaasObject.construct_from(response)
      end

      def self.refund(id, params = {}, opts = {})
        response = client(opts).request(:post, "#{resource_path}/#{id}/refund", params: params)
        AsaasObject.construct_from(response)
      end

      def self.capture(id, opts = {})
        response = client(opts).request(:post, "#{resource_path}/#{id}/capture")
        AsaasObject.construct_from(response)
      end

      def self.confirm_cash_receipt(id, params = {}, opts = {})
        response = client(opts).request(:post, "#{resource_path}/#{id}/confirmCashReceipt", params: params)
        AsaasObject.construct_from(response)
      end

      def self.payment_info(id, opts = {})
        response = client(opts).request(:get, "#{resource_path}/#{id}/paymentInfo")
        AsaasObject.construct_from(response)
      end

      def self.pix_qr_code(id, opts = {})
        response = client(opts).request(:get, "#{resource_path}/#{id}/pixQrCode")
        AsaasObject.construct_from(response)
      end
    end
  end
end
