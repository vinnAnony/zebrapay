defmodule ZebraPay.Gateways.MpesaTest do
  # ZebraPay.TokenCache is a single global ETS table, and these tests all
  # use the same consumer key, so it can't safely be shared across
  # concurrently-running tests: async tests would race to cache/clear the
  # same :mpesa token, causing
  # Bypass's oauth expectation to go unmet in whichever test loses the race.
  use ExUnit.Case, async: false

  alias ZebraPay.Gateways.Mpesa
  alias ZebraPay.Response

  # We use Bypass to simulate the Safaricom API locally in tests
  setup do
    # Ensure every test starts with a cache miss, forcing a real (mocked)
    # oauth call instead of reusing a token cached by a previous test.
    ZebraPay.TokenCache.clear(:mpesa)

    bypass = Bypass.open()

    Application.put_env(:zebrapay, :sandbox, true)

    Application.put_env(:zebrapay, :mpesa,
      base_url: [
        sandbox: "http://localhost:#{bypass.port}",
        production: "https://api.safaricom.co.ke"
      ],
      consumer_key: "test_consumer_key",
      consumer_secret: "test_consumer_secret",
      shortcode: "174379",
      passkey: "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919",
      callback_url: "http://localhost/callbacks/mpesa",
      initiator_name: "testapi",
      initiator_password: "Safaricom999!",
      b2c_result_url: "http://localhost/callbacks/mpesa/b2c/result",
      b2c_timeout_url: "http://localhost/callbacks/mpesa/b2c/timeout",
      b2b_result_url: "http://localhost/callbacks/mpesa/b2b/result",
      b2b_timeout_url: "http://localhost/callbacks/mpesa/b2b/timeout",
      transaction_status_result_url: "http://localhost/callbacks/mpesa/transaction_status/result",
      transaction_status_timeout_url:
        "http://localhost/callbacks/mpesa/transaction_status/timeout",
      reversal_result_url: "http://localhost/callbacks/mpesa/reversal/result",
      reversal_timeout_url: "http://localhost/callbacks/mpesa/reversal/timeout",
      account_balance_result_url: "http://localhost/callbacks/mpesa/account_balance/result",
      account_balance_timeout_url: "http://localhost/callbacks/mpesa/account_balance/timeout",
      c2b_validation_url: "http://localhost/callbacks/mpesa/c2b/validation",
      c2b_confirmation_url: "http://localhost/callbacks/mpesa/c2b/confirmation",
      # Throwaway self-signed cert fixture — not a real Safaricom cert,
      # just enough for Utils.Crypto.rsa_encrypt/2 to have a real RSA
      # public key to encrypt against in tests.
      sandbox_cert_path: "test/support/fixtures/test_cert.pem"
    )

    {:ok, bypass: bypass}
  end

  describe "validate/1" do
    test "returns :ok with all required params" do
      params = %{
        phone: "254712345678",
        amount: 100,
        reference: "ORDER-001",
        description: "Test payment"
      }

      assert :ok = Mpesa.validate(params)
    end

    test "returns error when params are missing" do
      params = %{phone: "254712345678"}
      assert {:error, %Response{status: :error, gateway: :mpesa}} = Mpesa.validate(params)
    end
  end

  describe "initiate_payment/1" do
    test "resolves base_url from config, gets a token, and returns pending on success", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        # BusinessShortCode/PartyB must come from config — regression check
        # for a bug where a double-wrapped config key always resolved to nil
        assert decoded["BusinessShortCode"] == "174379"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "MerchantRequestID" => "29115-34620561-1",
            "CheckoutRequestID" => "ws_CO_191220191020363925",
            "ResponseCode" => "0",
            "ResponseDescription" => "Success. Request accepted for processing",
            "CustomerMessage" => "Success. Request accepted for processing"
          })
        )
      end)

      params = %{
        phone: "254712345678",
        amount: 100,
        reference: "ORDER-001",
        description: "Test payment"
      }

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} =
               Mpesa.initiate_payment(params)

      assert resp.transaction_id == "ws_CO_191220191020363925"
    end

    test "returns a clear error when :base_url config is missing" do
      Application.put_env(:zebrapay, :mpesa, consumer_key: "x", consumer_secret: "y")

      params = %{
        phone: "254712345678",
        amount: 100,
        reference: "ORDER-001",
        description: "Test payment"
      }

      assert {:error, %Response{status: :error, gateway: :mpesa, message: message}} =
               Mpesa.initiate_payment(params)

      assert message =~ "base_url"
    end
  end

  describe "query_status/1" do
    test "resolves base_url, fetches a token, and returns success when the STK push completed",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["BusinessShortCode"] == "174379"
        assert decoded["CheckoutRequestID"] == "ws_CO_191220191020363925"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "ResponseCode" => "0",
            "ResponseDescription" => "The service request has been accepted successfully",
            "MerchantRequestID" => "29115-34620561-1",
            "CheckoutRequestID" => "ws_CO_191220191020363925",
            "ResultCode" => "0",
            "ResultDesc" => "The service request is processed successfully."
          })
        )
      end)

      assert {:ok, %Response{status: :success, gateway: :mpesa} = resp} =
               Mpesa.query_status("ws_CO_191220191020363925")

      assert resp.transaction_id == "ws_CO_191220191020363925"
    end

    test "returns a failed response when the STK push was cancelled/failed", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "ResultCode" => "1032",
            "ResultDesc" => "Request cancelled by user."
          })
        )
      end)

      assert {:ok, %Response{status: :failed, gateway: :mpesa} = resp} =
               Mpesa.query_status("ws_CO_191220191020363925")

      assert resp.message == "Request cancelled by user."
    end
  end

  describe "payout/1 (B2C)" do
    test "resolves base_url, fetches a token, RSA-encrypts the SecurityCredential, and returns pending on success",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/b2c/v3/paymentrequest", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["CommandID"] == "BusinessPayment"
        assert decoded["PartyA"] == "174379"
        assert decoded["PartyB"] == "254712345678"
        assert decoded["InitiatorName"] == "testapi"
        assert is_binary(decoded["SecurityCredential"]) and decoded["SecurityCredential"] != ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "Accept the service request successfully."
          })
        )
      end)

      params = %{phone: "254712345678", amount: 500, occasion: "Refund", remarks: "Order refund"}

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} = Mpesa.payout(params)
      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end
  end

  describe "verify_webhook/2" do
    test "parses a successful STK callback" do
      payload = %{
        "Body" => %{
          "stkCallback" => %{
            "MerchantRequestID" => "29115-34620561-1",
            "CheckoutRequestID" => "ws_CO_191220191020363925",
            "ResultCode" => 0,
            "ResultDesc" => "The service request is processed successfully.",
            "CallbackMetadata" => %{
              "Item" => [
                %{"Name" => "Amount", "Value" => 1},
                %{"Name" => "MpesaReceiptNumber", "Value" => "NLJ7RT61SV"},
                %{"Name" => "TransactionDate", "Value" => 20_191_219_102_115},
                %{"Name" => "PhoneNumber", "Value" => 254_708_374_149}
              ]
            }
          }
        }
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :success
      assert event.transaction_id == "NLJ7RT61SV"
      assert event.amount == 1
    end

    test "parses a failed STK callback" do
      payload = %{
        "Body" => %{
          "stkCallback" => %{
            "MerchantRequestID" => "29115-34620561-1",
            "CheckoutRequestID" => "ws_CO_191220191020363925",
            "ResultCode" => 1032,
            "ResultDesc" => "Request cancelled by user."
          }
        }
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :failed
    end

    test "parses a successful Result callback (B2C/B2B/TransactionStatus/Reversal)" do
      payload = %{
        "Result" => %{
          "ResultType" => 0,
          "ResultCode" => 0,
          "ResultDesc" => "The service request is processed successfully.",
          "OriginatorConversationID" => "29112-34801843-1",
          "ConversationID" => "AG_20191219_00005797af5d7d75f652",
          "TransactionID" => "NLJ7RT61SV",
          "ResultParameters" => %{
            "ResultParameter" => [
              %{"Key" => "TransactionAmount", "Value" => 100},
              %{"Key" => "TransactionReceipt", "Value" => "NLJ7RT61SV"}
            ]
          }
        }
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :success
      assert event.transaction_id == "NLJ7RT61SV"
      assert event.amount == 100
    end

    test "parses a failed Result callback" do
      payload = %{
        "Result" => %{
          "ResultType" => 0,
          "ResultCode" => 1,
          "ResultDesc" => "Insufficient balance."
        }
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :failed
    end

    test "parses the pipe-delimited AccountBalance result parameter" do
      payload = %{
        "Result" => %{
          "ResultType" => 0,
          "ResultCode" => 0,
          "ResultDesc" => "The service request is processed successfully.",
          "TransactionID" => "NLJ7RT61SV",
          "ResultParameters" => %{
            "ResultParameter" => [
              %{
                "Key" => "AccountBalance",
                "Value" =>
                  "Working Account|KES|481000.00|481000.00|0.00|0.00&Utility Account|KES|0.00|0.00|0.00|0.00"
              },
              %{"Key" => "BOCompletedTime", "Value" => 20_191_219_102_115}
            ]
          }
        }
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :success
      assert [working, utility] = event.metadata["AccountBalance"]
      assert working.account == "Working Account"
      assert working.currency == "KES"
      assert working.available_balance == "481000.00"
      assert utility.account == "Utility Account"
    end

    test "parses a C2B Validation/Confirmation payload" do
      payload = %{
        "TransactionType" => "Pay Bill",
        "TransID" => "RKTQDM7W6S",
        "TransTime" => "20191122063845",
        "TransAmount" => "10",
        "BusinessShortCode" => "600638",
        "BillRefNumber" => "invoice008",
        "InvoiceNumber" => "",
        "OrgAccountBalance" => "49197.00",
        "ThirdPartyTransID" => "",
        "MSISDN" => "254708374149",
        "FirstName" => "John"
      }

      assert {:ok, event} = Mpesa.verify_webhook(payload, %{})
      assert event.status == :success
      assert event.transaction_id == "RKTQDM7W6S"
      assert event.amount == "10"
      assert event.phone == "254708374149"
      assert event.reference == "invoice008"
      assert event.metadata["FirstName"] == "John"
    end
  end

  describe "business_payment/1 (B2B)" do
    test "returns error when required params are missing" do
      assert {:error, %Response{status: :error, gateway: :mpesa}} =
               Mpesa.business_payment(%{amount: 100})
    end

    test "resolves base_url, fetches a token, RSA-encrypts the SecurityCredential, and returns pending on success",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/b2b/v1/paymentrequest", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["CommandID"] == "BusinessPayBill"
        assert decoded["PartyA"] == "174379"
        assert decoded["PartyB"] == "600001"
        assert decoded["AccountReference"] == "INV-001"
        assert is_binary(decoded["SecurityCredential"]) and decoded["SecurityCredential"] != ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "Accept the service request successfully."
          })
        )
      end)

      params = %{
        amount: 1000,
        party_b: "600001",
        account_reference: "INV-001",
        remarks: "Supplier payment"
      }

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} =
               Mpesa.business_payment(params)

      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end
  end

  describe "transaction_status/1" do
    test "returns error when transaction_id is missing" do
      assert {:error, %Response{status: :error, gateway: :mpesa}} =
               Mpesa.transaction_status(%{})
    end

    test "resolves base_url, fetches a token, RSA-encrypts the SecurityCredential, and returns pending on success",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/transactionstatus/v1/query", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["CommandID"] == "TransactionStatusQuery"
        assert decoded["TransactionID"] == "OEI2AK4Q16"
        assert decoded["PartyA"] == "174379"
        assert is_binary(decoded["SecurityCredential"]) and decoded["SecurityCredential"] != ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "Accept the service request successfully."
          })
        )
      end)

      params = %{transaction_id: "OEI2AK4Q16"}

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} =
               Mpesa.transaction_status(params)

      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end
  end

  describe "reverse/1" do
    test "returns error when required params are missing" do
      assert {:error, %Response{status: :error, gateway: :mpesa}} =
               Mpesa.reverse(%{transaction_id: "NLJ7RT61SV"})
    end

    test "resolves base_url, fetches a token, RSA-encrypts the SecurityCredential, and returns pending on success",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/reversal/v1/request", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["CommandID"] == "TransactionReversal"
        assert decoded["TransactionID"] == "OEI2AK4Q16"
        assert decoded["Amount"] == 100
        assert is_binary(decoded["SecurityCredential"]) and decoded["SecurityCredential"] != ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "Accept the service request successfully."
          })
        )
      end)

      params = %{transaction_id: "OEI2AK4Q16", amount: 100, remarks: "Wrong recipient"}

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} = Mpesa.reverse(params)
      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end
  end

  describe "account_balance/1" do
    test "resolves base_url, fetches a token, RSA-encrypts the SecurityCredential, and returns pending on success",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/accountbalance/v1/query", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["CommandID"] == "AccountBalance"
        assert decoded["PartyA"] == "174379"
        assert decoded["Initiator"] == "testapi"
        assert is_binary(decoded["SecurityCredential"]) and decoded["SecurityCredential"] != ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "Accept the service request successfully."
          })
        )
      end)

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} =
               Mpesa.account_balance()

      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end

    test "returns a clear error when the sandbox cert can't be found", %{bypass: bypass} do
      Application.put_env(
        :zebrapay,
        :mpesa,
        Keyword.put(Application.get_env(:zebrapay, :mpesa), :sandbox_cert_path, "nope.cer")
      )

      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      assert {:error, %Response{status: :error, gateway: :mpesa, message: message}} =
               Mpesa.account_balance()

      assert message =~ "Certificate not found"
    end

    test "returns a clear error when :production_cert_path is missing in production", %{
      bypass: bypass
    } do
      Application.put_env(:zebrapay, :sandbox, false)

      mpesa_config = Application.get_env(:zebrapay, :mpesa)
      # Route "production" at Bypass too, so this test never touches the
      # real Safaricom API while exercising the sandbox: false branch.
      base_urls =
        Keyword.put(mpesa_config[:base_url], :production, "http://localhost:#{bypass.port}")

      Application.put_env(:zebrapay, :mpesa, Keyword.put(mpesa_config, :base_url, base_urls))

      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      assert {:error, %Response{status: :error, gateway: :mpesa, message: message}} =
               Mpesa.account_balance()

      assert message =~ "production_cert_path"
    end
  end

  describe "register_c2b_urls/1" do
    test "returns an error when c2b_validation_url is missing" do
      Application.put_env(
        :zebrapay,
        :mpesa,
        Keyword.delete(Application.get_env(:zebrapay, :mpesa), :c2b_validation_url)
      )

      assert {:error, %Response{status: :error, gateway: :mpesa, message: message}} =
               Mpesa.register_c2b_urls()

      assert message =~ "c2b_validation_url"
    end

    test "returns an error when c2b_confirmation_url is missing" do
      Application.put_env(
        :zebrapay,
        :mpesa,
        Keyword.delete(Application.get_env(:zebrapay, :mpesa), :c2b_confirmation_url)
      )

      assert {:error, %Response{status: :error, gateway: :mpesa, message: message}} =
               Mpesa.register_c2b_urls()

      assert message =~ "c2b_confirmation_url"
    end

    test "resolves base_url, fetches a token (no SecurityCredential needed), and registers the configured URLs",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"access_token" => "test_token", "expires_in" => "3599"})
        )
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/c2b/v2/registerurl", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["ShortCode"] == "174379"
        assert decoded["ResponseType"] == "Completed"
        assert decoded["ValidationURL"] == "http://localhost/callbacks/mpesa/c2b/validation"
        assert decoded["ConfirmationURL"] == "http://localhost/callbacks/mpesa/c2b/confirmation"
        refute Map.has_key?(decoded, "SecurityCredential")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0",
            "ResponseDescription" => "success"
          })
        )
      end)

      assert {:ok, %Response{status: :pending, gateway: :mpesa} = resp} =
               Mpesa.register_c2b_urls()

      assert resp.transaction_id == "AG_20191219_00005797af5d7d75f652"
    end
  end

  describe "validation_response/1" do
    test "builds the accept body" do
      assert Mpesa.validation_response(:accept) == %{
               "ResultCode" => 0,
               "ResultDesc" => "Accepted"
             }
    end

    test "builds a reject body with the generic error code" do
      assert Mpesa.validation_response({:reject, "Invalid account number"}) == %{
               "ResultCode" => "C2B00016",
               "ResultDesc" => "Invalid account number"
             }
    end

    test "builds a reject body with a specific error code" do
      assert Mpesa.validation_response({:reject, "C2B00012", "Invalid account number"}) == %{
               "ResultCode" => "C2B00012",
               "ResultDesc" => "Invalid account number"
             }
    end
  end

  describe "per-call config (multiple merchants)" do
    defp token_response(conn, token) do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"access_token" => token, "expires_in" => "3599"}))
    end

    defp basic_auth(conn) do
      ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
      Base.decode64!(encoded)
    end

    defp stk_ok(conn) do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "MerchantRequestID" => "29115-34620561-1",
          "CheckoutRequestID" => "ws_CO_191220191020363925",
          "ResponseCode" => "0",
          "CustomerMessage" => "Success. Request accepted for processing"
        })
      )
    end

    @stk_params %{phone: "0712345678", amount: 100, reference: "INV-1", description: "Rent"}

    test "uses the merchant's credentials, shortcode and callback URL instead of app config",
         %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        assert basic_auth(conn) == "merchant_a_key:merchant_a_secret"
        token_response(conn, "token_a")
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token_a"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["BusinessShortCode"] == "600111"
        assert decoded["PartyB"] == "600111"
        assert decoded["CallBackURL"] == "http://localhost/callbacks/daraja/a/stk"

        assert Base.decode64!(decoded["Password"]) ==
                 "600111" <> "passkey_a" <> decoded["Timestamp"]

        stk_ok(conn)
      end)

      merchant = [
        consumer_key: "merchant_a_key",
        consumer_secret: "merchant_a_secret",
        shortcode: "600111",
        passkey: "passkey_a",
        callback_url: "http://localhost/callbacks/daraja/a/stk"
      ]

      assert {:ok, %Response{status: :pending}} =
               Mpesa.initiate_payment(@stk_params, config: merchant)
    end

    test "accepts the config as a map and through the ZebraPay facade", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", fn conn ->
        assert basic_auth(conn) == "map_key:map_secret"
        token_response(conn, "token_map")
      end)

      Bypass.expect_once(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["BusinessShortCode"] == "600333"
        stk_ok(conn)
      end)

      merchant = %{consumer_key: "map_key", consumer_secret: "map_secret", shortcode: "600333"}

      assert {:ok, %Response{status: :pending}} =
               ZebraPay.initiate_payment(:mpesa, @stk_params, config: merchant)
    end

    test "caches one token per merchant, so merchants never share a token", %{bypass: bypass} do
      test_pid = self()

      Bypass.expect(bypass, "GET", "/oauth/v1/generate", fn conn ->
        [key, _secret] = conn |> basic_auth() |> String.split(":")
        send(test_pid, {:token_fetched, key})
        token_response(conn, "token_for_" <> key)
      end)

      Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
        ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:pushed, Jason.decode!(body)["BusinessShortCode"], token})
        stk_ok(conn)
      end)

      a = [consumer_key: "key_a", consumer_secret: "s", shortcode: "600111"]
      b = [consumer_key: "key_b", consumer_secret: "s", shortcode: "600222"]

      assert {:ok, _} = Mpesa.initiate_payment(@stk_params, config: a)
      assert {:ok, _} = Mpesa.initiate_payment(@stk_params, config: b)
      assert {:ok, _} = Mpesa.initiate_payment(@stk_params, config: a)

      assert_received {:pushed, "600111", "token_for_key_a"}
      assert_received {:pushed, "600222", "token_for_key_b"}
      assert_received {:pushed, "600111", "token_for_key_a"}

      # The third call reused merchant A's cached token
      assert_received {:token_fetched, "key_a"}
      assert_received {:token_fetched, "key_b"}
      refute_received {:token_fetched, _}
    end

    test "sandbox: false in the call's config selects the production base URL and cert",
         %{bypass: bypass} do
      Application.put_env(
        :zebrapay,
        :mpesa,
        Keyword.put(Application.get_env(:zebrapay, :mpesa), :base_url,
          sandbox: "http://localhost:1",
          production: "http://localhost:#{bypass.port}"
        )
      )

      Bypass.expect_once(bypass, "GET", "/oauth/v1/generate", &token_response(&1, "prod_token"))

      Bypass.expect_once(bypass, "POST", "/mpesa/reversal/v1/request", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["Initiator"] == "merchant_initiator"
        assert decoded["ReceiverParty"] == "600111"
        assert decoded["ResultURL"] == "http://localhost/callbacks/daraja/a/reversal/result"

        assert decoded["QueueTimeOutURL"] ==
                 "http://localhost/callbacks/daraja/a/reversal/timeout"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "OriginatorConversationID" => "29112-34801843-1",
            "ConversationID" => "AG_20191219_00005797af5d7d75f652",
            "ResponseCode" => "0"
          })
        )
      end)

      merchant = [
        sandbox: false,
        consumer_key: "prod_key",
        consumer_secret: "prod_secret",
        shortcode: "600111",
        initiator_name: "merchant_initiator",
        initiator_password: "secret",
        production_cert_path: "test/support/fixtures/test_cert.pem"
      ]

      params = %{
        transaction_id: "OEI2AK4Q16",
        amount: 100,
        result_url: "http://localhost/callbacks/daraja/a/reversal/result",
        timeout_url: "http://localhost/callbacks/daraja/a/reversal/timeout"
      }

      assert {:ok, %Response{status: :pending}} = Mpesa.reverse(params, config: merchant)
    end
  end
