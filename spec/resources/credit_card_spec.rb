# frozen_string_literal: true

require "spec_helper"

RSpec.describe Asaas::Resources::CreditCard do
  describe ".tokenize" do
    it "POSTs card data once with the per-call API key and returns an AsaasObject" do
      Asaas.configure do |config|
        config.max_retries = 2
        config.retry_delay = 0
      end

      request = stub_request(:post, "#{ASAAS_BASE_URL}/creditCard/tokenizeCreditCard")
                .with(
                  headers: { "access_token" => "sub_key" },
                  body: {
                    "customer" => "cus_1",
                    "creditCard" => { "number" => "4444333322221111" }
                  }
                )
                .to_return(status: 500, body: { errors: [{ description: "Unavailable" }] }.to_json)

      expect do
        described_class.tokenize(
          { customer: "cus_1", creditCard: { number: "4444333322221111" } },
          api_key: "sub_key",
          retryable: false
        )
      end.to raise_error(Asaas::ServerError)

      expect(request).to have_been_requested.once
    end

    it "returns an AsaasObject for a successful tokenization" do
      stub_asaas(
        :post,
        "/creditCard/tokenizeCreditCard",
        body: { "creditCardToken" => "token_1" }
      )

      result = described_class.tokenize(
        { customer: "cus_1", creditCard: { number: "4444333322221111" } },
        api_key: "sub_key",
        retryable: false
      )

      expect(result).to be_a(Asaas::AsaasObject)
      expect(result.creditCardToken).to eq("token_1")
    end
  end
end
