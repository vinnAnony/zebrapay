import Config

# ─────────────────────────────────────────────────────────────────────────────
# ZebraPay — Development / Sandbox Configuration
# Copy this to config/dev.exs and fill in your sandbox credentials.
# NEVER commit real credentials to version control.
# ─────────────────────────────────────────────────────────────────────────────

config :zebrapay,
  sandbox: true,
  default_gateway: :mpesa

# ── M-Pesa (Safaricom Daraja) ─────────────────────────────────────────────────
# Sandbox credentials from: https://developer.safaricom.co.ke
config :zebrapay, :mpesa,
  base_url: [
    sandbox: System.get_env("MPESA_SANDBOX_BASE_URL", "https://sandbox.safaricom.co.ke"),
    production: System.get_env("MPESA_PRODUCTION_BASE_URL", "https://api.safaricom.co.ke")
  ],
  consumer_key: System.get_env("MPESA_CONSUMER_KEY", "your_sandbox_consumer_key"),
  consumer_secret: System.get_env("MPESA_CONSUMER_SECRET", "your_sandbox_consumer_secret"),
  shortcode: System.get_env("MPESA_SHORTCODE", "174379"),
  passkey: System.get_env("MPESA_PASSKEY", "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919"),
  callback_url: System.get_env("MPESA_CALLBACK_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa"),
  # Each async operation gets its own result/timeout URL pair, so you can
  # route each one to a distinct handler instead of inspecting the
  # callback payload to figure out which operation it belongs to.
  b2c_result_url: System.get_env("MPESA_B2C_RESULT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/b2c/result"),
  b2c_timeout_url: System.get_env("MPESA_B2C_TIMEOUT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/b2c/timeout"),
  b2b_result_url: System.get_env("MPESA_B2B_RESULT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/b2b/result"),
  b2b_timeout_url: System.get_env("MPESA_B2B_TIMEOUT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/b2b/timeout"),
  transaction_status_result_url: System.get_env("MPESA_TRANSACTION_STATUS_RESULT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/transaction_status/result"),
  transaction_status_timeout_url: System.get_env("MPESA_TRANSACTION_STATUS_TIMEOUT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/transaction_status/timeout"),
  reversal_result_url: System.get_env("MPESA_REVERSAL_RESULT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/reversal/result"),
  reversal_timeout_url: System.get_env("MPESA_REVERSAL_TIMEOUT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/reversal/timeout"),
  account_balance_result_url: System.get_env("MPESA_ACCOUNT_BALANCE_RESULT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/account_balance/result"),
  account_balance_timeout_url: System.get_env("MPESA_ACCOUNT_BALANCE_TIMEOUT_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/account_balance/timeout"),
  # C2B (see ZebraPay.Gateways.Mpesa.register_c2b_urls/1). ValidationURL
  # is only called if Safaricom has enabled validation for your shortcode.
  c2b_validation_url: System.get_env("MPESA_C2B_VALIDATION_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/c2b/validation"),
  c2b_confirmation_url: System.get_env("MPESA_C2B_CONFIRMATION_URL", "https://your-ngrok.ngrok.io/webhooks/mpesa/c2b/confirmation"),
  initiator_name: System.get_env("MPESA_INITIATOR_NAME", "testapi"),
  initiator_password: System.get_env("MPESA_INITIATOR_PASSWORD", "Safaricom999!"),
  # Needed for B2C/B2B/Transaction Status/Reversal/Account Balance — see
  # priv/certs/README.md. Omit sandbox_cert_path to use this library's
  # bundled sandbox cert; production_cert_path has no default.
  sandbox_cert_path: System.get_env("MPESA_SANDBOX_CERT_PATH"),
  production_cert_path: System.get_env("MPESA_PRODUCTION_CERT_PATH")