end

defmodule ZebraPay.Utils.PhoneTest do
  use ExUnit.Case, async: true

  alias ZebraPay.Utils.Phone

  describe "format_ke/1" do
    test "formats local number to international" do
      assert Phone.format_ke("0712345678") == "254712345678"
    end

    test "strips + prefix" do
      assert Phone.format_ke("+254712345678") == "254712345678"
    end

    test "leaves already formatted number unchanged" do
      assert Phone.format_ke("254712345678") == "254712345678"
    end

    test "strips spaces" do
      assert Phone.format_ke("0712 345 678") == "254712345678"
    end
  end

  describe "valid_ke?/1" do
    test "returns true for valid Safaricom number" do
      assert Phone.valid_ke?("254712345678")
      assert Phone.valid_ke?("0712345678")
    end

    test "returns false for invalid number" do
      refute Phone.valid_ke?("12345")
      refute Phone.valid_ke?("254812345678")
    end
  end
end

defmodule ZebraPay.ResponseTest do
  use ExUnit.Case, async: true

  alias ZebraPay.Response

  test "success/2 builds correct struct" do
    resp = Response.success(:mpesa, %{transaction_id: "TXN123", amount: 100})
    assert resp.status == :success
    assert resp.gateway == :mpesa
    assert resp.transaction_id == "TXN123"
    assert Response.success?(resp)
  end

  test "pending/2 builds correct struct" do
    resp = Response.pending(:mpesa, %{reference: "REF-001"})
    assert resp.status == :pending
    assert Response.pending?(resp)
    refute Response.success?(resp)
  end

  test "error/3 builds error struct" do
    resp = Response.error(:mpesa, "Something went wrong")
    assert resp.status == :error
    assert resp.message == "Something went wrong"
  end

  test "to_map/1 converts to plain map" do
    resp = Response.success(:mpesa)
    map = Response.to_map(resp)
    assert is_map(map)
    assert map.status == :success
  end
end
