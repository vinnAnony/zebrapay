defmodule ZebraPay.Utils.CryptoTest do
  use ExUnit.Case, async: true

  alias ZebraPay.Utils.Crypto

  describe "rsa_encrypt/2" do
    test "encrypts successfully against the bundled M-Pesa sandbox cert" do
      cert_path = Application.app_dir(:zebrapay, "priv/certs/mpesa_sandbox.cer")

      assert {:ok, encoded} = Crypto.rsa_encrypt("Safaricom999!", cert_path)
      assert is_binary(encoded)
      assert {:ok, _decoded} = Base.decode64(encoded)
    end

    test "encrypts successfully against a throwaway self-signed test cert" do
      assert {:ok, encoded} =
               Crypto.rsa_encrypt("some-secret", "test/support/fixtures/test_cert.pem")

      assert is_binary(encoded)
    end

    test "returns a clear error when the cert file doesn't exist" do
      assert {:error, message} = Crypto.rsa_encrypt("x", "does/not/exist.cer")
      assert message =~ "Certificate not found"
    end

    test "returns an error tuple, not a crash, for a malformed cert file" do
      path = Path.join(System.tmp_dir!(), "zebrapay_malformed_cert_test.cer")
      File.write!(path, "not a real certificate")

      assert {:error, _reason} = Crypto.rsa_encrypt("x", path)

      File.rm(path)
    end
  end

  describe "mpesa_timestamp/0" do
    test "returns a 14-digit YYYYMMDDHHmmss timestamp" do
      assert Crypto.mpesa_timestamp() =~ ~r/^\d{14}$/
    end
  end

  describe "hmac_sha256/2 and hmac_sha512/2" do
    test "produce hex-encoded signatures of the expected length" do
      assert Crypto.hmac_sha256("secret", "payload") =~ ~r/^[0-9a-f]{64}$/
      assert Crypto.hmac_sha512("secret", "payload") =~ ~r/^[0-9a-f]{128}$/
    end
  end

  describe "secure_compare/2" do
    test "returns true for equal strings" do
      assert Crypto.secure_compare("abc", "abc")
    end

    test "returns false for different strings of the same length" do
      refute Crypto.secure_compare("abc", "abd")
    end

    test "returns false for strings of different length" do
      refute Crypto.secure_compare("abc", "abcd")
    end
  end
end
