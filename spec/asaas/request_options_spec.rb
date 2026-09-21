# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Per-call api_key override" do
  let(:global_key)   { "aact_test_fake" }
  let(:override_key) { "aact_override_fake" }
  let(:base_url)     { "https://sandbox.asaas.com/api/v3" }

  describe "Resources::Base methods" do
    it "uses the override on .create" do
      stub = stub_request(:post, "#{base_url}/customers")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.create({ name: "Maria" }, api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "forwards an explicit idempotency key from .create as a request header" do
      key = "scoby-customer-42"
      stub = stub_request(:post, "#{base_url}/customers")
             .with(
               body: { "name" => "Maria" },
               headers: { "Idempotency-Key" => key }
             )
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.create({ name: "Maria" }, idempotency_key: key)

      expect(stub).to have_been_requested
    end

    it "uses the override on .retrieve" do
      stub = stub_request(:get, "#{base_url}/customers/cus_1")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.retrieve("cus_1", api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "uses the override on .update" do
      stub = stub_request(:put, "#{base_url}/customers/cus_1")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.update("cus_1", { name: "Atualizado" }, api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "uses the override on .delete" do
      stub = stub_request(:delete, "#{base_url}/customers/cus_1")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: {}.to_json)

      Asaas::Resources::Customer.delete("cus_1", api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "uses the override on .list" do
      stub = stub_request(:get, "#{base_url}/customers")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: list_response([]).to_json)

      Asaas::Resources::Customer.list({}, api_key: override_key)

      expect(stub).to have_been_requested
    end
  end

  describe "Resources with custom methods" do
    it "uses the override on Customer.notifications" do
      stub = stub_request(:get, "#{base_url}/customers/cus_1/notifications")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: list_response([]).to_json)

      Asaas::Resources::Customer.notifications("cus_1", {}, api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "uses the override on Payment.refund" do
      stub = stub_request(:post, "#{base_url}/payments/pay_1/refund")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: { "id" => "pay_1" }.to_json)

      Asaas::Resources::Payment.refund("pay_1", { value: 10.0 }, api_key: override_key)

      expect(stub).to have_been_requested
    end

    it "uses the override on Finance.balance (no params arg)" do
      stub = stub_request(:get, "#{base_url}/finance/account/balance")
             .with(headers: { "access_token" => override_key })
             .to_return(status: 200, body: { "balance" => 0 }.to_json)

      Asaas::Resources::Finance.balance(api_key: override_key)

      expect(stub).to have_been_requested
    end
  end

  describe "fallback to global" do
    it "uses the global api_key when no opts are passed" do
      stub = stub_request(:get, "#{base_url}/customers/cus_1")
             .with(headers: { "access_token" => global_key })
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.retrieve("cus_1")

      expect(stub).to have_been_requested
    end

    it "uses the global api_key when opts omit :api_key" do
      stub = stub_request(:get, "#{base_url}/customers/cus_1")
             .with(headers: { "access_token" => global_key })
             .to_return(status: 200, body: { "id" => "cus_1" }.to_json)

      Asaas::Resources::Customer.retrieve("cus_1", {})

      expect(stub).to have_been_requested
    end
  end

  describe "ListObject pagination" do
    it "carries the override into next_page" do
      page1 = list_response([{ "id" => "cus_1" }], has_more: true).merge("limit" => 1, "offset" => 0)
      page2 = list_response([{ "id" => "cus_2" }], has_more: false).merge("limit" => 1, "offset" => 1)

      stub_request(:get, "#{base_url}/customers")
        .with(query: { "limit" => "1" }, headers: { "access_token" => override_key })
        .to_return(status: 200, body: page1.to_json)
      page2_stub = stub_request(:get, "#{base_url}/customers")
                   .with(query: { "limit" => "1", "offset" => "1" },
                         headers: { "access_token" => override_key })
                   .to_return(status: 200, body: page2.to_json)

      list = Asaas::Resources::Customer.list({ limit: 1 }, api_key: override_key)
      list.next_page

      expect(page2_stub).to have_been_requested
    end
  end
end
