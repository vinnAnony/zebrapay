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

  The macro injects `config/3`, `base_url/1`, `sandbox?/1`, and
  `gateway_name/0` helpers, each taking the call's `opts` so a
  `config: [...]` entry can override application config per call.
  `base_url/1` reads `base_url: [sandbox: "...", production: "..."]` from
  this gateway's own config block and returns `{:ok, url} | {:error, reason}`
  based on the global `config :zebrapay, sandbox: true/false` flag.
  """

  alias ZebraPay.Response

  @type params :: map()
  @type opts :: keyword()
  @type result :: {:ok, Response.t()} | {:error, Response.t()}

  @doc """
  Initiates a payment (STK push, charge, redirect, etc.).
  """
  @callback initiate_payment(params()) :: result()

  @doc """
  Same as `c:initiate_payment/1`, with per-call options. `config: [...]`
  overrides this gateway's application config for the one call — see
  `ZebraPay.Config.resolve/4`.
  """
  @callback initiate_payment(params(), opts()) :: result()

  @doc """
  Queries the current status of a transaction by ID.
  """
  @callback query_status(transaction_id :: String.t()) :: result()
  @callback query_status(transaction_id :: String.t(), opts()) :: result()

  @doc """
  Sends money to a customer (B2C / payout).
  Not all gateways support this — default raises `NotImplementedError`.
  """
  @callback payout(params()) :: result()
  @callback payout(params(), opts()) :: result()

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
      def payout(_params, _opts \\ []) do
        {:error,
         Response.error(
           gateway_name(),
           "Payout (B2C) is not supported by #{gateway_name()}",
           :not_supported
         )}
      end

      defoverridable payout: 1, payout: 2

      # Returns the gateway atom name derived from module name
      defp gateway_name do
        __MODULE__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      end

      # Loads config for this gateway — a `config: [...]` entry in the
      # call's opts wins over application config, key by key
      defp config(opts, key, default \\ nil) do
        Config.resolve(gateway_name(), opts, key, default)
      end

      defp sandbox?(opts), do: Config.sandbox?(opts)

      # Resolves this gateway's base URL for the current environment
      # (sandbox or production) from its
      # `base_url: [sandbox: "...", production: "..."]` config, keyed
      # off the `sandbox` flag — per call if given, else the global
      # `config :zebrapay, sandbox: true/false`.
      defp base_url(opts) do
        env = if sandbox?(opts), do: :sandbox, else: :production
        urls = config(opts, :base_url, [])

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
