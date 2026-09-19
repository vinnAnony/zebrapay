defmodule ZebraPay do
  @moduledoc """
  ZebraPay — Unified payment gateway library for Kenya and Africa.

  ## Supported Gateways

  | Gateway        | STK Push | B2C | B2B | Reversal | Cards | Status |
  |----------------|----------|-----|-----|----------|-------|--------|
  | M-Pesa (Daraja)| ✅       | ✅  | ✅  | ✅       | ❌    | Stable |

  Other gateways (KCB Buni, Equity JengaAPI, Paystack, Airtel Money,
  Pesapal) are being re-added one at a time in later phases — see
  `ZEBRAPAY_CONTEXT.md`.

  ## Quick Start

      # M-Pesa STK Push
      {:ok, result} = ZebraPay.initiate_payment(:mpesa, %{
        phone: "254712345678",
        amount: 100,
        reference: "ORDER-001",
        description: "Payment for order",
        callback_url: "https://myapp.com/callbacks/mpesa"
      })

  ## Configuration

  Add to your `config/config.exs`:

      config :zebrapay,
        default_gateway: :mpesa,
        sandbox: true  # set false in prod

      config :zebrapay, :mpesa,
        consumer_key: System.get_env("MPESA_CONSUMER_KEY"),
        consumer_secret: System.get_env("MPESA_CONSUMER_SECRET"),
        shortcode: System.get_env("MPESA_SHORTCODE"),
        passkey: System.get_env("MPESA_PASSKEY"),
        callback_url: System.get_env("MPESA_CALLBACK_URL")

  See `ZebraPay.Gateways.Mpesa` for full configuration options, including
  B2B, Transaction Status, and Reversal support.
  """

  alias ZebraPay.{Config, Response}
  alias ZebraPay.Gateways.Mpesa

  @type gateway :: :mpesa
  @type payment_params :: map()
  @type result :: {:ok, Response.t()} | {:error, Response.t()}

  @gateways %{
    mpesa: Mpesa
  }

  @doc """
  Initiates a payment on the specified gateway.

  ## Examples

      iex> ZebraPay.initiate_payment(:mpesa, %{phone: "254712345678", amount: 100, reference: "REF-001", description: "Test"})
      {:ok, %ZebraPay.Response{status: :pending, gateway: :mpesa, ...}}
  """
  @spec initiate_payment(gateway(), payment_params()) :: result()
  def initiate_payment(gateway, params) when is_atom(gateway) do
    with {:ok, mod} <- resolve_gateway(gateway),
         :ok <- mod.validate(params) do
      mod.initiate_payment(params)
    end
  end

  @doc """
  Queries the status of a transaction.

  ## Examples

      iex> ZebraPay.query_status(:mpesa, "ws_CO_010320202011179845")
      {:ok, %ZebraPay.Response{status: :success, ...}}
  """
  @spec query_status(gateway(), String.t()) :: result()
  def query_status(gateway, transaction_id) do
    with {:ok, mod} <- resolve_gateway(gateway) do
      mod.query_status(transaction_id)
    end
  end

  @doc """
  Initiates a B2C (business to customer) payout.
  """
  @spec payout(gateway(), payment_params()) :: result()
  def payout(gateway, params) do
    with {:ok, mod} <- resolve_gateway(gateway) do
      mod.payout(params)
    end
  end

  @doc """
  Verifies a webhook payload from the specified gateway.

  Returns `{:ok, parsed_event}` or `{:error, reason}`.
  """
  @spec verify_webhook(gateway(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def verify_webhook(gateway, payload, headers \\ %{}) do
    with {:ok, mod} <- resolve_gateway(gateway) do
      mod.verify_webhook(payload, headers)
    end
  end

  @doc """
  Lists all supported gateways.
  """
  @spec gateways() :: [gateway()]
  def gateways, do: Map.keys(@gateways)

  @doc """
  Returns the default gateway configured in application env.
  """
  @spec default_gateway() :: gateway()
  def default_gateway, do: Config.get(:default_gateway, :mpesa)

  defp resolve_gateway(gateway) do
    case Map.get(@gateways, gateway) do
      nil -> {:error, %Response{status: :error, message: "Unknown gateway: #{inspect(gateway)}"}}
      mod -> {:ok, mod}
    end
  end
end
