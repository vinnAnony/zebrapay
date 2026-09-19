defmodule ZebraPay.WebhookPlug do
  @moduledoc """
  A `Plug` for handling payment gateway webhooks in Phoenix applications.

  Reads the raw body (required for signature verification), then routes
  to the appropriate gateway handler.

  ## Usage in Phoenix Router

      # router.ex
      scope "/webhooks" do
        pipe_through :webhook

        post "/mpesa", ZebraPay.WebhookPlug, gateway: :mpesa
      end

  ## With custom handler

      post "/mpesa", ZebraPay.WebhookPlug,
        gateway: :mpesa,
        handler: MyApp.Payments.MpesaWebhookHandler

  The `handler` module must implement:

      @callback handle_event(map()) :: :ok | {:error, any()}

  ## Raw body preservation

  Add to your endpoint.ex BEFORE Plug.Parsers:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {ZebraPay.WebhookPlug, :read_body, []},
        json_decoder: Jason
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    gateway = Keyword.fetch!(opts, :gateway)
    handler = Keyword.get(opts, :handler)

    headers = conn |> get_req_header_map()
    body = conn.assigns[:raw_body] || ""

    payload =
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    case ZebraPay.verify_webhook(gateway, payload, headers) do
      {:ok, event} ->
        if handler, do: handler.handle_event(event)

        Logger.info(
          "[ZebraPay.Webhook] #{gateway} event received: #{inspect(event.status || :unknown)}"
        )

        send_resp(conn, 200, "OK")

      {:error, reason} ->
        Logger.warning("[ZebraPay.Webhook] #{gateway} webhook verification failed: #{reason}")
        send_resp(conn, 400, "Bad Request")
    end
  end

  @doc """
  Body reader for `Plug.Parsers` — preserves raw body in conn.assigns
  so it can be used for signature verification before parsing.
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], fn _ -> body end)
    {:ok, body, conn}
  end

  defp get_req_header_map(conn) do
    conn.req_headers
    |> Enum.into(%{})
  end
end
