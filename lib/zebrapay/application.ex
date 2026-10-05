defmodule ZebraPay.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Token cache: stores OAuth tokens with TTL to avoid re-fetching on every request
      {ZebraPay.TokenCache, []}

      # Optional: rate limiter (prep for production hardening)
      # {ZebraPay.RateLimiter, []}
    ]

    opts = [strategy: :one_for_one, name: ZebraPay.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule ZebraPay.TokenCache do
  @moduledoc """
  In-memory token cache using ETS.

  Avoids fetching a new OAuth token on every API call by caching
  tokens until they expire. A slot is keyed by whatever the gateway
  passes — M-Pesa uses `{:mpesa, environment, consumer_key}`, so each
  merchant's credentials get their own token.

  ## Usage

      ZebraPay.TokenCache.get(:mpesa)
      # => {:ok, "token..."} or :miss

      ZebraPay.TokenCache.put(:mpesa, "token...", expires_in: 3600)
  """

  use GenServer

  @table :zebrapay_token_cache
  # Evict 30s early to avoid using an almost-expired token
  @clock_skew_seconds 30

  # ── Public API ─────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get(term()) :: {:ok, String.t()} | :miss
  def get(gateway) do
    now = System.system_time(:second)

    case :ets.lookup(@table, gateway) do
      [{^gateway, token, expires_at}] when expires_at > now ->
        {:ok, token}

      _ ->
        :miss
    end
  end

  @spec put(term(), String.t(), keyword()) :: :ok
  def put(gateway, token, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    expires_at = System.system_time(:second) + expires_in - @clock_skew_seconds
    :ets.insert(@table, {gateway, token, expires_at})
    :ok
  end

  @doc """
  Drops a cached token. Given a gateway atom, drops every token cached
  for that gateway, whichever credentials it belongs to.
  """
  @spec clear(term()) :: :ok
  def clear(gateway) when is_atom(gateway) do
    :ets.delete(@table, gateway)
    :ets.match_delete(@table, {{gateway, :_, :_}, :_, :_})
    :ok
  end

  def clear(key) do
    :ets.delete(@table, key)
    :ok
  end

  # ── GenServer callbacks ────────────────────────────────────────────────────

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
