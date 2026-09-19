defmodule ZebraPay.Response do
  @moduledoc """
  Unified response struct returned by all gateway operations.

  This normalises wildly different API responses from each gateway
  into a consistent shape your application can rely on.

  ## Status values

  - `:pending`   — payment initiated, awaiting user action (e.g. STK push sent)
  - `:success`   — payment confirmed successful
  - `:failed`    — payment failed
  - `:cancelled` — payment cancelled by user
  - `:error`     — library or network error (not a payment failure)
  - `:not_supported` — operation not supported by this gateway
  """

  @type status ::
          :pending | :success | :failed | :cancelled | :error | :not_supported

  @type t :: %__MODULE__{
          status: status(),
          gateway: atom(),
          transaction_id: String.t() | nil,
          reference: String.t() | nil,
          amount: number() | nil,
          currency: String.t() | nil,
          phone: String.t() | nil,
          message: String.t() | nil,
          raw: map() | nil,
          metadata: map()
        }

  defstruct [
    :status,
    :gateway,
    :transaction_id,
    :reference,
    :amount,
    :currency,
    :phone,
    :message,
    :raw,
    metadata: %{}
  ]

  @doc "Builds a success response."
  @spec success(atom(), map()) :: t()
  def success(gateway, attrs \\ %{}) do
    struct(__MODULE__, Map.merge(%{status: :success, gateway: gateway}, attrs))
  end

  @doc "Builds a pending response (payment initiated, waiting for user)."
  @spec pending(atom(), map()) :: t()
  def pending(gateway, attrs \\ %{}) do
    struct(__MODULE__, Map.merge(%{status: :pending, gateway: gateway}, attrs))
  end

  @doc "Builds an error response."
  @spec error(atom(), String.t(), atom()) :: t()
  def error(gateway, message, status \\ :error) do
    %__MODULE__{
      status: status,
      gateway: gateway,
      message: message
    }
  end

  @doc "Builds a failed payment response."
  @spec failed(atom(), String.t(), map()) :: t()
  def failed(gateway, message, attrs \\ %{}) do
    struct(
      __MODULE__,
      Map.merge(%{status: :failed, gateway: gateway, message: message}, attrs)
    )
  end

  @doc "Returns true if the response represents a terminal success."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: :success}), do: true
  def success?(_), do: false

  @doc "Returns true if the response is still pending (awaiting confirmation)."
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(_), do: false

  @doc "Converts to a plain map for serialisation."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = r), do: Map.from_struct(r)
end
