# M-Pesa certificates

`ZebraPay.Gateways.Mpesa` needs Safaricom's public certificate to
RSA-encrypt the `SecurityCredential` used by B2C, B2B, Transaction
Status, Reversal, and Account Balance.

## Sandbox

`mpesa_sandbox.cer` is bundled here. It's Safaricom's real sandbox
certificate (`CN=apicrypt.safaricom.co.ke`, issued by `Safaricom
Internal Issuing CA 02`) — public and identical for every Daraja
developer, so it ships with this library and needs no setup. (Its
validity window is long expired — that's expected and harmless, since
RSA encryption only uses the key material, never checks cert dates.)

This is the default `ZebraPay.Gateways.Mpesa` looks for when
`config :zebrapay, sandbox: true` and no `sandbox_cert_path` is set —
see `config :zebrapay, :mpesa` in the README. Set `sandbox_cert_path`
yourself only if you need to override it (e.g. Safaricom rotates the
sandbox cert and this library hasn't been updated yet).

## Production

**Do not put a production cert here.** It's issued by Safaricom to
your specific shortcode during Daraja go-live, so it can't be shared
across every app using this library. Keep it in your own application
(e.g. `priv/certs/mpesa_prod.cer` in *your* app) and point
`production_cert_path` at it:

    config :zebrapay, :mpesa,
      production_cert_path: Application.app_dir(:my_app, "priv/certs/mpesa_prod.cer")
