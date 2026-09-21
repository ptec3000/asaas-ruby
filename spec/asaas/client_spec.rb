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

      it "does not add an Idempotency-Key to GET requests" do
        key = "scoby-customer-42"
        stub = stub_request(:get, "#{base_url}/customers")
               .with { |request| request.headers["Idempotency-Key"].nil? }
               .to_return(status: 200, body: {}.to_json)

        client.request(:get, "/customers", idempotency_key: key)

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

      it "uses an explicit Idempotency-Key without serializing it into the body" do
        key = "scoby-customer-42"
        stub = stub_request(:post, "#{base_url}/customers")
               .with(
                 body: { "name" => "Maria" },
                 headers: { "Idempotency-Key" => key }
               )
               .to_return(status: 200, body: {}.to_json)

        client.request(:post, "/customers", params: { name: "Maria" }, idempotency_key: key)

        expect(stub).to have_been_requested
      end

      it "prefers an explicit Idempotency-Key over a conflicting custom header" do
        key = "scoby-customer-42"
        stub = stub_request(:post, "#{base_url}/customers")
               .with(headers: { "Idempotency-Key" => key })
               .to_return(status: 200, body: {}.to_json)

        client.request(
          :post,
          "/customers",
          headers: { "Idempotency-Key" => "other-key" },
          idempotency_key: key
        )

        expect(stub).to have_been_requested
      end

      it "replaces case-insensitive Idempotency-Key header variants with the explicit key" do
        key = "scoby-customer-42"
        idempotency_headers = []

        stub_request(:post, "#{base_url}/customers")
          .to_return do |request|
            idempotency_headers << request.headers.select do |name, _|
              name.casecmp?("Idempotency-Key")
            end
            { status: 200, body: {}.to_json }
          end

        client.request(
          :post,
          "/customers",
          headers: { "idempotency-key" => "other-key" },
          idempotency_key: key
        )

        expect(idempotency_headers).to eq([{ "Idempotency-Key" => key }])
      end

      it "rejects blank explicit Idempotency-Keys before sending a request" do
        request = stub_request(:post, "#{base_url}/customers")

        expect do
          client.request(:post, "/customers", idempotency_key: "  ")
        end.to raise_error(ArgumentError, "idempotency_key must be a non-blank String")

        expect(request).not_to have_been_requested
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

      it "reuses an explicit Idempotency-Key across retries" do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 1
          c.retry_delay = 0
        end

        received_keys = []
        key = "scoby-customer-42"

        stub_request(:post, "#{base_url}/customers")
          .to_return do |req|
            received_keys << req.headers["Idempotency-Key"]
            received_keys.size == 1 ? { status: 500, body: {}.to_json } : { status: 200, body: {}.to_json }
          end

        client.request(:post, "/customers", params: {}, idempotency_key: key)

        expect(received_keys).to eq([key, key])
      end

      it "keeps an explicit Idempotency-Key stable when its caller mutates the original between retries" do
        Asaas.configure do |c|
          c.api_key     = api_key
          c.sandbox     = true
          c.max_retries = 1
          c.retry_delay = 0
        end

        expected_key = "scoby-customer-42"
        key = expected_key.dup
        received_keys = []

        stub_request(:post, "#{base_url}/customers")
          .to_return do |request|
            received_keys << request.headers["Idempotency-Key"]
            key.replace("mutated-key") if received_keys.one?
            received_keys.one? ? { status: 500, body: {}.to_json } : { status: 200, body: {}.to_json }
          end

        client.request(:post, "/customers", params: {}, idempotency_key: key)

        expect(received_keys).to eq([expected_key, expected_key])
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

      it "does not include explicit Idempotency-Keys in request logs" do
        key = "scoby-customer-42"
        stub_request(:post, "#{base_url}/customers")
          .to_return(status: 200, body: {}.to_json)

        client.request(:post, "/customers", params: { name: "Maria" }, idempotency_key: key)

        expect(log_output).not_to include(key)
      end

      it "filters nested authentication secrets from request logs without hiding operational fields" do
        stub_request(:post, "#{base_url}/webhooks")
          .to_return(status: 200, body: {}.to_json)

        client.request(
          :post,
          "/webhooks",
          params: {
            webhooks: [
              {
                authToken: "webhook-auth-secret",
                event: "PAYMENT_CREATED",
                tokenCount: 2
              },
              {
                "AUTH_TOKEN" => "uppercase-auth-secret",
                "authenticationType" => "TOKEN"
              }
            ],
            credentials: {
              accessToken: "access-token-secret",
              refresh_token: "refresh-token-secret",
              clientSecret: "client-secret-value",
              secret: "generic-secret-value",
              secretary: "operations"
            }
          }
        )

        request_log = logger.messages.find { |message| message.include?("[Asaas] -->") }
        logged_body = request_log.delete_prefix("[Asaas] --> POST #{base_url}/webhooks ")

        expect(JSON.parse(logged_body)).to eq(
          {
            "webhooks" => [
              {
                "authToken" => "[FILTERED]",
                "event" => "PAYMENT_CREATED",
                "tokenCount" => 2
              },
              {
                "AUTH_TOKEN" => "[FILTERED]",
                "authenticationType" => "TOKEN"
              }
            ],
            "credentials" => {
              "accessToken" => "[FILTERED]",
              "refresh_token" => "[FILTERED]",
              "clientSecret" => "[FILTERED]",
              "secret" => "[FILTERED]",
              "secretary" => "operations"
            }
          }
        )
        expect(log_output).not_to include(
          "webhook-auth-secret",
          "uppercase-auth-secret",
          "access-token-secret",
          "refresh-token-secret",
          "client-secret-value",
          "generic-secret-value"
        )
      end

      it "filters nested API keys from response logs without hiding operational fields" do
        stub_request(:get, "#{base_url}/accounts")
          .to_return(
            status: 200,
            body: {
              "apiKey" => "response-api-secret",
              "accounts" => [
                {
                  "API_KEY" => "uppercase-api-secret",
                  "authorization" => "Bearer response-secret",
                  "status" => "ACTIVE"
                }
              ],
              "apiKeyStatus" => "ENABLED",
              "tokenCount" => 3,
              "secretary" => "operations"
            }.to_json
          )

        client.request(:get, "/accounts")

        response_log = logger.messages.find { |message| message.include?("[Asaas] <--") }
        logged_body = response_log.split(" ", 4).last

        expect(JSON.parse(logged_body)).to eq(
          {
            "apiKey" => "[FILTERED]",
            "accounts" => [
              {
                "API_KEY" => "[FILTERED]",
                "authorization" => "[FILTERED]",
                "status" => "ACTIVE"
              }
            ],
            "apiKeyStatus" => "ENABLED",
            "tokenCount" => 3,
            "secretary" => "operations"
          }
        )
        expect(log_output).not_to include(
          "response-api-secret",
          "uppercase-api-secret",
          "Bearer response-secret"
        )
      end

      it "logs a bounded parseable summary for a large UTF-8 response" do
        large_value = "ação 🎲 " * 80
        stub_request(:get, "#{base_url}/customers")
          .to_return(
            status: 200,
            body: { "description" => large_value, "status" => "ACTIVE" }.to_json
          )

        client.request(:get, "/customers")

        response_log = logger.messages.find { |message| message.include?("[Asaas] <--") }
        logged_body = response_log.split(" ", 4).last
        parsed_body = JSON.parse(logged_body)

        expect(logged_body.bytesize).to be <= 200
        expect(parsed_body).to include("_truncated" => true)
        expect(log_output).not_to include(large_value)
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
