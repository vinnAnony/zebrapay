# ZebraPay 🦓

> Unified payment gateway library for Elixir — built for Kenya, ready for Africa.

[![Hex.pm](https://img.shields.io/hexpm/v/zebrapay.svg)](https://hex.pm/packages/zebrapay)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

ZebraPay provides a **single, consistent API** for integrating multiple payment gateways. Write your payment logic once and switch or add gateways with a one-line config change.

---

## Supported Gateways

### Phase 1 — Kenya 🇰🇪 (in progress)

| Gateway                 | Type           | STK Push | C2B | B2C | B2B | Transaction Status | Reversal | Balance | Cards | Status         |
| ----------------------- | -------------- | -------- | --- | --- | --- | ------------------ | -------- | ------- | ----- | -------------- |
| **M-Pesa (Daraja 3.0)** | Mobile Money   | ✅       | ✅  | ✅  | ✅  | ✅                 | ✅       | ✅      | ❌    | ✅ Stable      |
| KCB Buni                | Bank + Mobile  | —        | —   | —   | —   | —                  | —        | —       | —     | 🚧 Coming soon |
| Equity JengaAPI         | Bank + Cards   | —        | —   | —   | —   | —                  | —        | —       | —     | 🚧 Coming soon |
| Paystack                | Cards + Mobile | —        | —   | —   | —   | —                  | —        | —       | —     | 🚧 Coming soon |
| Airtel Money            | Mobile Money   | —        | —   | —   | —   | —                  | —        | —       | —     | 🚧 Coming soon |
| Pesapal                 | Multi-channel  | —        | —   | —   | —   | —                  | —        | —       | —     | 🚧 Coming soon |

M-Pesa is being built out fully first. The other Kenyan gateways will be re-added one at a time once M-Pesa is solid.

### Phase 2 — Pan-African & Global 🌍

| Gateway               | Coverage                 | Status     |
| --------------------- | ------------------------ | ---------- |
| **Flutterwave**       | 50+ African countries    | 🚧 Planned |
| **Stripe**            | Global (135+ currencies) | 🚧 Planned |
| **MTN MoMo**          | Uganda, Ghana, Rwanda    | 🚧 Planned |
| **Cellulant (Tingg)** | 18 African countries     | 🚧 Planned |

---

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:zebrapay, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :zebrapay,
  sandbox: true,           # false in production
  default_gateway: :mpesa

# M-Pesa (Safaricom Daraja)
config :zebrapay, :mpesa,
  base_url: [
    sandbox:    "https://sandbox.safaricom.co.ke",
    production: "https://api.safaricom.co.ke"
  ],
  consumer_key:       System.get_env("MPESA_CONSUMER_KEY"),
  consumer_secret:    System.get_env("MPESA_CONSUMER_SECRET"),
  shortcode:          System.get_env("MPESA_SHORTCODE"),
  passkey:            System.get_env("MPESA_PASSKEY"),
  callback_url:       System.get_env("MPESA_CALLBACK_URL"),
  # Each async operation (B2C, B2B, Transaction Status, Reversal, Account
  # Balance) has its own result/timeout URL pair, so you can route each
  # one to a distinct handler
  b2c_result_url:                     System.get_env("MPESA_B2C_RESULT_URL"),
  b2c_timeout_url:                    System.get_env("MPESA_B2C_TIMEOUT_URL"),
  b2b_result_url:                     System.get_env("MPESA_B2B_RESULT_URL"),
  b2b_timeout_url:                    System.get_env("MPESA_B2B_TIMEOUT_URL"),
  transaction_status_result_url:      System.get_env("MPESA_TRANSACTION_STATUS_RESULT_URL"),
  transaction_status_timeout_url:     System.get_env("MPESA_TRANSACTION_STATUS_TIMEOUT_URL"),
  reversal_result_url:                System.get_env("MPESA_REVERSAL_RESULT_URL"),
  reversal_timeout_url:               System.get_env("MPESA_REVERSAL_TIMEOUT_URL"),
  account_balance_result_url:         System.get_env("MPESA_ACCOUNT_BALANCE_RESULT_URL"),
  account_balance_timeout_url:        System.get_env("MPESA_ACCOUNT_BALANCE_TIMEOUT_URL"),
  # C2B (see register_c2b_urls/1) — ValidationURL is only called if
  # Safaricom has enabled validation for your shortcode
  c2b_validation_url:   System.get_env("MPESA_C2B_VALIDATION_URL"),
  c2b_confirmation_url: System.get_env("MPESA_C2B_CONFIRMATION_URL"),
  initiator_name:     System.get_env("MPESA_INITIATOR_NAME"),
  initiator_password: System.get_env("MPESA_INITIATOR_PASSWORD"),
  # sandbox_cert_path is optional — defaults to this library's bundled
  # sandbox cert. production_cert_path is required in production; point
  # it at a cert file that lives in YOUR app (never bundled here, since
  # Safaricom issues it per-shortcode at go-live)
  sandbox_cert_path:    System.get_env("MPESA_SANDBOX_CERT_PATH"),
  production_cert_path: System.get_env("MPESA_PRODUCTION_CERT_PATH")
```

`sandbox: true/false` picks which of `base_url`'s two URLs the gateway
uses — there's no hardcoded fallback, so `base_url` must be set for
each gateway you configure. It also picks which cert path is used for
`SecurityCredential` encryption — see `priv/certs/README.md` for how
to get and place the sandbox and production certs.

---

## Usage

### STK Push (C2B)

```elixir
{:ok, resp} = ZebraPay.initiate_payment(:mpesa, %{
  phone: "254712345678",
  amount: 100,
  reference: "ORDER-001",
  description: "Payment for Order #1"
})

# resp.status         => :pending
# resp.transaction_id => "ws_CO_010320202011179845"
# resp.message        => "Success. Request accepted for processing"
```

### Query STK Push Status

```elixir
{:ok, resp} = ZebraPay.query_status(:mpesa, "ws_CO_010320202011179845")
# resp.status => :success | :failed
```

### B2C Payout

```elixir
{:ok, resp} = ZebraPay.payout(:mpesa, %{
  phone: "254712345678",
  amount: 500,
  remarks: "Refund for order #001",
  occasion: "Refund"
})
```

### B2B Payment

Pay another business's paybill/till directly from your shortcode. Call
this directly on the M-Pesa gateway module since it's Daraja-specific
(not part of the generic `ZebraPay` cross-gateway API):

```elixir
{:ok, resp} = ZebraPay.Gateways.Mpesa.business_payment(%{
  amount: 1000,
  party_b: "600001",             # recipient shortcode/till
  account_reference: "INV-001",
  command_id: "BusinessPayBill", # or "BusinessBuyGoods", etc.
  remarks: "Supplier payment"
})
```

### Transaction Status

Query the status of _any_ M-Pesa transaction by its receipt number
(unlike `query_status/2`, which is specific to STK Push):

```elixir
{:ok, resp} = ZebraPay.Gateways.Mpesa.transaction_status(%{
  transaction_id: "OEI2AK4Q16"
})
```

### Reversal

```elixir
{:ok, resp} = ZebraPay.Gateways.Mpesa.reverse(%{
  transaction_id: "OEI2AK4Q16",
  amount: 100,
  remarks: "Wrong recipient"
})
```

### Account Balance

```elixir
{:ok, resp} = ZebraPay.Gateways.Mpesa.account_balance()
```

All of B2C, B2B, Transaction Status, Reversal, and Account Balance are
async: the initial response only confirms M-Pesa _accepted_ the request
(`status: :pending`); the actual result arrives later on that
operation's own `*_result_url` webhook (`b2c_result_url`,
`b2b_result_url`, `transaction_status_result_url`,
`reversal_result_url`, `account_balance_result_url`). For Account
Balance, `verify_webhook/2` parses the pipe-delimited balance string
into a list of `%{account:, currency:, balance:, available_balance:,
reserved_balance:, uncleared_balance:}` maps under
`event.metadata["AccountBalance"]`.

### C2B (Customer to Business)

Register your Validation and Confirmation URLs with Safaricom once —
not per transaction:

```elixir
{:ok, resp} = ZebraPay.Gateways.Mpesa.register_c2b_urls()
```

Confirmation (money has already moved — just acknowledge it) goes
through `ZebraPay.WebhookPlug` like every other callback. Validation
(Safaricom asks you to accept/reject _before_ completing the payment)
needs a real-time decision, so it's handled with a dedicated function
in your own controller instead — see [Webhook Handling](#webhook-handling-phoenix)
below.

---

## Webhook Handling (Phoenix)

```elixir
# router.ex
scope "/webhooks" do
  pipe_through :webhook_pipeline

  post "/mpesa", ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.MpesaHandler
end
```

```elixir
# lib/my_app/mpesa_handler.ex
defmodule MyApp.MpesaHandler do
  @behaviour ZebraPay.WebhookHandler

  def handle_event(%{status: :success, transaction_id: txn_id, amount: amount}) do
    MyApp.Orders.mark_paid(txn_id, amount)
    :ok
  end

  def handle_event(%{status: :failed, transaction_id: txn_id}) do
    MyApp.Orders.mark_payment_failed(txn_id)
    :ok
  end

  def handle_event(_event), do: :ok
end
```

`ZebraPay.Gateways.Mpesa.verify_webhook/2` handles all four M-Pesa
callback shapes: the STK Push callback, the shared "Result" callback
used by B2C, B2B, Transaction Status, Reversal, and Account Balance,
and the flat C2B Confirmation payload.

Since each operation has its own `*_result_url` config, you can also
route each to its own Phoenix path and handler instead of a single
shared one — useful since the "Result" callback shape doesn't itself
say which operation it's for:

```elixir
# router.ex
scope "/webhooks/mpesa" do
  pipe_through :webhook_pipeline

  post "/stk",                ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.StkHandler
  post "/b2c",                 ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.B2cHandler
  post "/b2b",                  ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.B2bHandler
  post "/transaction_status",   ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.TransactionStatusHandler
  post "/reversal",             ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.ReversalHandler
  post "/account_balance",      ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.AccountBalanceHandler
  post "/c2b/confirmation",     ZebraPay.WebhookPlug, gateway: :mpesa, handler: MyApp.Mpesa.C2bConfirmationHandler

  # Validation is NOT routed through ZebraPay.WebhookPlug — see below
  post "/c2b/validation", MyApp.MpesaValidationController, :validate
end
```

...then point `callback_url`, `b2c_result_url`, `b2b_result_url`,
`transaction_status_result_url`, `reversal_result_url`,
`account_balance_result_url`, and `c2b_confirmation_url` at the
matching path.

#### C2B Validation

Safaricom calls your `c2b_validation_url` **synchronously, before**
completing a C2B payment, and waits for a decision — this is the one
M-Pesa callback that isn't a fire-and-forget notification, so it isn't
routed through `ZebraPay.WebhookPlug`. Write your own small controller
action instead and build the reply with `validation_response/1`:

```elixir
# lib/my_app_web/controllers/mpesa_validation_controller.ex
defmodule MyAppWeb.MpesaValidationController do
  use MyAppWeb, :controller
  alias ZebraPay.Gateways.Mpesa

  def validate(conn, params) do
    decision =
      if MyApp.Orders.valid_ref?(params["BillRefNumber"]) do
        :accept
      else
        {:reject, "Invalid account number"}
      end

    json(conn, Mpesa.validation_response(decision))
  end
end
```

(Validation only fires at all if Safaricom has enabled it for your
shortcode — most Paybill/Till numbers only get Confirmation calls.)

### Raw body preservation (required for signature verification)

```elixir
# endpoint.ex — add BEFORE Plug.Parsers
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {ZebraPay.WebhookPlug, :read_body, []},
  json_decoder: Jason
```

---

## Adding a New Gateway

1. Create `lib/zebrapay/gateways/my_gateway.ex`
2. `use ZebraPay.Gateway`
3. Implement the 5 callbacks: `validate/1`, `initiate_payment/1`, `query_status/1`, `payout/1`, `verify_webhook/2`
4. Register in `ZebraPay` module's `@gateways` map

```elixir
defmodule ZebraPay.Gateways.MyGateway do
  use ZebraPay.Gateway

  @impl ZebraPay.Gateway
  def validate(params), do: :ok

  @impl ZebraPay.Gateway
  def initiate_payment(params) do
    # ... call your gateway API
    {:ok, Response.pending(:my_gateway, %{transaction_id: "..."})}
  end

  @impl ZebraPay.Gateway
  def query_status(id), do: # ...

  @impl ZebraPay.Gateway
  def verify_webhook(payload, headers), do: # ...
end
```

---

## Roadmap

### v0.1 — M-Pesa first 🚧 (current)

- [x] M-Pesa Daraja 3.0 — STK Push
- [x] M-Pesa Daraja 3.0 — STK Push Query
- [x] M-Pesa Daraja 3.0 — B2C
- [x] M-Pesa Daraja 3.0 — B2B
- [x] M-Pesa Daraja 3.0 — Transaction Status
- [x] M-Pesa Daraja 3.0 — Reversal
- [x] M-Pesa Daraja 3.0 — Account Balance
- [x] M-Pesa Daraja 3.0 — C2B URL Registration + Validation/Confirmation
- [x] Unified `Response` struct
- [x] OAuth token caching
- [x] Phoenix/Plug webhook handler
- [x] Sandbox/production toggling
- [x] Wire `TokenCache` into M-Pesa's auth calls
- [x] Bypass-based integration tests for every M-Pesa endpoint

### v0.2 — Coming soon Kenyan gateways (one at a time)

- [ ] KCB Buni
- [ ] Equity JengaAPI
- [ ] Paystack
- [ ] Airtel Money Kenya
- [ ] Pesapal

### v0.3 — Hardening

- [ ] Telemetry events (`:telemetry` integration)
- [ ] Rate limiting middleware
- [ ] Retry with exponential backoff

### v0.4 — Pan-African

- [ ] Flutterwave (50+ African countries)
- [ ] MTN Mobile Money (Uganda, Ghana, Rwanda, Cameroon)
- [ ] Cellulant/Tingg (18 countries)
- [ ] Multi-currency amount handling

### v1.0 — Global

- [ ] Stripe (135+ currencies, subscriptions)
- [ ] PayPal
- [ ] Multi-language library parity (Python, Node.js, Go, Ruby)

---

## Contributing

PRs welcome! Please:

1. Add tests for any new gateway
2. Run `mix credo --strict`
3. Update the gateway table in this README

## License

MIT © 2025 ZebraPay Contributors
