# asaas-ruby

Ruby SDK for the [Asaas](https://www.asaas.com) payment gateway API.

## Installation

Add to your Gemfile:

```ruby
gem "asaas-ruby"
```

Or install directly:

```bash
gem install asaas-ruby
```

## Configuration

```ruby
Asaas.configure do |c|
  c.api_key  = "your_api_key"
  c.sandbox  = true   # false in production
end
```

| Option | Default | Description |
|---|---|---|
| `api_key` | `nil` | Your Asaas API key |
| `sandbox` | `false` | Use sandbox environment |
| `timeout` | `30` | HTTP timeout in seconds |
| `max_retries` | `2` | Retries on 5xx / network errors |
| `retry_delay` | `0.5` | Base delay in seconds (exponential backoff) |
| `logger` | `nil` | Any Logger-compatible object |

### Per-call API key

Every resource method accepts a final positional options hash that overrides the global `api_key` — useful for multi-tenant apps and subaccount keys. When passing options, the `params` hash must be explicit.

```ruby
Asaas::Resources::Customer.retrieve("cus_123", api_key: "aact_subaccount_key")
Asaas::Resources::Customer.list({ name: "João" }, api_key: "aact_subaccount_key")
Asaas::Resources::Payment.create(
  { customer: "cus_123", value: 10.0, billingType: "PIX", dueDate: "2025-12-31" },
  api_key: "aact_subaccount_key"
)
Asaas::Resources::Finance.balance(api_key: "aact_subaccount_key")
```

### Stable idempotency keys for creates

`Base.create` resources accept `idempotency_key:` in the final options hash.
It is sent only as the `Idempotency-Key` HTTP header, and the same value is
preserved if the request is retried. The key must be a non-blank `String`.

```ruby
Asaas::Resources::Customer.create(
  { name: "João Silva", email: "joao@example.com" },
  idempotency_key: "scoby-customer-42"
)
```

`ListObject` pages returned with an override keep that override when paginated:

```ruby
list = Asaas::Resources::Customer.list({ limit: 50 }, api_key: "aact_subaccount_key")
list.next_page  # also uses aact_subaccount_key
```

For direct `Client` usage:

```ruby
client = Asaas::Client.new(api_key: "aact_subaccount_key")
client.request(:get, "/customers")
```

## Usage

All resources return `AsaasObject` instances with dot-access to attributes. List endpoints return `ListObject`, which supports pagination.

### Customers

```ruby
customer = Asaas::Customer.create(name: "João Silva", cpfCnpj: "000.000.000-00", email: "joao@example.com")
customer.id       # => "cus_..."
customer.name     # => "João Silva"

Asaas::Customer.retrieve("cus_123")
Asaas::Customer.update("cus_123", name: "João Atualizado")
Asaas::Customer.delete("cus_123")
Asaas::Customer.restore("cus_123")
Asaas::Customer.list(name: "João")
Asaas::Customer.notifications("cus_123")
```

### Payments

```ruby
payment = Asaas::Payment.create(
  customer:    "cus_123",
  billingType: "PIX",
  value:       150.0,
  dueDate:     "2025-12-31"
)

Asaas::Payment.retrieve("pay_123")
Asaas::Payment.update("pay_123", value: 200.0)
Asaas::Payment.delete("pay_123")
Asaas::Payment.restore("pay_123")
Asaas::Payment.list(status: "PENDING")
Asaas::Payment.refund("pay_123", value: 150.0)
Asaas::Payment.capture("pay_123")
Asaas::Payment.confirm_cash_receipt("pay_123", paymentDate: "2025-01-15")
Asaas::Payment.payment_info("pay_123")
```

### Subscriptions

```ruby
subscription = Asaas::Subscription.create(
  customer:    "cus_123",
  billingType: "PIX",
  value:       49.90,
  cycle:       "MONTHLY",
  nextDueDate: "2025-02-01"
)

Asaas::Subscription.retrieve("sub_123")
Asaas::Subscription.update("sub_123", value: 59.90)
Asaas::Subscription.delete("sub_123")
Asaas::Subscription.list
Asaas::Subscription.payments("sub_123")
```

### Pix

```ruby
Asaas::Pix.create_key(type: "EMAIL", key: "joao@example.com")
Asaas::Pix.list_keys
Asaas::Pix.delete_key("key_123")

qr = Asaas::Pix.create_qr_code(addressKey: "joao@example.com", value: 50.0)
qr.payload    # => "00020101..."

Asaas::Pix.transactions(type: "CREDIT")
Asaas::Pix.decode_qr_code(payload: "00020101...")
```

### Finance

```ruby
balance = Asaas::Finance.balance
balance.balance         # => 1500.0
balance.blockedBalance  # => 0.0

Asaas::Finance.statistics(billingType: "PIX")
Asaas::Finance.extract
```

### Payment Links

```ruby
link = Asaas::PaymentLink.create(name: "Produto X", value: 99.90, billingType: "UNDEFINED")
Asaas::PaymentLink.retrieve("lnk_123")
Asaas::PaymentLink.update("lnk_123", value: 149.90)
Asaas::PaymentLink.delete("lnk_123")
Asaas::PaymentLink.list
Asaas::PaymentLink.add_image("lnk_123", image: "base64data")
```

### Transfers

```ruby
Asaas::Transfer.create(value: 500.0, walletId: "wal_abc")
Asaas::Transfer.retrieve("tra_123")
Asaas::Transfer.list
Asaas::Transfer.delete("tra_123")  # cancel
```

### Installments

```ruby
Asaas::Installment.create(customer: "cus_123", value: 1200.0, installmentCount: 12, billingType: "CREDIT_CARD")
Asaas::Installment.retrieve("ins_123")
Asaas::Installment.list
Asaas::Installment.delete("ins_123")
Asaas::Installment.update_splits("ins_123", splits: [{ walletId: "wal_1", percentualValue: 10.0 }])
```

### Webhooks

```ruby
Asaas::Webhook.create(url: "https://example.com/webhook", email: "dev@example.com")
Asaas::Webhook.retrieve("web_123")
Asaas::Webhook.update("web_123", url: "https://example.com/new")
Asaas::Webhook.delete("web_123")
Asaas::Webhook.list
Asaas::Webhook.remove_penalty("web_123")
```

### Notifications

```ruby
Asaas::Notification.update("not_123", enabled: false)
Asaas::Notification.update_batch(notifications: [{ id: "not_123", enabled: true }])
```

### Invoices

```ruby
Asaas::Invoice.create(payment: "pay_123", serviceDescription: "Consultoria")
Asaas::Invoice.retrieve("inv_123")
Asaas::Invoice.update("inv_123", serviceDescription: "Desenvolvimento")
Asaas::Invoice.delete("inv_123")
Asaas::Invoice.list
```

### Anticipations

```ruby
Asaas::Anticipation.simulate(payment: "pay_123")
Asaas::Anticipation.create(payment: "pay_123")
Asaas::Anticipation.retrieve("ant_123")
Asaas::Anticipation.list
Asaas::Anticipation.delete("ant_123")  # cancel
```

### Splits

```ruby
Asaas::Split.paid
Asaas::Split.received
Asaas::Split.retrieve_paid("spl_123")
Asaas::Split.retrieve_received("spl_123")
```

### Checkouts

```ruby
Asaas::Checkout.create(billingType: "UNDEFINED", totalValue: 150.0)
Asaas::Checkout.retrieve("chk_123")
Asaas::Checkout.delete("chk_123")  # cancel
```

### Dunning

```ruby
Asaas::Dunning.create(payment: "pay_123", type: "CREDIT_BUREAU")
Asaas::Dunning.retrieve("dun_123")
Asaas::Dunning.list
Asaas::Dunning.delete("dun_123")  # cancel
Asaas::Dunning.resend_documents("dun_123")
```

### Chargebacks

```ruby
Asaas::Chargeback.list
Asaas::Chargeback.retrieve("cbk_123")
Asaas::Chargeback.dispute("cbk_123", description: "Item entregue conforme pedido")
```

### Subaccounts

```ruby
Asaas::Subaccount.create(name: "Loja Parceira", email: "loja@example.com", cpfCnpj: "000.000.000-00")
Asaas::Subaccount.retrieve("sub_123")
Asaas::Subaccount.list
Asaas::Subaccount.create_api_key("sub_123")
Asaas::Subaccount.api_keys("sub_123")
```

### Account Status

Authoritative KYC registration status for the authenticated account. Acts on
`/myAccount`, so pass the subaccount's own key per call:

```ruby
status = Asaas::MyAccount.status(api_key: "aact_subaccount_key")
status.commercialInfo   # => "APPROVED"
status.documentation    # => "AWAITING_APPROVAL"
status.bankAccountInfo  # => "PENDING"
status.general          # => "PENDING"
```

### Documents (KYC)

KYC documents for the authenticated account (`/myAccount/documents`). Pass the
subaccount's own key per call:

```ruby
# List pending document groups (each with its onboardingUrl and sent files)
groups = Asaas::Document.pending(api_key: "aact_subaccount_key")
group  = groups.data.first
group.onboardingUrl

# Upload a file to a group (multipart). `file` is any IO that responds to #read.
Asaas::Document.send_document(
  group.id,
  file: File.open("identity.png"),
  type: "IDENTIFICATION",
  api_key: "aact_subaccount_key"
)

# Remove a previously sent file
Asaas::Document.delete_file("file_123", api_key: "aact_subaccount_key")
```

> Asaas recommends waiting ~15s after subaccount creation before listing
> documents, so Receita Federal validation can finish.

### Bill Payments

```ruby
Asaas::BillPayment.create(identificationField: "123456789", value: 150.0)
Asaas::BillPayment.retrieve("bil_123")
Asaas::BillPayment.list
Asaas::BillPayment.delete("bil_123")  # cancel
```

### Pix Automatic

```ruby
Asaas::PixAutomatic.create(customer: "cus_123", value: 99.90)
Asaas::PixAutomatic.list
Asaas::PixAutomatic.delete("aut_123")  # cancel
```

## Pagination

List endpoints return a `ListObject`. You can iterate the current page or all pages automatically:

```ruby
# Current page only
payments = Asaas::Payment.list(limit: 10)
payments.each { |p| puts p.status }
payments.total_count  # => 312
payments.has_more     # => true

# All pages — fetches next automatically
Asaas::Payment.list.auto_paging_each do |payment|
  puts payment.id
end

# As an Enumerator (lazy)
Asaas::Payment.list.auto_paging_each.lazy.first(50)
```

## Error Handling

```ruby
begin
  Asaas::Customer.retrieve("invalid_id")
rescue Asaas::NotFoundError => e
  puts e.message
  puts e.http_status   # => 404
  puts e.request_id
rescue Asaas::AuthenticationError
  puts "Invalid API key"
rescue Asaas::RateLimitError
  puts "Too many requests"
rescue Asaas::AsaasError => e
  puts "Unexpected error: #{e.message}"
end
```

| Exception | HTTP Status |
|---|---|
| `AuthenticationError` | 401 |
| `PermissionError` | 403 |
| `NotFoundError` | 404 |
| `RateLimitError` | 429 |
| `ServerError` | 5xx |
| `ConnectionError` | network failure |

## Development

```bash
bundle install
bundle exec rspec       # run tests
bundle exec rubocop     # lint
bundle exec rake        # tests + lint
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
