# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Asaas::Client do
  let(:api_key) { "aact_test_fake" }
  let(:base_url) { "https://sandbox.asaas.com/api/v3" }

  before do
    Asaas.configure do |c|
      c.api_key     = api_key
      c.sandbox     = true
      c.max_retries = 0
    end
  end

  subject(:client) { described_class.new }

  describe "#request" do
    context "GET" do
      it "returns parsed JSON body on success" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 200, body: { "totalCount" => 1 }.to_json,
                     headers: { "Content-Type" => "application/json" })

        result = client.request(:get, "/customers")

        expect(result).to eq({ "totalCount" => 1 })
      end

      it "appends query params to the URL" do
        stub = stub_request(:get, "#{base_url}/customers")
               .with(query: { "name" => "João" })
               .to_return(status: 200, body: {}.to_json)

        client.request(:get, "/customers", params: { name: "João" })

        expect(stub).to have_been_requested
      end

      it "flattens nested query params" do
        stub = stub_request(:get, "#{base_url}/payments")
               .with(query: { "filter[status]" => "PENDING" })
               .to_return(status: 200, body: {}.to_json)

        client.request(:get, "/payments", params: { filter: { status: "PENDING" } })

        expect(stub).to have_been_requested
      end

      it "serializes array params as comma-separated values" do
        stub = stub_request(:get, "#{base_url}/payments")
               .with(query: { "status" => "PENDING,OVERDUE" })
               .to_return(status: 200, body: {}.to_json)

        client.request(:get, "/payments", params: { status: %w[PENDING OVERDUE] })

        expect(stub).to have_been_requested
      end
    end

    context "POST" do
      it "sends body as JSON" do
        stub = stub_request(:post, "#{base_url}/customers")
               .with(body: { "name" => "Maria" })
               .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

        result = client.request(:post, "/customers", params: { name: "Maria" })

        expect(result["id"]).to eq("cus_1")
        expect(stub).to have_been_requested
      end

      it "sends an Idempotency-Key header" do
        stub = stub_request(:post, "#{base_url}/customers")
               .with(headers: { "Idempotency-Key" => /\S+/ })
               .to_return(status: 200, body: {}.to_json)

        client.request(:post, "/customers", params: {})

        expect(stub).to have_been_requested
      end

      it "reuses the same Idempotency-Key across retries" do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 1
          c.retry_delay = 0
        end

        received_keys = []

        stub_request(:post, "#{base_url}/customers")
          .to_return do |req|
            received_keys << req.headers["Idempotency-Key"]
            received_keys.size == 1 ? { status: 500, body: {}.to_json } : { status: 200, body: {}.to_json }
          end

        client.request(:post, "/customers", params: {})

        expect(received_keys.size).to eq(2)
        expect(received_keys.uniq.size).to eq(1)
      end

      it "makes one transport call after a retryable response when retryable is false" do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 2
          c.retry_delay = 0
        end
        request = stub_request(:post, "#{base_url}/payments")
                  .to_return(status: 503, body: {}.to_json)

        expect do
          client.request(:post, "/payments", retryable: false)
        end.to raise_error(Asaas::ServerError)

        expect(request).to have_been_requested.once
      end

      it "makes one transport call after a timeout when retryable is false" do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 2
          c.retry_delay = 0
        end
        request = stub_request(:post, "#{base_url}/payments").to_timeout

        expect do
          client.request(:post, "/payments", retryable: false)
        end.to raise_error(Asaas::ConnectionError)

        expect(request).to have_been_requested.once
      end

      it "applies a per-call timeout without changing the global timeout" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:request).and_return(
          instance_double(Net::HTTPResponse, code: "200", body: "{}", :[] => nil)
        )

        client.request(:post, "/payments", timeout: 65)

        expect(http).to have_received(:read_timeout=).with(65)
        expect(http).to have_received(:open_timeout=).with(65)
        expect(Asaas.config.timeout).to eq(30)
      end
    end

    context "authentication" do
      it "sends access_token header" do
        stub = stub_request(:get, "#{base_url}/customers")
               .with(headers: { "access_token" => api_key })
               .to_return(status: 200, body: {}.to_json)

        client.request(:get, "/customers")

        expect(stub).to have_been_requested
      end

      it "overrides the global api_key when one is passed to the constructor" do
        override_key = "aact_override_fake"
        stub = stub_request(:get, "#{base_url}/customers")
               .with(headers: { "access_token" => override_key })
               .to_return(status: 200, body: {}.to_json)

        described_class.new(api_key: override_key).request(:get, "/customers")

        expect(stub).to have_been_requested
      end

      it "falls back to the global api_key when override is nil" do
        stub = stub_request(:get, "#{base_url}/customers")
               .with(headers: { "access_token" => api_key })
               .to_return(status: 200, body: {}.to_json)

        described_class.new(api_key: nil).request(:get, "/customers")

        expect(stub).to have_been_requested
      end

      it "uses the override even when the global api_key is unset" do
        Asaas.configure { |c| c.api_key = nil }
        override_key = "aact_override_fake"
        stub = stub_request(:get, "#{base_url}/customers")
               .with(headers: { "access_token" => override_key })
               .to_return(status: 200, body: {}.to_json)

        described_class.new(api_key: override_key).request(:get, "/customers")

        expect(stub).to have_been_requested
      end
    end

    context "error responses" do
      it "raises AuthenticationError on 401" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 401, body: { "errors" => [{ "description" => "Invalid API key" }] }.to_json)

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::AuthenticationError)
      end

      it "raises NotFoundError on 404" do
        stub_request(:get, "#{base_url}/customers/notfound")
          .to_return(status: 404, body: {}.to_json)

        expect { client.request(:get, "/customers/notfound") }.to raise_error(Asaas::NotFoundError)
      end

      it "raises ServerError on 500" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 500, body: {}.to_json)

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::ServerError)
      end

      it "raises ConnectionError on network failure" do
        stub_request(:get, "#{base_url}/customers").to_raise(SocketError)

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::ConnectionError)
      end

      it "handles empty response body" do
        stub_request(:delete, "#{base_url}/customers/cus_1")
          .to_return(status: 200, body: "")

        expect { client.request(:delete, "/customers/cus_1") }.not_to raise_error
      end
    end

    context "retries" do
      before do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 2
          c.retry_delay = 0
        end
      end

      it "retries on 500 and succeeds" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 500, body: {}.to_json).then
          .to_return(status: 200, body: { "ok" => true }.to_json)

        result = client.request(:get, "/customers")

        expect(result["ok"]).to be true
      end

      it "raises after exhausting retries" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 500, body: {}.to_json).times(3)

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::ServerError)
      end

      it "does not retry on 404" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 404, body: {}.to_json)

        begin
          client.request(:get, "/customers")
        rescue StandardError
          nil
        end

        expect(WebMock).to have_requested(:get, "#{base_url}/customers").once
      end

      it "keeps retrying GET requests by default" do
        request = stub_request(:get, "#{base_url}/customers")
                  .to_return(status: 503, body: {}.to_json).then
                  .to_return(status: 200, body: { "ok" => true }.to_json)

        result = client.request(:get, "/customers")

        expect(result).to eq({ "ok" => true })
        expect(request).to have_been_requested.twice
      end
    end

    context "logging" do
      let(:logger) do
        Class.new do
          attr_reader :messages

          def initialize
            @messages = []
          end

          def debug(message)
            messages << message
          end
        end.new
      end

      let(:log_output) { logger.messages.join("\n") }

      before do
        Asaas.configure do |c|
          c.api_key = api_key
          c.sandbox = true
          c.logger = logger
        end
      end

      after { Asaas.configure { |c| c.logger = nil } }

      it "filters card data from request and parsed response logs" do
        stub_request(:post, "#{base_url}/creditCard/tokenizeCreditCard")
          .to_return(
            status: 200,
            body: {
              "creditCardToken" => "returned_token_secret",
              "remoteIp" => "203.0.113.9",
              "cardNumber" => "5555444433332222",
              "ccv" => "999",
              "CVV" => "888"
            }.to_json
          )

        client.request(
          :post,
          "/creditCard/tokenizeCreditCard",
          params: {
            customer: "cus_1",
            creditCard: { number: "4444333322221111", ccv: "764" },
            creditCardHolderInfo: { cpfCnpj: "98765432100" },
            remoteIp: "198.51.100.7"
          },
          retryable: false
        )

        expect(log_output).to include("[FILTERED]")
        expect(log_output).not_to include(
          "4444333322221111",
          "764",
          "98765432100",
          "198.51.100.7",
          "returned_token_secret",
          "203.0.113.9",
          "5555444433332222",
          "999",
          "888"
        )
      end

      it "logs status and byte length without the raw body when response JSON is invalid" do
        stub_request(:get, "#{base_url}/customers")
          .to_return(status: 200, body: "raw-secret-body")

        client.request(:get, "/customers")

        expect(log_output).to include("200", "15 bytes")
        expect(log_output).not_to include("raw-secret-body")
      end
    end

    context "multipart/form-data" do
      it "sends multipart when a param value is an IO" do
        stub = stub_request(:post, "#{base_url}/paymentLinks/lnk_1/images")
               .with(headers: { "Content-Type" => %r{multipart/form-data} })
               .to_return(status: 200, body: { "id" => "img_1" }.to_json)

        client.request(:post, "/paymentLinks/lnk_1/images", params: { image: StringIO.new("data") })

        expect(stub).to have_been_requested
      end

      it "does not send application/json when body has an IO param" do
        json_stub = stub_request(:post, "#{base_url}/paymentLinks/lnk_1/images")
                    .with(headers: { "Content-Type" => "application/json" })
                    .to_return(status: 200, body: {}.to_json)
        stub_request(:post, "#{base_url}/paymentLinks/lnk_1/images")
          .with(headers: { "Content-Type" => %r{multipart/form-data} })
          .to_return(status: 200, body: {}.to_json)

        client.request(:post, "/paymentLinks/lnk_1/images", params: { image: StringIO.new("data") })

        expect(json_stub).not_to have_been_requested
      end

      it "sends JSON normally when no param is an IO" do
        stub = stub_request(:post, "#{base_url}/customers")
               .with(headers: { "Content-Type" => "application/json" })
               .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

        client.request(:post, "/customers", params: { name: "Maria" })

        expect(stub).to have_been_requested
      end
    end

    context "configuration" do
      it "raises ConfigurationError when api_key is nil" do
        Asaas.configure { |c| c.api_key = nil }

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::ConfigurationError)
      end

      it "raises ConfigurationError when api_key is empty" do
        Asaas.configure { |c| c.api_key = "" }

        expect { client.request(:get, "/customers") }.to raise_error(Asaas::ConfigurationError)
      end
    end
  end
end
