defmodule ZebraPay.Config do
  @moduledoc """
  Centralised configuration management for ZebraPay.

  Configuration is read from the application environment (`:zebrapay` key).
  All values can be overridden at runtime via `put/2`.

  ## Example config/config.exs

      config :zebrapay,
        sandbox: true,
        default_gateway: :mpesa

      config :zebrapay, :mpesa,
        base_url: [
          sandbox: System.get_env("MPESA_SANDBOX_BASE_URL"),
          production: System.get_env("MPESA_PRODUCTION_BASE_URL")
        ],
        consumer_key: System.get_env("MPESA_CONSUMER_KEY"),
        consumer_secret: System.get_env("MPESA_CONSUMER_SECRET"),
        shortcode: System.get_env("MPESA_SHORTCODE"),
        passkey: System.get_env("MPESA_PASSKEY"),
        callback_url: System.get_env("MPESA_CALLBACK_URL"),
        # Each async operation has its own result/timeout URL pair
        b2c_result_url: System.get_env("MPESA_B2C_RESULT_URL"),
        b2c_timeout_url: System.get_env("MPESA_B2C_TIMEOUT_URL"),
        b2b_result_url: System.get_env("MPESA_B2B_RESULT_URL"),
        b2b_timeout_url: System.get_env("MPESA_B2B_TIMEOUT_URL"),
        transaction_status_result_url: System.get_env("MPESA_TRANSACTION_STATUS_RESULT_URL"),
        transaction_status_timeout_url: System.get_env("MPESA_TRANSACTION_STATUS_TIMEOUT_URL"),
        reversal_result_url: System.get_env("MPESA_REVERSAL_RESULT_URL"),
        reversal_timeout_url: System.get_env("MPESA_REVERSAL_TIMEOUT_URL"),
        account_balance_result_url: System.get_env("MPESA_ACCOUNT_BALANCE_RESULT_URL"),
        account_balance_timeout_url: System.get_env("MPESA_ACCOUNT_BALANCE_TIMEOUT_URL"),
        c2b_validation_url: System.get_env("MPESA_C2B_VALIDATION_URL"),
        c2b_confirmation_url: System.get_env("MPESA_C2B_CONFIRMATION_URL"),
        initiator_name: System.get_env("MPESA_INITIATOR_NAME"),
        initiator_password: System.get_env("MPESA_INITIATOR_PASSWORD"),
        # production_cert_path is required for prod B2C/B2B/Transaction
        # Status/Reversal/Balance — sandbox_cert_path is optional
        production_cert_path: System.get_env("MPESA_PRODUCTION_CERT_PATH")

  See `ZebraPay.Gateways.Mpesa` for the full set of M-Pesa config keys
  (B2C/B2B/Transaction Status/Reversal/Balance result & timeout URLs,
  C2B Validation/Confirmation URLs, initiator credentials, certificate
  paths, etc).
  """

  @app :zebrapay

  @doc "Gets a config value. Supports dot-notation via list keys."
  @spec get(atom() | [atom()], any()) :: any()
  def get(key, default \\ nil)

  def get(key, default) when is_atom(key) do
    Application.get_env(@app, key, default)
  end

  def get([gateway_key | rest], default) when is_atom(gateway_key) do
    case Application.get_env(@app, gateway_key) do
      nil -> default
      config when is_list(config) -> get_in(config, rest) || default
      config when is_map(config) -> get_in(config, rest) || default
    end
  end

  @doc "Sets a runtime config value."
  @spec put(atom(), any()) :: :ok
  def put(key, value) do
    Application.put_env(@app, key, value)
  end

  @doc "Returns true if sandbox mode is enabled."
  @spec sandbox?() :: boolean()
  def sandbox?, do: get(:sandbox, true)

  @doc "Returns all config for a specific gateway."
  @spec gateway_config(atom()) :: keyword()
  def gateway_config(gateway) do
    Application.get_env(@app, gateway, [])
  end

  @doc """
  Validates that required gateway config keys are present.
  Raises `ArgumentError` if any are missing.
  """
  @spec validate_gateway_config!(atom(), [atom()]) :: :ok
  def validate_gateway_config!(gateway, required_keys) do
    config = gateway_config(gateway)

    missing =
      required_keys
      |> Enum.filter(fn key -> is_nil(config[key]) end)

    if missing != [] do
      raise ArgumentError,
            "ZebraPay: Missing config for :#{gateway} — #{inspect(missing)}. " <>
              "Set them in config/config.exs or via environment variables."
    end

    :ok
  end
end
