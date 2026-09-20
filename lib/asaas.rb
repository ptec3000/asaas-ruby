# frozen_string_literal: true

require_relative "asaas/version"
require_relative "asaas/configuration"
require_relative "asaas/errors"
require_relative "asaas/webhook_event"
require_relative "asaas/asaas_object"
require_relative "asaas/list_object"
require_relative "asaas/client"
require_relative "asaas/resources/has_client"
require_relative "asaas/resources/base"
require_relative "asaas/resources/customer"
require_relative "asaas/resources/credit_card"
require_relative "asaas/resources/payment"
require_relative "asaas/resources/subscription"
require_relative "asaas/resources/webhook"
require_relative "asaas/resources/finance"
require_relative "asaas/resources/pix"
require_relative "asaas/resources/payment_link"
require_relative "asaas/resources/transfer"
require_relative "asaas/resources/installment"
require_relative "asaas/resources/checkout"
require_relative "asaas/resources/invoice"
require_relative "asaas/resources/split"
require_relative "asaas/resources/anticipation"
require_relative "asaas/resources/notification"
require_relative "asaas/resources/dunning"
require_relative "asaas/resources/chargeback"
require_relative "asaas/resources/subaccount"
require_relative "asaas/resources/bill_payment"
require_relative "asaas/resources/pix_automatic"
require_relative "asaas/resources/sandbox"
require_relative "asaas/resources/document"
require_relative "asaas/resources/my_account"

module Asaas
  @config = Configuration.new

  class << self
    attr_reader :config

    def configure
      yield @config
    end

    def api_key=(key)
      @config.api_key = key
    end

    def api_key
      @config.api_key
    end

    def sandbox=(val)
      @config.sandbox = val
    end

    def sandbox?
      @config.sandbox
    end
  end
end
