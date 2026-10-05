# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Multi-merchant support: every M-Pesa call (and `ZebraPay.initiate_payment/3`,
  `query_status/3`, `payout/3`) takes a `config: [...]` option that
  overrides application config for that call, including `:sandbox`.
- Per-call `:result_url` / `:timeout_url` for B2C, B2B, Transaction
  Status, Reversal and Account Balance.
- Per-call `:transaction_type` and `:party_b` for STK Push (Buy Goods tills).

### Changed

- OAuth tokens are cached per consumer key and environment instead of
  per gateway. `ZebraPay.TokenCache.clear(:mpesa)` still clears them all.

## [0.1.0] - 2026-09-19

### Added

- Initial release.
- M-Pesa (Daraja 3.0) gateway: STK Push, B2C, B2B, Transaction Status,
  Account Balance, and Reversal.
- `ZebraPay.WebhookPlug` for handling gateway callbacks in Phoenix apps.
- `ZebraPay.Gateway` behaviour for adding new payment gateways.
- Unified `ZebraPay.Response` struct across gateway operations.
- OAuth token caching for M-Pesa via `ZebraPay.TokenCache`.
