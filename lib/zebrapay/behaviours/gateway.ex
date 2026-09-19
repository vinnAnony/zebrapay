defmodule ZebraPay.Gateway do
  @moduledoc """
  Behaviour that all payment gateway modules must implement.

  ## Adding a New Gateway

  To add a new gateway, create a module that `use ZebraPay.Gateway` and
  implement the required callbacks:

      defmodule ZebraPay.Gateways.MyGateway do
        use ZebraPay.Gateway

        @impl true
        def initiate_payment(params), do: ...

        @impl true
        def query_status(transaction_id), do: ...

        @impl true
        def payout(params), do: ...

        @impl true
        def verify_webhook(payload, headers), do: ...

        @impl true
        def validate(params), do: ...
      end

  The macro injects `config/1`, `base_url/0`, and `gateway_name/0` helpers.
  `base_url/0` reads `base_url: [sandbox: "...", production: "..."]` from
  this gateway's own config block and returns `{:ok, url} | {:error, reason}`
  based on the global `config :zebrapay, sandbox: true/false` flag.
  """

  alias ZebraPay.Response

  @type params :: map()
  @type result :: {:ok, Response.t()} | {:error, Response.t()}

  @doc """
  Initiates a payment (STK push, charge, redirect, etc.).
  """
  @callback initiate_payment(params()) :: result()

  @doc """
  Queries the current status of a transaction by ID.
  """
  @callback query_status(transaction_id :: String.t()) :: result()

  @doc """
  Sends money to a customer (B2C / payout).
  Not all gateways support this — default raises `NotImplementedError`.
  """
  @callback payout(params()) :: result()

  @doc """
  Verifies an incoming webhook payload and returns a parsed event map.
  """
  @callback verify_webhook(payload :: map(), headers :: map()) ::
              {:ok, map()} | {:error, String.t()}

  @doc """
  Validates required parameters for the gateway before making an API call.
  Returns `:ok` or `{:error, Response.t()}`.
  """
  @callback validate(params()) :: :ok | {:error, Response.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour ZebraPay.Gateway

      alias ZebraPay.{Config, HTTP, Response, Utils}

      # Default payout: returns not_supported unless overridden
      @impl ZebraPay.Gateway
      def payout(_params) do
        {:error,
         Response.error(
           gateway_name(),
           "Payout (B2C) is not supported by #{gateway_name()}",
           :not_supported
         )}
      end

      defoverridable payout: 1

      # Returns the gateway atom name derived from module name
      defp gateway_name do
        __MODULE__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      end

      # Loads config for this gateway
      defp config(key, default \\ nil) do
        gateway_key = gateway_name()
        Config.get([gateway_key, key], default)
      end

      # Resolves this gateway's base URL for the current environment
      # (sandbox or production) from its
      # `base_url: [sandbox: "...", production: "..."]` config, keyed
      # off the global `config :zebrapay, sandbox: true/false` flag.
      defp base_url do
        env = if Config.sandbox?(), do: :sandbox, else: :production
        urls = config(:base_url, [])

        case Keyword.get(urls, env) do
          url when is_binary(url) and url != "" ->
            {:ok, url}

          _ ->
            {:error,
             "Missing :base_url config for :#{gateway_name()} (#{env} environment). " <>
               "Set base_url: [sandbox: ..., production: ...] in " <>
               "config :zebrapay, :#{gateway_name()}."}
        end
      end
    end
  end
end
