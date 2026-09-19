defmodule ZebraPay.HTTP do
  @moduledoc """
  Thin HTTP wrapper around `Req` with shared retry logic,
  timeout defaults, and consistent error handling.

  All gateway modules use this instead of calling Req directly,
  so we can swap the underlying HTTP client without touching gateway code.
  """

  require Logger

  @default_timeout 30_000
  @default_retries 2

  @doc """
  Makes a POST request.
  Returns `{:ok, response_body}` or `{:error, reason}`.
  """
  @spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def post(url, body, opts \\ []) do
    request(:post, url, body, opts)
  end

  @doc """
  Makes a GET request.
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def get(url, opts \\ []) do
    request(:get, url, nil, opts)
  end

  defp request(method, url, body, opts) do
    headers = Keyword.get(opts, :headers, [])
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: timeout,
        retry: :transient,
        max_retries: retries
      ]
      |> then(fn o -> if body, do: Keyword.put(o, :json, body), else: o end)

    Logger.debug("[ZebraPay.HTTP] #{String.upcase(to_string(method))} #{url}")

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("[ZebraPay.HTTP] Non-2xx response: #{status} from #{url}")
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("[ZebraPay.HTTP] Transport error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("[ZebraPay.HTTP] Error: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
