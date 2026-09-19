defmodule ZebraPay.Gateways.Mpesa do
  @moduledoc """
  M-Pesa (Safaricom Daraja 3.0) gateway for ZebraPay.

  This is currently the only gateway implemented in ZebraPay. Other
  gateways (KCB Buni, Equity JengaAPI, Paystack, Airtel Money, Pesapal)
  will be re-added one at a time in later phases.

  Supports the major Daraja endpoints:

  - STK Push (Lipa na M-Pesa Online) — C2B — `initiate_payment/1`
  - STK Push Query — `query_status/1`
  - B2C (Business to Customer payouts) — `payout/1`
  - B2B (Business to Business payments) — `business_payment/1`
  - Transaction Status (query any transaction, not just STK) — `transaction_status/1`
  - Transaction Reversal — `reverse/1`
  - Account Balance — `account_balance/1`
  - C2B URL Registration — `register_c2b_urls/1`
  - C2B Validation response building — `validation_response/1`

  ## Configuration

      config :zebrapay, :mpesa,
        base_url: [
          sandbox: "https://sandbox.safaricom.co.ke",
          production: "https://api.safaricom.co.ke"
        ],
        consumer_key: "...",
        consumer_secret: "...",
        shortcode: "174379",          # Paybill or Till
        passkey: "...",               # From Daraja dashboard
        initiator_name: "testapi",    # For B2C / B2B / Transaction Status / Reversal / Balance
        initiator_password: "...",    # For B2C / B2B / Transaction Status / Reversal / Balance
        callback_url: "https://myapp.com/callbacks/mpesa",
        b2c_result_url: "https://myapp.com/callbacks/mpesa/b2c/result",
        b2c_timeout_url: "https://myapp.com/callbacks/mpesa/b2c/timeout",
        b2b_result_url: "https://myapp.com/callbacks/mpesa/b2b/result",
        b2b_timeout_url: "https://myapp.com/callbacks/mpesa/b2b/timeout",
        transaction_status_result_url: "https://myapp.com/callbacks/mpesa/transaction_status/result",
        transaction_status_timeout_url: "https://myapp.com/callbacks/mpesa/transaction_status/timeout",
        reversal_result_url: "https://myapp.com/callbacks/mpesa/reversal/result",
        reversal_timeout_url: "https://myapp.com/callbacks/mpesa/reversal/timeout",
        account_balance_result_url: "https://myapp.com/callbacks/mpesa/account_balance/result",
        account_balance_timeout_url: "https://myapp.com/callbacks/mpesa/account_balance/timeout",
        # C2B (see register_c2b_urls/1) — ValidationURL is only called if
        # Safaricom has enabled validation for your shortcode
        c2b_validation_url: "https://myapp.com/callbacks/mpesa/c2b/validation",
        c2b_confirmation_url: "https://myapp.com/callbacks/mpesa/c2b/confirmation",
        # Optional — defaults to this library's bundled sandbox cert
        sandbox_cert_path: "priv/certs/mpesa_sandbox.cer",
        # Required in production — Safaricom issues this per-shortcode at
        # go-live, so point it at a cert that lives in YOUR app, not this one
        production_cert_path: "priv/certs/mpesa_prod.cer"

  Each async operation (B2C, B2B, Transaction Status, Reversal, Account
  Balance) has its own `ResultURL`/`QueueTimeOutURL` config pair, so you
  can route each one to a distinct handler instead of having to inspect
  the callback payload to figure out which operation it belongs to.

  `sandbox_cert_path` / `production_cert_path` are Safaricom's public
  certificates, used to RSA-encrypt the `SecurityCredential` these same
  async operations (Safaricom calls them "Organization" security APIs)
  all require — see `ZebraPay.Utils.Crypto.rsa_encrypt/2`.

  ## Sandbox vs Production

  Set `config :zebrapay, sandbox: true` globally, and this gateway picks
  `sandbox` or `production` out of its own `:base_url` config accordingly
  (see above). Both must be present in config — there's no hardcoded
  fallback, so a missing `:base_url` config surfaces as a clear
  `{:error, %ZebraPay.Response{}}` instead of a confusing network error.

  ## Examples

      # STK Push
      {:ok, resp} = ZebraPay.Gateways.Mpesa.initiate_payment(%{
        phone: "254712345678",
        amount: 100,
        reference: "ORDER-001",
        description: "Payment for Order #1"
      })

      # Query STK status
      {:ok, resp} = ZebraPay.Gateways.Mpesa.query_status("ws_CO_010320202011179845")

      # B2C payout
      {:ok, resp} = ZebraPay.Gateways.Mpesa.payout(%{
        phone: "254712345678",
        amount: 500,
        occasion: "Refund",
        remarks: "Order refund"
      })

      # B2B payment
      {:ok, resp} = ZebraPay.Gateways.Mpesa.business_payment(%{
        amount: 1000,
        party_b: "600001",
        account_reference: "INV-001",
        remarks: "Supplier payment"
      })

      # Transaction status (any M-Pesa transaction, by receipt number)
      {:ok, resp} = ZebraPay.Gateways.Mpesa.transaction_status(%{
        transaction_id: "OEI2AK4Q16"
      })

      # Reversal
      {:ok, resp} = ZebraPay.Gateways.Mpesa.reverse(%{
        transaction_id: "OEI2AK4Q16",
        amount: 100,
        remarks: "Wrong recipient"
      })

      # Account balance
      {:ok, resp} = ZebraPay.Gateways.Mpesa.account_balance()

      # Register C2B Validation/Confirmation URLs (one-time setup)
      {:ok, resp} = ZebraPay.Gateways.Mpesa.register_c2b_urls()
  """

  use ZebraPay.Gateway

  alias ZebraPay.{Response, TokenCache, Utils}

  # Party identifier types, per Daraja docs
  @identifier_shortcode "4"
  @identifier_org_shortcode "11"

  # ── Callbacks ─────────────────────────────────────────────────────────────

  @impl ZebraPay.Gateway
  def validate(params) do
    required = [:phone, :amount, :reference, :description]
    missing = Enum.reject(required, &Map.has_key?(params, &1))

    if missing == [] do
      :ok
    else
      {:error, Response.error(:mpesa, "Missing required params: #{inspect(missing)}")}
    end
  end

  @impl ZebraPay.Gateway
  def initiate_payment(params) do
    with {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, body} <- build_stk_push_body(params),
         url = "#{base}/mpesa/stkpush/v1/processrequest",
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_stk_push_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  @impl ZebraPay.Gateway
  def query_status(checkout_request_id) do
    with {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, timestamp, password} <- generate_password(),
         url = "#{base}/mpesa/stkpushquery/v1/query",
         body = %{
           "BusinessShortCode" => shortcode(),
           "Password" => password,
           "Timestamp" => timestamp,
           "CheckoutRequestID" => checkout_request_id
         },
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_query_response(raw, checkout_request_id)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}
    end
  end

  @impl ZebraPay.Gateway
  def payout(params) do
    %{phone: phone, amount: amount} = params
    remarks = Map.get(params, :remarks, "ZebraPay payout")
    occasion = Map.get(params, :occasion, "")
    command_id = Map.get(params, :command_id, "BusinessPayment")

    with {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, security_credential} <- generate_security_credential(),
         url = "#{base}/mpesa/b2c/v3/paymentrequest",
         body = %{
           "InitiatorName" => config(:initiator_name),
           "SecurityCredential" => security_credential,
           "CommandID" => command_id,
           "Amount" => amount,
           "PartyA" => shortcode(),
           "PartyB" => Utils.Phone.format_ke(phone),
           "Remarks" => remarks,
           "QueueTimeOutURL" => config(:b2c_timeout_url),
           "ResultURL" => config(:b2c_result_url),
           "Occasion" => occasion
         },
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}
    end
  end

  @impl ZebraPay.Gateway
  def verify_webhook(payload, _headers) do
    # M-Pesa doesn't sign webhooks — validate structure instead
    cond do
      Map.has_key?(payload, "Body") ->
        {:ok, parse_callback(payload)}

      Map.has_key?(payload, "stkCallback") ->
        {:ok, parse_stk_callback(payload["stkCallback"])}

      Map.has_key?(payload, "Result") ->
        {:ok, parse_result_callback(payload["Result"])}

      Map.has_key?(payload, "TransactionType") ->
        {:ok, parse_c2b_payload(payload)}

      true ->
        {:error, "Unknown M-Pesa webhook payload structure"}
    end
  end

  # ── B2B ───────────────────────────────────────────────────────────────────

  @doc """
  Business-to-Business payment (e.g. paying a supplier's paybill/till
  from your own shortcode).

  ## Params

  - `:amount` (required)
  - `:party_b` — recipient shortcode/till (required)
  - `:account_reference` (required)
  - `:party_a` — your shortcode, defaults to configured `shortcode`
  - `:command_id` — defaults to `"BusinessPayBill"` (also accepts
    `"BusinessBuyGoods"`, `"DisburseFundsToBusiness"`, etc.)
  - `:sender_identifier_type` / `:receiver_identifier_type` — default to
    organization shortcode (`"4"`)
  - `:remarks`
  """
  @spec business_payment(map()) :: ZebraPay.Gateway.result()
  def business_payment(params) do
    with :ok <- validate_b2b(params),
         {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, security_credential} <- generate_security_credential(),
         url = "#{base}/mpesa/b2b/v1/paymentrequest",
         body = build_b2b_body(params, security_credential),
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  defp validate_b2b(params) do
    required = [:amount, :party_b, :account_reference]
    missing = Enum.reject(required, &Map.has_key?(params, &1))

    if missing == [] do
      :ok
    else
      {:error, Response.error(:mpesa, "Missing required params: #{inspect(missing)}")}
    end
  end

  defp build_b2b_body(params, security_credential) do
    %{
      "Initiator" => config(:initiator_name),
      "SecurityCredential" => security_credential,
      "CommandID" => Map.get(params, :command_id, "BusinessPayBill"),
      "SenderIdentifierType" => Map.get(params, :sender_identifier_type, @identifier_shortcode),
      "RecieverIdentifierType" =>
        Map.get(params, :receiver_identifier_type, @identifier_shortcode),
      "Amount" => params.amount,
      "PartyA" => Map.get(params, :party_a, shortcode()),
      "PartyB" => params.party_b,
      "AccountReference" => params.account_reference,
      "Remarks" => Map.get(params, :remarks, "ZebraPay B2B payment"),
      "QueueTimeOutURL" => config(:b2b_timeout_url),
      "ResultURL" => config(:b2b_result_url)
    }
  end

  # ── Transaction Status ───────────────────────────────────────────────────

  @doc """
  Queries the status of any M-Pesa transaction by its receipt number
  (unlike `query_status/1`, which is specific to STK Push).

  ## Params

  - `:transaction_id` — the M-Pesa receipt number, e.g. `"OEI2AK4Q16"` (required)
  - `:party_a` — defaults to configured `shortcode`
  - `:identifier_type` — defaults to organization shortcode (`"4"`)
  - `:remarks`, `:occasion`
  """
  @spec transaction_status(map()) :: ZebraPay.Gateway.result()
  def transaction_status(params) do
    with :ok <- validate_transaction_id(params),
         {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, security_credential} <- generate_security_credential(),
         url = "#{base}/mpesa/transactionstatus/v1/query",
         body = build_transaction_status_body(params, security_credential),
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  defp build_transaction_status_body(params, security_credential) do
    %{
      "Initiator" => config(:initiator_name),
      "SecurityCredential" => security_credential,
      "CommandID" => "TransactionStatusQuery",
      "TransactionID" => params.transaction_id,
      "PartyA" => Map.get(params, :party_a, shortcode()),
      "IdentifierType" => Map.get(params, :identifier_type, @identifier_shortcode),
      "ResultURL" => config(:transaction_status_result_url),
      "QueueTimeOutURL" => config(:transaction_status_timeout_url),
      "Remarks" => Map.get(params, :remarks, "ZebraPay transaction status query"),
      "Occasion" => Map.get(params, :occasion, "")
    }
  end

  # ── Reversal ──────────────────────────────────────────────────────────────

  @doc """
  Reverses a completed M-Pesa transaction.

  ## Params

  - `:transaction_id` — the M-Pesa receipt number to reverse (required)
  - `:amount` (required)
  - `:receiver_party` — defaults to configured `shortcode`
  - `:remarks`, `:occasion`
  """
  @spec reverse(map()) :: ZebraPay.Gateway.result()
  def reverse(params) do
    with :ok <- validate_reversal(params),
         {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, security_credential} <- generate_security_credential(),
         url = "#{base}/mpesa/reversal/v1/request",
         body = build_reversal_body(params, security_credential),
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  defp validate_reversal(params) do
    required = [:transaction_id, :amount]
    missing = Enum.reject(required, &Map.has_key?(params, &1))

    if missing == [] do
      :ok
    else
      {:error, Response.error(:mpesa, "Missing required params: #{inspect(missing)}")}
    end
  end

  defp build_reversal_body(params, security_credential) do
    %{
      "Initiator" => config(:initiator_name),
      "SecurityCredential" => security_credential,
      "CommandID" => "TransactionReversal",
      "TransactionID" => params.transaction_id,
      "Amount" => params.amount,
      "ReceiverParty" => Map.get(params, :receiver_party, shortcode()),
      "RecieverIdentifierType" => @identifier_org_shortcode,
      "ResultURL" => config(:reversal_result_url),
      "QueueTimeOutURL" => config(:reversal_timeout_url),
      "Remarks" => Map.get(params, :remarks, "ZebraPay reversal"),
      "Occasion" => Map.get(params, :occasion, "")
    }
  end

  defp validate_transaction_id(%{transaction_id: id}) when is_binary(id) and id != "", do: :ok

  defp validate_transaction_id(_),
    do: {:error, Response.error(:mpesa, "Missing required param: :transaction_id")}

  # ── Account Balance ──────────────────────────────────────────────────────

  @doc """
  Queries the account balance for your M-Pesa shortcode.

  ## Params (all optional)

  - `:party_a` — defaults to configured `shortcode`
  - `:identifier_type` — defaults to organization shortcode (`"4"`)
  - `:remarks`

  The actual balance is delivered asynchronously to
  `account_balance_result_url` — `verify_webhook/2` parses the
  pipe-delimited `AccountBalance` result
  parameter into a list of `%{account:, currency:, balance:,
  available_balance:, reserved_balance:, uncleared_balance:}` maps under
  `event.metadata["AccountBalance"]`.
  """
  @spec account_balance(map()) :: ZebraPay.Gateway.result()
  def account_balance(params \\ %{}) do
    with {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         {:ok, security_credential} <- generate_security_credential(),
         url = "#{base}/mpesa/accountbalance/v1/query",
         body = build_account_balance_body(params, security_credential),
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  defp build_account_balance_body(params, security_credential) do
    %{
      "Initiator" => config(:initiator_name),
      "SecurityCredential" => security_credential,
      "CommandID" => "AccountBalance",
      "PartyA" => Map.get(params, :party_a, shortcode()),
      "IdentifierType" => Map.get(params, :identifier_type, @identifier_shortcode),
      "Remarks" => Map.get(params, :remarks, "ZebraPay account balance query"),
      "QueueTimeOutURL" => config(:account_balance_timeout_url),
      "ResultURL" => config(:account_balance_result_url)
    }
  end

  # ── C2B (Customer to Business) ──────────────────────────────────────────────

  @doc """
  Registers your Validation and Confirmation URLs with Safaricom for
  C2B (PayBill/Till) payments on this shortcode.

  Unlike B2C/B2B/Transaction Status/Reversal/Account Balance, this does
  **not** need a `SecurityCredential` — just an OAuth token, your
  shortcode, and the two URLs.

  Call this once (e.g. a deploy step or a `mix` task), not per
  transaction — it overwrites whatever URLs were previously registered
  for this shortcode. Requires Safaricom to have enabled C2B on your
  shortcode first.

  ## Params (all optional — default to configured values)

  - `:validation_url` — defaults to configured `c2b_validation_url`
  - `:confirmation_url` — defaults to configured `c2b_confirmation_url`
  - `:response_type` — `"Completed"` (default) or `"Cancelled"`; what
    Safaricom does with the payment if your `ValidationURL` times out
    or is unreachable
  - `:shortcode` — defaults to configured `shortcode`
  """
  @spec register_c2b_urls(map()) :: ZebraPay.Gateway.result()
  def register_c2b_urls(params \\ %{}) do
    with :ok <- validate_c2b_urls(params),
         {:ok, base} <- base_url(),
         {:ok, token} <- get_access_token(base),
         url = "#{base}/mpesa/c2b/v2/registerurl",
         body = build_c2b_register_body(params),
         {:ok, raw} <- HTTP.post(url, body, headers: auth_headers(token)) do
      parse_org_response(raw, params)
    else
      {:error, reason} when is_binary(reason) ->
        {:error, Response.error(:mpesa, reason)}

      {:error, %Response{} = resp} ->
        {:error, resp}
    end
  end

  defp validate_c2b_urls(params) do
    validation_url = Map.get(params, :validation_url, config(:c2b_validation_url))
    confirmation_url = Map.get(params, :confirmation_url, config(:c2b_confirmation_url))

    cond do
      blank?(validation_url) ->
        {:error,
         Response.error(:mpesa, "Missing :c2b_validation_url config (or :validation_url param)")}

      blank?(confirmation_url) ->
        {:error,
         Response.error(
           :mpesa,
           "Missing :c2b_confirmation_url config (or :confirmation_url param)"
         )}

      true ->
        :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp build_c2b_register_body(params) do
    %{
      "ShortCode" => Map.get(params, :shortcode, shortcode()),
      "ResponseType" => Map.get(params, :response_type, "Completed"),
      "ConfirmationURL" => Map.get(params, :confirmation_url, config(:c2b_confirmation_url)),
      "ValidationURL" => Map.get(params, :validation_url, config(:c2b_validation_url))
    }
  end

  @doc """
  Builds the JSON-ready response body M-Pesa's C2B **Validation** URL
  expects — render it directly from your own controller action for
  that route (this is intentionally not handled by `ZebraPay.WebhookPlug`,
  since Validation needs a real-time accept/reject decision reflected in
  the HTTP response, unlike every other M-Pesa callback which is a
  fire-and-forget notification).

  ## Examples

      # Accept the payment
      Mpesa.validation_response(:accept)
      #=> %{"ResultCode" => 0, "ResultDesc" => "Accepted"}

      # Reject with the generic "Other Error" code
      Mpesa.validation_response({:reject, "Unknown account number"})
      #=> %{"ResultCode" => "C2B00016", "ResultDesc" => "Unknown account number"}

      # Reject with a specific Safaricom C2B error code
      Mpesa.validation_response({:reject, "C2B00012", "Invalid account number"})
      #=> %{"ResultCode" => "C2B00012", "ResultDesc" => "Invalid account number"}

  ## Usage (Phoenix)

      def validate(conn, params) do
        decision =
          if MyApp.Orders.valid_ref?(params["BillRefNumber"]) do
            :accept
          else
            {:reject, "Invalid account number"}
          end

        json(conn, Mpesa.validation_response(decision))
      end
  """
  @spec validation_response(:accept | {:reject, String.t()} | {:reject, String.t(), String.t()}) ::
          map()
  def validation_response(:accept), do: %{"ResultCode" => 0, "ResultDesc" => "Accepted"}

  def validation_response({:reject, reason}) when is_binary(reason),
    do: %{"ResultCode" => "C2B00016", "ResultDesc" => reason}

  def validation_response({:reject, code, reason})
      when is_binary(code) and is_binary(reason),
      do: %{"ResultCode" => code, "ResultDesc" => reason}

  # ── Private helpers ────────────────────────────────────────────────────────

  defp get_access_token(base) do
    case TokenCache.get(gateway_name()) do
      {:ok, token} -> {:ok, token}
      :miss -> fetch_access_token(base)
    end
  end

  defp fetch_access_token(base) do
    url = "#{base}/oauth/v1/generate?grant_type=client_credentials"
    key = config(:consumer_key)
    secret = config(:consumer_secret)
    credentials = Base.encode64("#{key}:#{secret}")

    case HTTP.get(url, headers: [{"Authorization", "Basic #{credentials}"}]) do
      {:ok, %{"access_token" => token} = body} ->
        TokenCache.put(gateway_name(), token, expires_in: token_expires_in(body))
        {:ok, token}

      {:ok, body} ->
        {:error, "Token error: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Daraja returns "expires_in" as a numeric string, e.g. "3599"
  defp token_expires_in(%{"expires_in" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> 3600
    end
  end

  defp token_expires_in(%{"expires_in" => value}) when is_integer(value), do: value
  defp token_expires_in(_body), do: 3600

  defp build_stk_push_body(params) do
    with {:ok, timestamp, password} <- generate_password() do
      body = %{
        "BusinessShortCode" => shortcode(),
        "Password" => password,
        "Timestamp" => timestamp,
        "TransactionType" => "CustomerPayBillOnline",
        "Amount" => params.amount,
        "PartyA" => Utils.Phone.format_ke(params.phone),
        "PartyB" => shortcode(),
        "PhoneNumber" => Utils.Phone.format_ke(params.phone),
        "CallBackURL" => Map.get(params, :callback_url, config(:callback_url)),
        "AccountReference" => params.reference,
        "TransactionDesc" => params.description
      }

      {:ok, body}
    end
  end

  defp generate_password do
    passkey = config(:passkey)
    timestamp = Utils.Crypto.mpesa_timestamp()
    raw = "#{shortcode()}#{passkey}#{timestamp}"
    password = Base.encode64(raw)
    {:ok, timestamp, password}
  end

  defp generate_security_credential do
    # Encrypt initiator password with Safaricom's public cert
    password = config(:initiator_password)

    with {:ok, cert_path} <- cert_path() do
      Utils.Crypto.rsa_encrypt(password, cert_path)
    end
  end

  # Sandbox cert defaults to the one bundled with this library (Safaricom's
  # sandbox cert is public and identical for every developer). Production
  # has no default — it's issued per-shortcode by Safaricom at go-live, so
  # each host app must configure its own `production_cert_path`.
  defp cert_path do
    if Config.sandbox?() do
      path =
        config(:sandbox_cert_path, Application.app_dir(:zebrapay, "priv/certs/mpesa_sandbox.cer"))

      {:ok, Path.expand(path)}
    else
      case config(:production_cert_path) do
        nil ->
          {:error,
           "Missing :production_cert_path config for :mpesa. Set it to the path of " <>
             "Safaricom's production public certificate, issued to your shortcode " <>
             "during Daraja go-live."}

        path ->
          {:ok, Path.expand(path)}
      end
    end
  end

  defp parse_stk_push_response(%{"ResponseCode" => "0"} = raw, params) do
    resp =
      Response.pending(:mpesa, %{
        transaction_id: raw["CheckoutRequestID"],
        reference: params.reference,
        amount: params.amount,
        phone: params.phone,
        message: raw["CustomerMessage"],
        raw: raw,
        metadata: %{
          merchant_request_id: raw["MerchantRequestID"]
        }
      })

    {:ok, resp}
  end

  defp parse_stk_push_response(raw, _params) do
    {:error,
     Response.error(
       :mpesa,
       raw["errorMessage"] || raw["ResponseDescription"] || "STK push failed"
     )}
  end

  defp parse_query_response(%{"ResultCode" => "0"} = raw, checkout_id) do
    {:ok,
     Response.success(:mpesa, %{
       transaction_id: checkout_id,
       message: raw["ResultDesc"],
       raw: raw
     })}
  end

  defp parse_query_response(%{"ResultCode" => code} = raw, _id) when code != "0" do
    {:ok, Response.failed(:mpesa, raw["ResultDesc"] || "Payment failed", %{raw: raw})}
  end

  defp parse_query_response(raw, _id) do
    {:error, Response.error(:mpesa, "Unexpected query response: #{inspect(raw)}")}
  end

  # Shared response shape for the async "Organization" APIs: B2C, B2B,
  # Transaction Status, and Reversal all acknowledge the request the
  # same way and deliver the actual result later via ResultURL.
  defp parse_org_response(%{"ResponseCode" => "0"} = raw, params) do
    {:ok,
     Response.pending(:mpesa, %{
       transaction_id: raw["ConversationID"],
       amount: Map.get(params, :amount),
       phone: Map.get(params, :phone),
       message: raw["ResponseDescription"],
       raw: raw,
       metadata: %{
         originator_conversation_id: raw["OriginatorConversationID"]
       }
     })}
  end

  defp parse_org_response(raw, _params) do
    {:error, Response.error(:mpesa, raw["errorMessage"] || "M-Pesa request failed")}
  end

  defp parse_callback(%{"Body" => %{"stkCallback" => cb}}), do: parse_stk_callback(cb)
  defp parse_callback(payload), do: payload

  defp parse_stk_callback(%{"ResultCode" => 0} = cb) do
    items =
      get_in(cb, ["CallbackMetadata", "Item"]) || []

    meta =
      items
      |> Enum.map(fn item -> {item["Name"], item["Value"]} end)
      |> Map.new()

    %{
      status: :success,
      transaction_id: meta["MpesaReceiptNumber"],
      amount: meta["Amount"],
      phone: to_string(meta["PhoneNumber"]),
      raw: cb
    }
  end

  defp parse_stk_callback(%{"ResultCode" => code, "ResultDesc" => desc}) do
    %{status: :failed, result_code: code, message: desc}
  end

  # Result callback shape used by B2C, B2B, Transaction Status,
  # Reversal, and Account Balance — delivered asynchronously to
  # ResultURL/QueueTimeOutURL.
  defp parse_result_callback(%{"ResultCode" => 0} = result) do
    items = get_in(result, ["ResultParameters", "ResultParameter"]) || []

    meta =
      items
      |> Enum.map(fn %{"Key" => key, "Value" => value} -> {key, value} end)
      |> Map.new()

    meta =
      case Map.fetch(meta, "AccountBalance") do
        {:ok, value} -> Map.put(meta, "AccountBalance", parse_account_balance(value))
        :error -> meta
      end

    %{
      status: :success,
      transaction_id: result["TransactionID"] || meta["TransactionReceipt"],
      amount: meta["Amount"] || meta["TransactionAmount"],
      message: result["ResultDesc"],
      metadata: meta,
      raw: result
    }
  end

  defp parse_result_callback(%{"ResultCode" => code, "ResultDesc" => desc} = result) do
    %{status: :failed, result_code: code, message: desc, raw: result}
  end

  # "AccountBalance" arrives as "Name|Currency|Balance|Available|Reserved|Uncleared"
  # per account, with multiple accounts joined by "&".
  defp parse_account_balance(raw) when is_binary(raw) do
    raw
    |> String.split("&")
    |> Enum.map(fn account ->
      case String.split(account, "|") do
        [name, currency, balance, available, reserved, uncleared] ->
          %{
            account: name,
            currency: currency,
            balance: balance,
            available_balance: available,
            reserved_balance: reserved,
            uncleared_balance: uncleared
          }

        _ ->
          %{raw: account}
      end
    end)
  end

  defp parse_account_balance(other), do: other

  # C2B Validation and Confirmation payloads share this same flat shape
  # (Safaricom doesn't include a field saying which one it is — that's
  # determined by which URL the request came in on).
  defp parse_c2b_payload(payload) do
    %{
      status: :success,
      transaction_id: payload["TransID"],
      amount: payload["TransAmount"],
      phone: payload["MSISDN"],
      reference: payload["BillRefNumber"],
      raw: payload,
      metadata: %{
        "TransactionType" => payload["TransactionType"],
        "TransTime" => payload["TransTime"],
        "BusinessShortCode" => payload["BusinessShortCode"],
        "InvoiceNumber" => payload["InvoiceNumber"],
        "OrgAccountBalance" => payload["OrgAccountBalance"],
        "ThirdPartyTransID" => payload["ThirdPartyTransID"],
        "FirstName" => payload["FirstName"],
        "MiddleName" => payload["MiddleName"],
        "LastName" => payload["LastName"]
      }
    }
  end

  defp auth_headers(token), do: [{"Authorization", "Bearer #{token}"}]
  defp shortcode, do: config(:shortcode)
end
