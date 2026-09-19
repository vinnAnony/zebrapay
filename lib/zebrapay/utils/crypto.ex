defmodule ZebraPay.Utils.Crypto do
  @moduledoc """
  Cryptographic utilities used by various gateway integrations.
  """

  @doc """
  Generates an M-Pesa timestamp in the required format: YYYYMMDDHHmmss
  """
  @spec mpesa_timestamp() :: String.t()
  def mpesa_timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  @doc """
  Encrypts a plaintext value with an RSA public key certificate (PEM/DER).
  Used to generate M-Pesa SecurityCredential.
  """
  @spec rsa_encrypt(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def rsa_encrypt(plaintext, cert_path) do
    with true <- File.exists?(cert_path),
         {:ok, cert_pem} <- File.read(cert_path),
         {:ok, public_key} <- extract_public_key(cert_pem),
         {:ok, encrypted} <- do_encrypt(plaintext, public_key) do
      {:ok, Base.encode64(encrypted)}
    else
      false -> {:error, "Certificate not found at #{cert_path}"}
      {:error, reason} -> {:error, "RSA encryption failed: #{inspect(reason)}"}
    end
  end

  # :public_key.encrypt_public/3 raises on bad input (e.g. a malformed
  # key or plaintext too long for it) instead of returning an error
  # tuple — caught here so RSA failures never crash the caller.
  defp do_encrypt(plaintext, public_key) do
    {:ok, :public_key.encrypt_public(plaintext, public_key, rsa_padding: :rsa_pkcs1_padding)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Computes an HMAC-SHA256 signature.
  Returns hex-encoded string.
  """
  @spec hmac_sha256(String.t(), String.t()) :: String.t()
  def hmac_sha256(secret, payload) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Computes an HMAC-SHA512 signature.
  Returns hex-encoded string.
  """
  @spec hmac_sha512(String.t(), String.t()) :: String.t()
  def hmac_sha512(secret, payload) do
    :crypto.mac(:hmac, :sha512, secret, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Secure constant-time string comparison to prevent timing attacks
  when verifying webhook signatures.
  """
  @spec secure_compare(String.t(), String.t()) :: boolean()
  def secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  rescue
    _ -> false
  end

  def secure_compare(_, _), do: false

  @doc """
  Generates a unique idempotency key.
  """
  @spec idempotency_key() :: String.t()
  def idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp extract_public_key(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, cert_der, _}] ->
        cert = :public_key.pkix_decode_cert(cert_der, :otp)
        # cert = {OTPCertificate, tbsCertificate, ...}
        # tbsCertificate elem 7 = subjectPublicKeyInfo = {OTPSubjectPublicKeyInfo, algorithm, subjectPublicKey}
        # elem 1 there is the algorithm identifier, not the key — elem 2 is the actual RSA public key
        public_key = get_in(cert, [Access.elem(1), Access.elem(7), Access.elem(2)])
        {:ok, public_key}

      [{:SubjectPublicKeyInfo, _, _} | _] = entries ->
        [{:SubjectPublicKeyInfo, der, _}] = entries
        {:ok, :public_key.der_decode(:SubjectPublicKeyInfo, der)}

      _ ->
        {:error, "Could not extract public key from certificate"}
    end
  end
end

defmodule ZebraPay.Utils.Phone do
  @moduledoc """
  Phone number formatting utilities for Kenyan (and future African) numbers.
  """

  @doc """
  Formats a phone number to Kenyan international format (254XXXXXXXXX).

  ## Examples

      iex> ZebraPay.Utils.Phone.format_ke("0712345678")
      "254712345678"

      iex> ZebraPay.Utils.Phone.format_ke("+254712345678")
      "254712345678"

      iex> ZebraPay.Utils.Phone.format_ke("254712345678")
      "254712345678"
  """
  @spec format_ke(String.t()) :: String.t()
  def format_ke(phone) do
    phone
    |> String.trim()
    |> String.replace(~r/[\s\-\(\)]/, "")
    |> do_format_ke()
  end

  defp do_format_ke("+" <> rest), do: rest
  defp do_format_ke("0" <> rest), do: "254" <> rest
  defp do_format_ke("254" <> _ = phone), do: phone
  defp do_format_ke(phone), do: phone

  @doc """
  Strips country prefix, returning just the local number (for Airtel Money API).

  ## Examples

      iex> ZebraPay.Utils.Phone.strip_prefix("254712345678")
      "712345678"
  """
  @spec strip_prefix(String.t()) :: String.t()
  def strip_prefix("254" <> rest), do: rest
  def strip_prefix("+" <> rest), do: strip_prefix(rest)
  def strip_prefix("0" <> rest), do: rest
  def strip_prefix(phone), do: phone

  @doc """
  Basic validation: returns true if the number looks like a valid Kenyan mobile.
  """
  @spec valid_ke?(String.t()) :: boolean()
  def valid_ke?(phone) do
    formatted = format_ke(phone)
    String.match?(formatted, ~r/^254[17]\d{8}$/)
  end
end
